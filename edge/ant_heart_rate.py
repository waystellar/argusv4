#!/usr/bin/env python3
"""
ANT+ Heart Rate Monitor Service

Connects to ANT+ heart rate monitors and integrates with the Argus telemetry pipeline.
Requires ANT+ USB dongle (e.g., Garmin ANT+ Stick).

Dependencies:
    pip install openant pyzmq

Usage:
    python ant_heart_rate.py --serial /dev/argus_ant
    python ant_heart_rate.py --serial /dev/argus_ant --zmq-port 5556

ZMQ Output (PUB on tcp://*:5556):
    Topic: "ant"
    Data: JSON with heart rate data

This service publishes heart rate data via ZMQ for consumption by uplink_service.py
"""
import asyncio
import argparse
import json
import logging
import os
import time
from typing import Optional, Callable

# ZMQ for IPC with uplink service
try:
    import zmq
    import zmq.asyncio
    ZMQ_AVAILABLE = True
except ImportError:
    ZMQ_AVAILABLE = False
    print("WARNING: pyzmq not installed. Heart rate will be logged only.")

# Configure logging
logging.basicConfig(
    level=os.environ.get("ARGUS_LOG_LEVEL", "INFO"),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("ant_heart_rate")

# ANT+ Heart Rate Monitor Profile constants
CHANNEL_TYPE_SLAVE = 0x00
NETWORK_KEY = [0xB9, 0xA5, 0x21, 0xFB, 0xBD, 0x72, 0xC3, 0x45]  # ANT+ public network key
HR_DEVICE_TYPE = 120  # ANT+ Heart Rate device type
HR_PERIOD = 8070  # Message period for HR monitors
HR_FREQUENCY = 57  # RF frequency for ANT+ HR

# Default device path (uses udev symlink)
DEFAULT_ANT_DEVICE = "/dev/argus_ant"
ZMQ_ANT_PORT = 5556


class HeartRateData:
    """Heart rate data container."""

    def __init__(self):
        self.heart_rate: Optional[int] = None  # None when no data received
        self.rr_interval_ms: Optional[float] = None
        self.beat_count: int = 0
        self.last_update_ms: int = 0
        self.last_frame_ts: int = 0  # Timestamp of last real ANT+ data received
        self.data_valid: bool = False  # Only True when receiving real ANT+ data
        self.is_simulated: bool = False  # True when running in simulation mode
        # EDGE-3: Device status for dashboard distinction
        # Values: "connected", "missing", "simulated", "timeout"
        self.device_status: str = "missing"

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "heart_rate": self.heart_rate,
            "beat_count": self.beat_count,
            "ts_ms": self.last_update_ms,
            "last_frame_ts": self.last_frame_ts,
            "data_valid": self.data_valid,
            "is_simulated": self.is_simulated,
            "device_status": self.device_status,  # EDGE-3
        }


