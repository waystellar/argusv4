#!/usr/bin/env python3
"""
Argus GPS Service - Production-Ready NMEA GPS Reader

Reads NMEA sentences from a GPS device and publishes position data via ZMQ.
Supports USB GPS dongles, UART GPS modules, and gpsd.

Hardware Support:
    - USB GPS dongles (e.g., u-blox, GlobalSat)
    - UART GPS modules (e.g., NEO-6M, NEO-M8N)
    - gpsd daemon

Output:
    ZMQ PUB on tcp://*:5558
    JSON payload with lat, lon, speed, heading, etc.

Usage:
    python gps_service.py --device /dev/argus_gps
    python gps_service.py --device /dev/ttyUSB0 --baud 9600
    python gps_service.py --gpsd

Environment Variables:
    ARGUS_GPS_DEVICE - Serial device path (default: /dev/argus_gps)
    ARGUS_GPS_BAUD   - Baud rate (default: 9600)
    ARGUS_GPS_HZ     - Output rate in Hz (default: 10)
    ARGUS_LOG_LEVEL  - Logging level
"""
import argparse
import asyncio
import json
import logging
import math
import os
import sys
import time
from dataclasses import dataclass, asdict
from typing import Optional

# Serial port
try:
    import serial
    import serial.tools.list_ports
    SERIAL_AVAILABLE = True
except ImportError:
    SERIAL_AVAILABLE = False

# NMEA parsing
try:
    import pynmea2
    NMEA_AVAILABLE = True
except ImportError:
    NMEA_AVAILABLE = False
    print("ERROR: pynmea2 not installed. Run: pip install pynmea2")

# ZMQ for IPC
try:
    import zmq
    import zmq.asyncio
    ZMQ_AVAILABLE = True
except ImportError:
    ZMQ_AVAILABLE = False
    print("ERROR: pyzmq not installed. Run: pip install pyzmq")

# ============ Configuration ============

# Default to udev symlink, fallback to common USB-serial paths
DEFAULT_GPS_DEVICE = "/dev/argus_gps"
FALLBACK_GPS_DEVICES = [
    "/dev/ttyUSB0",
    "/dev/ttyUSB1",
    "/dev/ttyACM0",
    "/dev/ttyACM1",
]

ZMQ_GPS_PORT = 5558

