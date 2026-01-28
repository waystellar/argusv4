#!/usr/bin/env python3
"""
Argus CAN Bus Telemetry Service

Reads vehicle CAN bus data and publishes decoded telemetry via ZMQ.
Supports OBD-II PIDs, MoTeC ECUs, and DBC-defined proprietary messages.

Supported ECUs:
    - MoTeC M1, M150, M130, M84, M800 series
    - AEM Infinity, Series 2
    - Haltech Elite, Nexus
    - Link G4+, G4X
    - Any ECU with CAN output and DBC file

Hardware: PEAK PCAN-USB, Kvaser Leaf, or socketcan-compatible adapters

Usage:
    python can_telemetry.py --interface can0 --zmq-port 5557
    python can_telemetry.py --interface pcan --dbc motec_m150.dbc
    python can_telemetry.py --motec --interface can0  # Uses bundled MoTeC DBC

ZMQ Output (PUB on tcp://*:5557):
    Topic: "can"
    Data: JSON with decoded CAN values

Note: This service publishes on port 5557 for consumption by uplink_service.py
"""
import argparse
import asyncio
import json
import logging
import time
from dataclasses import dataclass, field
from typing import Optional, Callable

# Optional CAN library (python-can) - graceful fallback for development
try:
    import can
    CAN_AVAILABLE = True
except ImportError:
    CAN_AVAILABLE = False
    print("WARNING: python-can not installed. Using mock CAN data.")

# Optional DBC parser (cantools) - for proprietary message decoding
try:
    import cantools
    DBC_AVAILABLE = True
except ImportError:
    DBC_AVAILABLE = False

# ZeroMQ for IPC with uplink service
try:
    import zmq
    import zmq.asyncio
    ZMQ_AVAILABLE = True
except ImportError:
    ZMQ_AVAILABLE = False
    print("WARNING: pyzmq not installed. Messages will be logged only.")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("can_telemetry")


# ============ OBD-II PID Definitions ============

@dataclass
class OBDPid:
    """OBD-II PID definition."""
    pid: int
    name: str
    unit: str
    min_val: float
    max_val: float
    decode: Callable[[bytes], float]


# Standard OBD-II PIDs (Mode 01)
OBD_PIDS = {
    0x0C: OBDPid(
        pid=0x0C,
        name="rpm",
        unit="rpm",
        min_val=0,
        max_val=16383.75,
        decode=lambda b: ((b[0] << 8) | b[1]) / 4.0,
    ),
    0x0D: OBDPid(
        pid=0x0D,
        name="speed_kph",
        unit="km/h",
        min_val=0,
        max_val=255,
        decode=lambda b: float(b[0]),
    ),
    0x04: OBDPid(
        pid=0x04,
        name="engine_load",
        unit="%",
        min_val=0,
        max_val=100,
        decode=lambda b: b[0] / 2.55,
    ),
    0x05: OBDPid(
        pid=0x05,
        name="coolant_temp",
        unit="C",
        min_val=-40,
        max_val=215,
        decode=lambda b: b[0] - 40,
    ),
    0x0B: OBDPid(
        pid=0x0B,
        name="intake_pressure",
        unit="kPa",
        min_val=0,
        max_val=255,
        decode=lambda b: float(b[0]),
    ),
    0x0F: OBDPid(
        pid=0x0F,
        name="intake_temp",
        unit="C",
        min_val=-40,
        max_val=215,
        decode=lambda b: b[0] - 40,
    ),
    0x11: OBDPid(
        pid=0x11,
        name="throttle_pct",
        unit="%",
        min_val=0,
        max_val=100,
        decode=lambda b: b[0] / 2.55,
    ),
    0x23: OBDPid(
        pid=0x23,
        name="fuel_pressure",
        unit="kPa",
        min_val=0,
        max_val=765765,
        decode=lambda b: ((b[0] << 8) | b[1]) * 10,
    ),
}


# ============ Telemetry State ============