class ANTHeartRateService:
    """
    ANT+ Heart Rate Monitor Service.

    Connects to ANT+ USB dongle and reads heart rate data from paired monitors.
    Publishes data via ZMQ for consumption by uplink_service.
    """

    def __init__(
        self,
        serial_port: Optional[str] = None,
        zmq_port: int = ZMQ_ANT_PORT,
        on_heart_rate: Optional[Callable[[HeartRateData], None]] = None,
        simulate: bool = False,
    ):
        """
        Initialize the ANT+ heart rate service.

        Args:
            serial_port: Serial port for ANT+ USB dongle (e.g., "/dev/argus_ant")
            zmq_port: ZMQ publisher port (default: 5556)
            on_heart_rate: Optional callback function
            simulate: If True, run in simulation mode (requires explicit flag)
        """
        self.serial_port = serial_port
        self.zmq_port = zmq_port
        self.on_heart_rate = on_heart_rate
        # FIXED: Only enable simulation if explicitly requested via --simulate flag
        self._simulate_mode = simulate
        self._running = False
        self._last_data = HeartRateData()
        self._node = None
        self._zmq_socket: Optional["zmq.asyncio.Socket"] = None
        self._data_timeout_ms = 5000  # Mark data invalid after 5 seconds of no data

    @property
    def latest_heart_rate(self) -> HeartRateData:
        """Get the most recent heart rate data."""
        return self._last_data

    def _on_data(self, data: bytes):
        """Process ANT+ heart rate data page."""
        if len(data) < 8:
            return

        # ANT+ HR data page format (Page 4 - Main Data Page)
        page_number = data[0] & 0x7F
        beat_count = data[6]
        heart_rate = data[7]

        now_ms = int(time.time() * 1000)

        # Update data
        self._last_data.heart_rate = heart_rate
        self._last_data.beat_count = beat_count
        self._last_data.last_update_ms = now_ms
        self._last_data.last_frame_ts = now_ms  # Track when we last received real data
        self._last_data.data_valid = True  # Mark data as valid - we have real ANT+ data
        self._last_data.is_simulated = False  # This is real data, not simulated

        logger.debug(f"HR: {heart_rate} bpm, Beat count: {beat_count}")

        # Call callback
        if self.on_heart_rate:
            self.on_heart_rate(self._last_data)

    async def _publish_zmq(self):
        """Publish heart rate data via ZMQ.

        Always publishes so UI receives the data_valid flag to know
        whether to show data or "No data" indicator.
        """
        if self._zmq_socket:
            try:
                payload = self._last_data.to_dict()
                await self._zmq_socket.send_multipart([
                    b"ant",
                    json.dumps(payload).encode()
                ])
            except Exception as e:
                logger.error(f"ZMQ publish error: {e}")

    async def start(self):
        """Start the ANT+ heart rate service."""
        self._running = True
        logger.info("Starting ANT+ Heart Rate Service...")

        # Initialize ZMQ publisher
        if ZMQ_AVAILABLE:
            ctx = zmq.asyncio.Context()
            self._zmq_socket = ctx.socket(zmq.PUB)
            self._zmq_socket.bind(f"tcp://*:{self.zmq_port}")
            logger.info(f"ZMQ ANT+ publisher bound to tcp://*:{self.zmq_port}")

        # FIXED: Only run simulation if explicitly requested via --simulate flag
        if self._simulate_mode:
            self._last_data.device_status = "simulated"  # EDGE-3
            await self._run_simulation()
            return

        try:
            # Try to import openant
            from ant.core import driver, node, event, message
            from ant.core.constants import CHANNEL_TYPE_TWOWAY_RECEIVE

            logger.info("OpenANT library loaded successfully")

            # Initialize ANT+ node
            if self.serial_port and os.path.exists(self.serial_port):
                self._node = node.Node(driver.USB2Driver(self.serial_port))
            else:
                self._node = node.Node()

            self._node.start()

            # Set network key
            network = node.Network(key=bytes(NETWORK_KEY), name="N:ANT+")
            self._node.setNetworkKey(0, network)

            # Open channel
            channel = self._node.getFreeChannel()
            channel.assign(network, CHANNEL_TYPE_TWOWAY_RECEIVE)
            channel.setID(HR_DEVICE_TYPE, 0, 0)  # Device type, pairing request
            channel.setPeriod(HR_PERIOD)
            channel.setFrequency(HR_FREQUENCY)
            channel.setSearchTimeout(255)  # Search indefinitely

            # Register callback
            channel.registerCallback(lambda e: self._on_data(e.message.payload))

            # Open channel and start receiving
            channel.open()
            logger.info("ANT+ channel opened, waiting for heart rate monitor...")
            self._last_data.device_status = "connected"  # EDGE-3

            # Run publish loop with timeout checking
            while self._running:
                await self._check_timeout_and_publish()
                await asyncio.sleep(1.0)

        except ImportError:
            # FIXED: Don't auto-fallback to simulation - log error and continue
            # publishing with data_valid=False so UI shows "No data"
            logger.error("OpenANT library not installed. Cannot read ANT+ data.")
            logger.error("Install with: pip install openant")
            logger.error("To test without hardware, use --simulate flag explicitly.")
            self._last_data.device_status = "missing"  # EDGE-3
            # Continue running publish loop with invalid data
            while self._running:
                await self._check_timeout_and_publish()
                await asyncio.sleep(1.0)

        except Exception as e:
            # FIXED: Don't auto-fallback to simulation - log error and continue
            logger.error(f"ANT+ error: {e}")
            logger.error("ANT+ heart rate will show 'No data' until hardware is connected.")
            logger.error("To test without hardware, use --simulate flag explicitly.")
            self._last_data.device_status = "missing"  # EDGE-3
            # Continue running publish loop with invalid data
            while self._running:
                await self._check_timeout_and_publish()
                await asyncio.sleep(1.0)

        finally:
            await self.stop()

    async def _check_timeout_and_publish(self):
        """Check for data timeout and publish current state."""
        now_ms = int(time.time() * 1000)

        # Check for data timeout - invalidate if no data received recently
        if self._last_data.last_frame_ts > 0:
            time_since_data = now_ms - self._last_data.last_frame_ts
            if time_since_data > self._data_timeout_ms:
                if self._last_data.data_valid:
                    logger.warning(f"ANT+ data timeout ({time_since_data}ms since last data). Marking invalid.")
                    self._last_data.data_valid = False
                    self._last_data.heart_rate = None  # Clear to null on timeout
                    self._last_data.device_status = "timeout"  # EDGE-3

        await self._publish_zmq()

    async def _run_simulation(self):
        """Run in simulation mode (generates fake HR data for testing).

        IMPORTANT: This only runs when --simulate flag is explicitly passed.
        Simulated data is clearly marked with is_simulated=True so UI can display appropriately.
        """
        logger.warning("=" * 60)
        logger.warning("  SIMULATION MODE ACTIVE - Generating fake heart rate data")
        logger.warning("  This data is NOT from real hardware!")
        logger.warning("=" * 60)

        import random

        base_hr = 75  # Resting heart rate

        while self._running:
            now_ms = int(time.time() * 1000)

            # Simulate heart rate with some variation
            # Simulate racing conditions (elevated HR with variability)
            hr_variation = random.gauss(0, 5)
            self._last_data.heart_rate = int(
                min(200, max(60, base_hr + hr_variation))
            )
            self._last_data.beat_count = (self._last_data.beat_count + 1) % 256
            self._last_data.last_update_ms = now_ms
            self._last_data.last_frame_ts = now_ms
            # Mark as simulated but valid (for testing purposes)
            self._last_data.data_valid = True
            self._last_data.is_simulated = True

            # Gradually increase/decrease HR to simulate effort
            if random.random() > 0.5:
                base_hr = min(180, base_hr + random.uniform(0, 2))
            else:
                base_hr = max(70, base_hr - random.uniform(0, 1))

            if self.on_heart_rate:
                self.on_heart_rate(self._last_data)

            # Publish via ZMQ
            await self._publish_zmq()

            logger.debug(f"Simulated HR: {self._last_data.heart_rate} bpm")
            await asyncio.sleep(1.0)

    async def stop(self):
        """Stop the ANT+ heart rate service."""
        self._running = False

        if self._node:
            try:
                self._node.stop()
            except Exception as e:
                logger.warning(f"Error stopping ANT+ node: {e}")
            self._node = None

        if self._zmq_socket:
            self._zmq_socket.close()
            self._zmq_socket = None

        logger.info("ANT+ Heart Rate Service stopped")