logging.basicConfig(
    level=os.environ.get("ARGUS_LOG_LEVEL", "INFO"),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("gps_service")


# ============ Data Models ============

@dataclass
class GPSFix:
    """GPS position fix."""
    ts_utc_ms: int  # FIXED: Renamed from ts_ms to match uplink_service expectation
    lat: float
    lon: float
    altitude_m: Optional[float] = None
    speed_mps: Optional[float] = None
    heading_deg: Optional[float] = None
    hdop: Optional[float] = None
    satellites: Optional[int] = None
    fix_quality: int = 0  # 0=invalid, 1=GPS, 2=DGPS, 4=RTK Fixed, 5=RTK Float

    def is_valid(self) -> bool:
        """Check if fix is valid."""
        return (
            self.fix_quality > 0 and
            -90 <= self.lat <= 90 and
            -180 <= self.lon <= 180
        )

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {k: v for k, v in asdict(self).items() if v is not None}


# ============ GPS Service ============

class GPSService:
    """
    Reads GPS data from serial port and publishes via ZMQ.
    """

    def __init__(
        self,
        device: str = DEFAULT_GPS_DEVICE,
        baud: int = 9600,
        zmq_port: int = ZMQ_GPS_PORT,
        output_hz: int = 10,
        use_gpsd: bool = False,
    ):
        self.device = device
        self.baud = baud
        self.zmq_port = zmq_port
        self.output_hz = output_hz
        self.use_gpsd = use_gpsd

        self._serial: Optional[serial.Serial] = None
        self._zmq_socket: Optional[zmq.asyncio.Socket] = None
        self._running = False

        # Current state
        self._current_fix = GPSFix(ts_utc_ms=0, lat=0.0, lon=0.0)
        self._last_publish_time = 0
        self._fix_count = 0

        # EDGE-3: Device status for dashboard distinction
        # Values: "connected", "missing", "simulated"
        self._device_status = "missing"
        self._error_count = 0

    def _find_gps_device(self) -> Optional[str]:
        """Try to find a GPS device."""
        # Try configured device first
        if os.path.exists(self.device):
            return self.device

        # Try fallback devices
        for device in FALLBACK_GPS_DEVICES:
            if os.path.exists(device):
                logger.info(f"Using fallback GPS device: {device}")
                return device

        # Try to auto-detect USB GPS
        if SERIAL_AVAILABLE:
            ports = serial.tools.list_ports.comports()
            for port in ports:
                # Common GPS device identifiers
                if any(x in (port.description or "").lower() for x in ["gps", "u-blox", "gnss", "nmea"]):
                    logger.info(f"Auto-detected GPS: {port.device} ({port.description})")
                    return port.device

        return None

    async def start(self):
        """Start the GPS service."""
        self._running = True

        # Initialize ZMQ publisher
        ctx = zmq.asyncio.Context()
        self._zmq_socket = ctx.socket(zmq.PUB)
        self._zmq_socket.bind(f"tcp://*:{self.zmq_port}")
        logger.info(f"ZMQ GPS publisher bound to tcp://*:{self.zmq_port}")

        if self.use_gpsd:
            await self._run_gpsd()
        else:
            await self._run_serial()

    async def _run_serial(self):
        """Run with direct serial port access."""
        device = self._find_gps_device()

        if not device:
            logger.error(f"GPS device not found: {self.device}")
            logger.info("Running in simulation mode")
            self._device_status = "simulated"  # EDGE-3
            await self._run_simulation()
            return

        logger.info(f"Opening GPS device: {device} at {self.baud} baud")

        try:
            self._serial = serial.Serial(
                device,
                self.baud,
                timeout=1.0,
            )
            logger.info("GPS serial port opened")
            self._device_status = "connected"  # EDGE-3

        except serial.SerialException as e:
            logger.error(f"Failed to open GPS device: {e}")
            logger.info("Running in simulation mode")
            self._device_status = "simulated"  # EDGE-3
            await self._run_simulation()
            return

        # Start read and publish tasks
        read_task = asyncio.create_task(self._read_serial_loop())
        publish_task = asyncio.create_task(self._publish_loop())

        try:
            await asyncio.gather(read_task, publish_task)
        except asyncio.CancelledError:
            pass
        finally:
            await self.stop()

    async def _read_serial_loop(self):
        """Read NMEA sentences from serial port with automatic reconnection."""
        logger.info("Starting GPS read loop")
        buffer = ""
        consecutive_errors = 0
        MAX_ERRORS_BEFORE_RECONNECT = 5

        while self._running:
            # Check if we need to reconnect
            if self._serial is None or not self._serial.is_open:
                logger.warning("Serial port closed, attempting reconnect...")
                await self._reconnect_serial()
                if self._serial is None:
                    await asyncio.sleep(2.0)  # Wait before retry
                    continue
                consecutive_errors = 0
                buffer = ""

            try:
                # Read available data
                if self._serial.in_waiting > 0:
                    data = self._serial.read(self._serial.in_waiting)
                    buffer += data.decode("ascii", errors="ignore")

                    # Process complete sentences
                    while "\n" in buffer:
                        line, buffer = buffer.split("\n", 1)
                        line = line.strip()

                        if line.startswith("$"):
                            self._parse_nmea(line)

                    consecutive_errors = 0  # Reset on successful read
                else:
                    await asyncio.sleep(0.01)

            except serial.SerialException as e:
                logger.error(f"Serial read error: {e}")
                self._error_count += 1
                consecutive_errors += 1

                # After multiple errors, close and trigger reconnect
                if consecutive_errors >= MAX_ERRORS_BEFORE_RECONNECT:
                    logger.warning(f"Too many serial errors ({consecutive_errors}), forcing reconnect")
                    if self._serial:
                        try:
                            self._serial.close()
                        except:
                            pass
                        self._serial = None
                else:
                    await asyncio.sleep(0.1)

            except Exception as e:
                logger.error(f"GPS read error: {e}")
                await asyncio.sleep(0.1)

    async def _reconnect_serial(self):
        """Attempt to reconnect to GPS device after disconnect."""
        # Close existing connection if any
        if self._serial:
            try:
                self._serial.close()
            except:
                pass
            self._serial = None

        # Find GPS device (may be on different port after reconnect)
        device = self._find_gps_device()
        if not device:
            logger.warning("GPS device not found during reconnect")
            return

        try:
            self._serial = serial.Serial(
                device,
                self.baud,
                timeout=1.0,
            )
            logger.info(f"GPS reconnected on {device}")
        except serial.SerialException as e:
            logger.error(f"Failed to reconnect GPS: {e}")
            self._serial = None

    def _parse_nmea(self, sentence: str):
        """Parse an NMEA sentence and update current fix."""
        if not NMEA_AVAILABLE:
            return

        try:
            msg = pynmea2.parse(sentence)

            # GGA - GPS Fix Data
            if isinstance(msg, pynmea2.GGA):
                if msg.latitude and msg.longitude:
                    self._current_fix.lat = msg.latitude
                    self._current_fix.lon = msg.longitude
                    self._current_fix.altitude_m = msg.altitude
                    self._current_fix.satellites = msg.num_sats
                    self._current_fix.hdop = msg.horizontal_dil
                    self._current_fix.fix_quality = msg.gps_qual
                    self._current_fix.ts_utc_ms = int(time.time() * 1000)
                    self._fix_count += 1

            # RMC - Recommended Minimum
            elif isinstance(msg, pynmea2.RMC):
                if msg.latitude and msg.longitude:
                    self._current_fix.lat = msg.latitude
                    self._current_fix.lon = msg.longitude
                    self._current_fix.ts_utc_ms = int(time.time() * 1000)

                    # Speed in knots -> m/s
                    if msg.spd_over_grnd:
                        self._current_fix.speed_mps = msg.spd_over_grnd * 0.514444

                    # True course
                    if msg.true_course:
                        self._current_fix.heading_deg = msg.true_course

                    self._fix_count += 1

            # VTG - Course Over Ground
            elif isinstance(msg, pynmea2.VTG):
                if msg.true_track:
                    self._current_fix.heading_deg = msg.true_track
                if msg.spd_over_grnd_kmph:
                    self._current_fix.speed_mps = msg.spd_over_grnd_kmph / 3.6

        except pynmea2.ParseError:
            pass  # Ignore malformed sentences
        except Exception as e:
            logger.debug(f"NMEA parse error: {e}")

    async def _publish_loop(self):
        """Publish GPS fixes at configured rate."""
        interval = 1.0 / self.output_hz
        logger.info(f"Starting GPS publish loop at {self.output_hz} Hz")

        while self._running:
            await asyncio.sleep(interval)

            if not self._current_fix.is_valid():
                continue

            # Publish via ZMQ
            try:
                payload = self._current_fix.to_dict()
                # EDGE-3: Include device status so dashboard can distinguish
                payload["device_status"] = self._device_status
                await self._zmq_socket.send_multipart([
                    b"gps",
                    json.dumps(payload).encode()
                ])

                logger.debug(
                    f"GPS: ({self._current_fix.lat:.6f}, {self._current_fix.lon:.6f}) "
                    f"speed={self._current_fix.speed_mps:.1f} m/s"
                )

            except Exception as e:
                logger.error(f"ZMQ publish error: {e}")

    async def _run_gpsd(self):
        """Run using gpsd daemon (not implemented yet)."""
        logger.warning("gpsd mode not yet implemented, using simulation")
        await self._run_simulation()

    async def _run_simulation(self):
        """Generate simulated GPS data for testing."""
        logger.info("Running in SIMULATION mode")
        import random

        # Start position (Johnson Valley OHV area)
        lat = 34.36
        lon = -116.45
        speed = 15.0  # m/s
        heading = 45.0

        while self._running:
            # Simulate movement
            heading += random.gauss(0, 5)  # Wander
            heading = heading % 360

            # Move forward
            distance = speed / self.output_hz
            lat += (distance / 111000) * math.cos(math.radians(heading))
            lon += (distance / (111000 * math.cos(math.radians(lat)))) * math.sin(math.radians(heading))

            # Vary speed
            speed = max(5, min(40, speed + random.gauss(0, 1)))

            self._current_fix = GPSFix(
                ts_utc_ms=int(time.time() * 1000),
                lat=lat + random.gauss(0, 0.00005),  # GPS noise
                lon=lon + random.gauss(0, 0.00005),
                altitude_m=1000 + random.gauss(0, 5),
                speed_mps=speed + random.gauss(0, 0.5),
                heading_deg=heading + random.gauss(0, 2),
                hdop=1.0 + random.random(),
                satellites=random.randint(8, 14),
                fix_quality=1,
            )

            # Publish
            payload = self._current_fix.to_dict()
            payload["device_status"] = self._device_status  # EDGE-3
            await self._zmq_socket.send_multipart([
                b"gps",
                json.dumps(payload).encode()
            ])

            self._fix_count += 1

            if self._fix_count % (self.output_hz * 5) == 0:
                logger.info(
                    f"SIM GPS: ({lat:.5f}, {lon:.5f}) "
                    f"speed={speed:.1f} m/s heading={heading:.0f}°"
                )

            await asyncio.sleep(1.0 / self.output_hz)

    async def stop(self):
        """Stop the GPS service."""
        self._running = False

        if self._serial:
            self._serial.close()
            self._serial = None

        if self._zmq_socket:
            self._zmq_socket.close()
            self._zmq_socket = None

        logger.info(f"GPS service stopped. Fixes: {self._fix_count}, Errors: {self._error_count}")


# ============ Main Entry Point ============

async def main():
    parser = argparse.ArgumentParser(description="Argus GPS Service")
    parser.add_argument(
        "--device", "-d",
        default=os.environ.get("ARGUS_GPS_DEVICE", DEFAULT_GPS_DEVICE),
        help=f"GPS serial device (default: {DEFAULT_GPS_DEVICE})",
    )
    parser.add_argument(
        "--baud", "-b",
        type=int,
        default=int(os.environ.get("ARGUS_GPS_BAUD", "9600")),
        help="Baud rate (default: 9600)",
    )
    parser.add_argument(
        "--hz",
        type=int,
        default=int(os.environ.get("ARGUS_GPS_HZ", "10")),
        help="Output rate in Hz (default: 10)",
    )
    parser.add_argument(
        "--gpsd",
        action="store_true",
        help="Use gpsd daemon instead of direct serial",
    )
    parser.add_argument(
        "--simulate",
        action="store_true",
        help="Run in simulation mode",
    )
    args = parser.parse_args()

    logger.info("=" * 50)
    logger.info("Argus GPS Service Starting")
    logger.info("=" * 50)
    logger.info(f"Device: {args.device}")
    logger.info(f"Baud: {args.baud}")
    logger.info(f"Output Hz: {args.hz}")
    logger.info(f"ZMQ Port: {ZMQ_GPS_PORT}")
    logger.info("=" * 50)

    # Override device if simulating
    if args.simulate:
        args.device = "/dev/null"

    service = GPSService(
        device=args.device,
        baud=args.baud,
        zmq_port=ZMQ_GPS_PORT,
        output_hz=args.hz,
        use_gpsd=args.gpsd,
    )

    try:
        await service.start()
    except KeyboardInterrupt:
        pass
    finally:
        await service.stop()


if __name__ == "__main__":
    asyncio.run(main())