@dataclass
class TelemetryState:
    """Current telemetry values."""
    rpm: Optional[float] = None
    speed_kph: Optional[float] = None
    speed_mps: Optional[float] = None
    throttle_pct: Optional[float] = None
    engine_load: Optional[float] = None
    coolant_temp: Optional[float] = None
    oil_pressure: Optional[float] = None
    fuel_pressure: Optional[float] = None
    intake_temp: Optional[float] = None
    intake_pressure: Optional[float] = None
    gear: Optional[int] = None
    # NOTE: Suspension fields removed - not currently in use
    # Timestamps and validity
    last_update_ms: int = 0
    last_frame_ts: int = 0  # Timestamp of last real CAN frame received
    message_count: int = 0
    # Data validity flag - only True when receiving real CAN data
    data_valid: bool = False
    # Source indicator
    is_simulated: bool = False
    # EDGE-3: Device status for dashboard distinction
    # Values: "connected", "missing", "simulated", "timeout"
    device_status: str = "missing"

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "rpm": round(self.rpm, 1) if self.rpm is not None else None,
            "speed_mps": round(self.speed_kph / 3.6, 2) if self.speed_kph is not None else None,
            "throttle_pct": round(self.throttle_pct, 1) if self.throttle_pct is not None else None,
            "engine_load": round(self.engine_load, 1) if self.engine_load is not None else None,
            "coolant_temp": round(self.coolant_temp, 1) if self.coolant_temp is not None else None,
            "oil_pressure": round(self.oil_pressure, 1) if self.oil_pressure is not None else None,
            "fuel_pressure": round(self.fuel_pressure, 1) if self.fuel_pressure is not None else None,
            "gear": self.gear,
            # NOTE: Suspension fields removed - not currently in use
            "ts_ms": self.last_update_ms,
            "last_frame_ts": self.last_frame_ts,
            "data_valid": self.data_valid,
            "is_simulated": self.is_simulated,
            "device_status": self.device_status,  # EDGE-3
        }


# ============ CAN Service ============