async def main():
    """Main entry point for standalone ANT+ heart rate service."""
    parser = argparse.ArgumentParser(description="ANT+ Heart Rate Service")
    parser.add_argument(
        "--serial",
        default=os.environ.get("ARGUS_ANT_DEVICE", DEFAULT_ANT_DEVICE),
        help=f"Serial port for ANT+ USB dongle (default: {DEFAULT_ANT_DEVICE})",
    )
    parser.add_argument(
        "--zmq-port",
        type=int,
        default=ZMQ_ANT_PORT,
        help=f"ZMQ publisher port (default: {ZMQ_ANT_PORT})",
    )
    parser.add_argument(
        "--simulate",
        action="store_true",
        help="Run in simulation mode (no hardware required)",
    )
    args = parser.parse_args()

    def on_hr_update(data: HeartRateData):
        print(f"❤️  Heart Rate: {data.heart_rate} bpm (beat #{data.beat_count})")

    service = ANTHeartRateService(
        serial_port=args.serial,
        zmq_port=args.zmq_port,
        on_heart_rate=on_hr_update,
        simulate=args.simulate,  # Only simulate if explicitly requested
    )

    print("\n" + "=" * 50)
    print("ANT+ Heart Rate Monitor Service")
    print("=" * 50)
    if args.simulate:
        print("Mode: SIMULATION (generating fake data)")
    else:
        print(f"Serial: {args.serial}")
    print(f"ZMQ Port: {args.zmq_port}")
    print("Press Ctrl+C to stop")
    print("=" * 50 + "\n")

    try:
        await service.start()
    except KeyboardInterrupt:
        print("\n\nStopping...")
        await service.stop()


if __name__ == "__main__":
    asyncio.run(main())