class CANTelemetryService:
    """
    Reads CAN bus messages and decodes vehicle telemetry.

    Supports:
    - Standard OBD-II PIDs (11-bit CAN IDs)
    - DBC-defined messages (for proprietary race ECUs)
    - Mock mode for development/testing
    """

    def __init__(
        self,
        interface: str = "can0",
        dbc_path: Optional[str] = None,
        zmq_port: int = 5555,
        publish_hz: int = 10,
        mock_mode: bool = False,
    ):
        self.interface = interface
        self.dbc_path = dbc_path
        self.zmq_port = zmq_port
        self.publish_hz = publish_hz
        # FIXED: Only enable mock mode if explicitly requested via --mock flag
        # Never auto-fallback to mock - this causes phantom telemetry
        self.mock_mode = mock_mode
        self.data_timeout_ms = 5000  # Mark data invalid after 5 seconds of no frames

        self.state = TelemetryState()
        self.bus: Optional["can.Bus"] = None
        self.dbc: Optional["cantools.database.Database"] = None
        self.zmq_socket: Optional["zmq.asyncio.Socket"] = None
        self.running = False

        # Load DBC file if provided
        if dbc_path and DBC_AVAILABLE:
            try:
                self.dbc = cantools.database.load_file(dbc_path)
                logger.info(f"Loaded DBC file: {dbc_path} ({len(self.dbc.messages)} messages)")
            except Exception as e:
                logger.error(f"Failed to load DBC file: {e}")

    async def start(self):
        """Start the CAN telemetry service."""
        self.running = True

        # Initialize ZMQ publisher
        if ZMQ_AVAILABLE:
            ctx = zmq.asyncio.Context()
            self.zmq_socket = ctx.socket(zmq.PUB)
            self.zmq_socket.bind(f"tcp://*:{self.zmq_port}")
            logger.info(f"ZMQ publisher bound to tcp://*:{self.zmq_port}")

        # Initialize CAN bus
        if self.mock_mode:
            self.state.device_status = "simulated"  # EDGE-3
        if not self.mock_mode:
            if not CAN_AVAILABLE:
                logger.error("python-can library not installed. Cannot read CAN data.")
                logger.error("Install with: pip install python-can")
                logger.error("To test without hardware, use --mock flag explicitly.")
                # Continue running but data_valid will remain False
            else:
                try:
                    # Detect interface type
                    if self.interface.startswith("pcan"):
                        self.bus = can.Bus(interface="pcan", channel="PCAN_USBBUS1")
                    elif self.interface.startswith("kvaser"):
                        self.bus = can.Bus(interface="kvaser", channel=0)
                    else:
                        # Assume socketcan (Linux)
                        self.bus = can.Bus(interface="socketcan", channel=self.interface)
                    logger.info(f"Connected to CAN interface: {self.interface}")
                    self.state.device_status = "connected"  # EDGE-3
                except Exception as e:
                    # FIXED: Don't silently fallback to mock - log error and continue
                    # without generating fake data. data_valid will remain False.
                    logger.error(f"Failed to connect to CAN interface '{self.interface}': {e}")
                    logger.error("CAN telemetry will show 'No data' until hardware is connected.")
                    logger.error("To test without hardware, use --mock flag explicitly.")
                    self.state.device_status = "missing"  # EDGE-3

        # Start tasks
        tasks = [
            asyncio.create_task(self._read_can_loop()),
            asyncio.create_task(self._publish_loop()),
        ]

        if self.mock_mode:
            tasks.append(asyncio.create_task(self._mock_data_loop()))

        try:
            await asyncio.gather(*tasks)
        except asyncio.CancelledError:
            pass
        finally:
            await self.stop()

    async def stop(self):
        """Stop the service and clean up."""
        self.running = False

        if self.bus:
            self.bus.shutdown()
            logger.info("CAN bus shutdown")

        if self.zmq_socket:
            self.zmq_socket.close()
            logger.info("ZMQ socket closed")

    async def _read_can_loop(self):
        """Read CAN messages and decode telemetry."""
        if self.mock_mode or not self.bus:
            return

        logger.info("Starting CAN read loop")

        while self.running:
            try:
                # Non-blocking read with timeout
                msg = await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: self.bus.recv(timeout=0.1)
                )

                if msg is None:
                    continue

                self._decode_message(msg)

            except Exception as e:
                logger.error(f"CAN read error: {e}")
                await asyncio.sleep(0.1)

    def _decode_message(self, msg: "can.Message"):
        """Decode a CAN message and update telemetry state."""
        self.state.message_count += 1
        now_ms = int(time.time() * 1000)
        self.state.last_update_ms = now_ms
        self.state.last_frame_ts = now_ms  # Track when we last received a real frame
        self.state.data_valid = True  # Mark data as valid - we have real CAN data
        self.state.is_simulated = False  # This is real data, not simulated

        # Try OBD-II decoding first (responses are 0x7E8-0x7EF)
        if 0x7E8 <= msg.arbitration_id <= 0x7EF:
            self._decode_obd_response(msg)
            return

        # Try DBC decoding if available
        if self.dbc:
            try:
                decoded = self.dbc.decode_message(msg.arbitration_id, msg.data)
                self._apply_dbc_values(decoded)
            except Exception:
                pass  # Unknown message ID

    def _decode_obd_response(self, msg: "can.Message"):
        """Decode OBD-II Mode 01 response."""
        if len(msg.data) < 4:
            return

        # OBD-II response format: [length, mode+0x40, pid, data...]
        mode = msg.data[1]
        pid = msg.data[2]

        if mode != 0x41:  # Mode 01 response
            return

        if pid not in OBD_PIDS:
            return

        pid_def = OBD_PIDS[pid]
        data = msg.data[3:]

        try:
            value = pid_def.decode(data)
            setattr(self.state, pid_def.name, value)

            # Update derived values
            if pid_def.name == "speed_kph":
                self.state.speed_mps = value / 3.6

        except Exception as e:
            logger.debug(f"Failed to decode PID {pid:02X}: {e}")

    def _apply_dbc_values(self, decoded: dict):
        """Apply DBC-decoded values to telemetry state."""
        # Map DBC signal names to our state fields
        # Includes common naming conventions from various ECU manufacturers
        mappings = {
            # Generic DBC names
            "EngineRPM": "rpm",
            "VehicleSpeed": "speed_kph",
            "ThrottlePosition": "throttle_pct",
            "EngineCoolantTemp": "coolant_temp",
            "OilPressure": "oil_pressure",
            "FuelPressure": "fuel_pressure",
            "GearPosition": "gear",
            # NOTE: Suspension mappings removed - not currently in use

            # MoTeC M1/M150/M130/M84 common signal names
            "Engine_RPM": "rpm",
            "Engine RPM": "rpm",
            "RPM": "rpm",
            "Ground_Speed": "speed_kph",
            "Ground Speed": "speed_kph",
            "Vehicle_Speed": "speed_kph",
            "Wheel_Speed_Avg": "speed_kph",
            "Throttle_Position": "throttle_pct",
            "Throttle Position": "throttle_pct",
            "Throttle_Pos": "throttle_pct",
            "TPS": "throttle_pct",
            "TPS_Main": "throttle_pct",
            "Engine_Coolant_Temp": "coolant_temp",
            "Engine Coolant Temp": "coolant_temp",
            "ECT": "coolant_temp",
            "Coolant_Temp": "coolant_temp",
            "Water_Temp": "coolant_temp",
            "Oil_Pressure": "oil_pressure",
            "Oil Pressure": "oil_pressure",
            "Oil_Press": "oil_pressure",
            "Engine_Oil_Press": "oil_pressure",
            "Fuel_Pressure": "fuel_pressure",
            "Fuel Pressure": "fuel_pressure",
            "Fuel_Press": "fuel_pressure",
            "Gear": "gear",
            "Gear_Position": "gear",
            "Gear Position": "gear",
            "Current_Gear": "gear",
            "Intake_Air_Temp": "intake_temp",
            "Intake Air Temp": "intake_temp",
            "IAT": "intake_temp",
            "Air_Temp": "intake_temp",
            "Manifold_Pressure": "intake_pressure",
            "Manifold Pressure": "intake_pressure",
            "MAP": "intake_pressure",
            "Boost_Pressure": "intake_pressure",

            # NOTE: MoTeC suspension/damper channels removed - not currently in use

            # MoTeC load/lambda channels (map to engine_load)
            "Engine_Load": "engine_load",
            "Engine Load": "engine_load",
            "Load": "engine_load",
            "Injector_Duty": "engine_load",

            # AEM/Haltech/Link ECU common names
            "Eng_RPM": "rpm",
            "EngRPM": "rpm",
            "Veh_Speed": "speed_kph",
            "Thr_Pos": "throttle_pct",
            "CLT": "coolant_temp",
            "Coolant": "coolant_temp",
            "Oil_P": "oil_pressure",
            "Fuel_P": "fuel_pressure",
        }

        for signal_name, value in decoded.items():
            if signal_name in mappings:
                setattr(self.state, mappings[signal_name], value)

    async def _publish_loop(self):
        """Publish telemetry at configured rate."""
        interval = 1.0 / self.publish_hz
        logger.info(f"Starting publish loop at {self.publish_hz} Hz")

        while self.running:
            await asyncio.sleep(interval)

            now_ms = int(time.time() * 1000)

            # Check for data timeout - invalidate if no frames received recently
            if self.state.last_frame_ts > 0:
                time_since_frame = now_ms - self.state.last_frame_ts
                if time_since_frame > self.data_timeout_ms:
                    if self.state.data_valid:
                        logger.warning(f"CAN data timeout ({time_since_frame}ms since last frame). Marking data invalid.")
                        self.state.data_valid = False
                        self.state.device_status = "timeout"  # EDGE-3
                        # Clear telemetry values to null when timed out
                        self.state.rpm = None
                        self.state.speed_kph = None
                        self.state.speed_mps = None
                        self.state.throttle_pct = None
                        self.state.engine_load = None
                        self.state.coolant_temp = None
                        self.state.oil_pressure = None
                        self.state.fuel_pressure = None
                        self.state.intake_temp = None
                        self.state.intake_pressure = None
                        self.state.gear = None
                        # NOTE: Suspension clearing removed - not currently in use

            telemetry = self.state.to_dict()

            # Publish via ZMQ (topic: "can" for uplink_service)
            # Always publish so UI knows the current state (including data_valid=False)
            if self.zmq_socket:
                try:
                    topic = b"can"
                    payload = json.dumps(telemetry).encode()
                    await self.zmq_socket.send_multipart([topic, payload])
                except Exception as e:
                    logger.error(f"ZMQ publish error: {e}")

            # Log periodically
            if self.state.message_count % (self.publish_hz * 5) == 0:
                if self.state.data_valid:
                    rpm_str = f"{telemetry['rpm']}" if telemetry['rpm'] is not None else "N/A"
                    speed_str = f"{telemetry['speed_mps']:.1f}" if telemetry['speed_mps'] is not None else "N/A"
                    logger.info(f"Telemetry: RPM={rpm_str}, Speed={speed_str} m/s [VALID]")
                else:
                    logger.info(f"Telemetry: No CAN data (data_valid=False)")

    async def _mock_data_loop(self):
        """Generate mock telemetry for development/testing.

        IMPORTANT: This only runs when --mock flag is explicitly passed.
        Mock data is clearly marked with is_simulated=True so UI can display appropriately.
        """
        logger.warning("=" * 60)
        logger.warning("  MOCK MODE ACTIVE - Generating simulated CAN telemetry")
        logger.warning("  This data is NOT from real hardware!")
        logger.warning("=" * 60)
        import math
        import random

        t = 0
        base_rpm = 3500
        base_speed = 80

        while self.running:
            await asyncio.sleep(0.05)  # 20 Hz internal update
            t += 0.05

            # Simulate driving patterns
            self.state.rpm = base_rpm + math.sin(t * 0.5) * 1500 + random.gauss(0, 50)
            self.state.speed_kph = base_speed + math.sin(t * 0.3) * 30 + random.gauss(0, 2)
            self.state.speed_mps = self.state.speed_kph / 3.6
            self.state.throttle_pct = 50 + math.sin(t * 0.7) * 40 + random.gauss(0, 5)
            self.state.engine_load = 40 + math.sin(t * 0.4) * 30 + random.gauss(0, 3)
            self.state.coolant_temp = 90 + math.sin(t * 0.1) * 10
            self.state.oil_pressure = 45 + math.sin(t * 0.2) * 10
            self.state.fuel_pressure = 350 + random.gauss(0, 10)

            # NOTE: Suspension mock data removed - not currently in use

            # Gear (1-6 based on speed)
            self.state.gear = max(1, min(6, int(self.state.speed_kph / 30) + 1))

            now_ms = int(time.time() * 1000)
            self.state.last_update_ms = now_ms
            self.state.last_frame_ts = now_ms
            self.state.message_count += 1
            # Mark as simulated but valid (for testing purposes)
            self.state.data_valid = True
            self.state.is_simulated = True


# ============ OBD-II Query Service ============

class OBDQueryService:
    """
    Actively queries OBD-II PIDs (for vehicles that don't broadcast CAN).
    Sends Mode 01 requests and waits for responses.
    """

    def __init__(self, bus: "can.Bus", pids: list[int] = None):
        self.bus = bus
        self.pids = pids or [0x0C, 0x0D, 0x05, 0x11]  # RPM, Speed, Coolant, Throttle
        self.request_id = 0x7DF  # Broadcast request ID

    async def query_loop(self, interval: float = 0.1):
        """Continuously query OBD-II PIDs."""
        while True:
            for pid in self.pids:
                # Send OBD-II request: [length, mode, pid, 0x55, 0x55, 0x55, 0x55, 0x55]
                data = [0x02, 0x01, pid, 0x55, 0x55, 0x55, 0x55, 0x55]
                msg = can.Message(
                    arbitration_id=self.request_id,
                    data=data,
                    is_extended_id=False,
                )
                try:
                    self.bus.send(msg)
                except Exception as e:
                    logger.error(f"Failed to send OBD request: {e}")

                await asyncio.sleep(interval / len(self.pids))


# ============ Main Entry Point ============

async def main():
    parser = argparse.ArgumentParser(description="CAN Bus Telemetry Service")
    parser.add_argument(
        "--interface", "-i",
        default="can0",
        help="CAN interface (can0, vcan0, pcan, kvaser)",
    )
    parser.add_argument(
        "--dbc", "-d",
        help="Path to DBC file for proprietary message decoding",
    )
    parser.add_argument(
        "--zmq-port", "-p",
        type=int,
        default=5557,
        help="ZMQ publisher port (default: 5557 for uplink_service)",
    )
    parser.add_argument(
        "--hz",
        type=int,
        default=10,
        help="Telemetry publish rate in Hz (default: 10)",
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Use mock data instead of real CAN",
    )
    parser.add_argument(
        "--motec",
        action="store_true",
        help="Use bundled MoTeC DBC template (for M150/M1/M800 series)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging",
    )
    args = parser.parse_args()

    # Handle --motec flag
    if args.motec and not args.dbc:
        # Look for bundled MoTeC DBC in same directory as script
        import os
        script_dir = os.path.dirname(os.path.abspath(__file__))
        motec_dbc = os.path.join(script_dir, "dbc", "motec_generic.dbc")
        if os.path.exists(motec_dbc):
            args.dbc = motec_dbc
            logger.info(f"Using bundled MoTeC DBC: {motec_dbc}")
        else:
            logger.warning(
                "MoTeC DBC not found. Export your DBC from MoTeC i2 Pro:\n"
                "  1. Open i2 Pro\n"
                "  2. File -> Export -> CAN Protocol (DBC)\n"
                "  3. Save as 'dbc/motec_generic.dbc'\n"
                "  Or use --dbc to specify your exported DBC file."
            )

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    logger.info(f"Starting CAN Telemetry Service")
    logger.info(f"  Interface: {args.interface}")
    logger.info(f"  DBC file: {args.dbc or 'None'}")
    logger.info(f"  ZMQ port: {args.zmq_port}")
    logger.info(f"  Publish rate: {args.hz} Hz")
    logger.info(f"  Mock mode: {args.mock}")

    service = CANTelemetryService(
        interface=args.interface,
        dbc_path=args.dbc,
        zmq_port=args.zmq_port,
        publish_hz=args.hz,
        mock_mode=args.mock,
    )

    try:
        await service.start()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        await service.stop()


if __name__ == "__main__":
    asyncio.run(main())
