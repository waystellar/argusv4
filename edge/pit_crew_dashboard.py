#!/usr/bin/env python3
"""
Argus Pit Crew Dashboard - Local Telemetry Web Server

A password-protected web dashboard for the pit crew to monitor real-time
vehicle telemetry. Runs on the truck's edge device and displays:

- Live CAN bus telemetry (RPM, temps, pressures)
- Real-time charts for key metrics
- Current production camera status
- Connection status to cloud

Architecture:
    [CAN Service] --ZMQ:5557--> [Pit Dashboard] <--HTTP:8080-- [Pit Crew Browser]
                                      |
                                      +---> SSE telemetry stream

ZERO-FRICTION INSTALL:
    1. Service starts automatically after install
    2. First browser visit shows setup wizard to set password
    3. Password is saved to /opt/argus/config/pit_dashboard.json
    4. Subsequent visits require password login

Features:
    - Web-based setup wizard (no command-line config needed)
    - Password-protected access after initial setup
    - Real-time telemetry with Chart.js visualization
    - Shows which camera feed production has selected
    - Responsive design for tablets/phones
    - No internet required - runs entirely on local network

Usage:
    # Service starts automatically via systemd after install
    # Access at: http://truck-ip:8080/

    # Manual start for development:
    python pit_crew_dashboard.py --port 8080

Environment Variables (optional, can be set via web wizard):
    ARGUS_CLOUD_URL        - Cloud API URL (for production status)
    ARGUS_TRUCK_TOKEN      - Auth token for cloud API
    ARGUS_EVENT_ID         - Current event ID
    ARGUS_VEHICLE_NUMBER   - Vehicle number for display
"""
import argparse
import asyncio
import hashlib
import hmac
import json
import logging
import os
import secrets
import socket
import subprocess
import sys
import time

# Ensure sibling modules (e.g. stream_profiles.py) are importable when
# running from /opt/argus/bin/ or any other installed location.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, Dict, Any, Set

# Web framework
from aiohttp import web

# ZMQ for telemetry subscription
try:
    import zmq
    import zmq.asyncio
    ZMQ_AVAILABLE = True
except ImportError:
    ZMQ_AVAILABLE = False
    print("WARNING: pyzmq not installed. Telemetry will be simulated.")

# HTTP client for cloud status
try:
    import httpx
    HTTPX_AVAILABLE = True
except ImportError:
    HTTPX_AVAILABLE = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("pit_dashboard")


def _detect_lan_ip() -> str:
    """EDGE-URL-1: Detect this device's LAN IP address for Pit Crew Portal URL.

    Uses UDP connect trick (no actual traffic sent) to find the interface
    the OS would use to reach an external address. Falls back to hostname lookup.
    """
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.1)
        # Connect to a non-routable address - no traffic is actually sent
        s.connect(("10.255.255.255", 1))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        try:
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            return "127.0.0.1"


# ============ Configuration ============

# Default config file location - can be overridden with env var
CONFIG_FILE_PATH = os.environ.get(
    "ARGUS_PIT_CONFIG",
    "/opt/argus/config/pit_dashboard.json"
)

# Fallback for development (in current directory)
CONFIG_FILE_PATH_DEV = os.path.join(os.path.dirname(__file__), "pit_dashboard_config.json")

# PIT-FUEL-2: Fuel tank capacity constants
# Single source of truth — user can configure 1..250 gal; 95 is just the default.
DEFAULT_TANK_CAPACITY_GAL = 95.0  # Default for new installs; user can change to anything 1-250
MIN_TANK_CAPACITY_GAL = 1.0
MAX_TANK_CAPACITY_GAL = 250.0  # Hard upper bound for user-selectable capacity


def hash_password(password: str) -> str:
    """Hash password using SHA-256 with salt.

    Note: In production, consider using bcrypt, but this avoids
    additional dependencies on the edge device.
    """
    salt = secrets.token_hex(16)
    hash_value = hashlib.pbkdf2_hmac(
        'sha256',
        password.encode(),
        salt.encode(),
        100000
    ).hex()
    return f"{salt}:{hash_value}"


def verify_password(password: str, stored_hash: str) -> bool:
    """Verify password against stored hash."""
    try:
        salt, hash_value = stored_hash.split(':')
        computed = hashlib.pbkdf2_hmac(
            'sha256',
            password.encode(),
            salt.encode(),
            100000
        ).hex()
        return hmac.compare_digest(computed, hash_value)
    except (ValueError, AttributeError):
        return False


def get_config_path() -> str:
    """Get the config file path, trying production then dev location."""
    # Check if production path directory exists
    prod_dir = os.path.dirname(CONFIG_FILE_PATH)
    if os.path.isdir(prod_dir):
        return CONFIG_FILE_PATH
    # Fall back to dev location
    return CONFIG_FILE_PATH_DEV


@dataclass
class DashboardConfig:
    """Dashboard configuration."""
    port: int = 8080
    host: str = "0.0.0.0"
    password_hash: str = ""  # Hashed password (empty = not configured)
    session_secret: str = field(default_factory=lambda: secrets.token_hex(32))

    # Cloud connection
    cloud_url: str = ""
    truck_token: str = ""
    event_id: str = ""
    vehicle_id: str = ""  # Cloud-assigned vehicle ID
    vehicle_number: str = "000"

    # ZMQ ports
    zmq_can_port: int = 5557
    zmq_gps_port: int = 5558
    zmq_ant_port: int = 5556  # ANT+ heart rate monitor

    # YouTube streaming configuration
    youtube_stream_key: str = ""  # Stream key for FFmpeg to push to YouTube
    youtube_live_url: str = ""    # Public URL where fans can watch the stream

    # Cloudflare Tunnel (CGNAT-proof external access)
    cloudflare_tunnel_token: str = ""  # cloudflared service token
    cloudflare_tunnel_url: str = ""    # Public https URL via tunnel

    # PROGRESS-3: Leaderboard poll interval (seconds)
    leaderboard_poll_seconds: int = 60

    @property
    def is_configured(self) -> bool:
        """Check if initial setup has been completed."""
        return bool(self.password_hash)

    def set_password(self, password: str):
        """Set password (hashes it)."""
        self.password_hash = hash_password(password)

    def check_password(self, password: str) -> bool:
        """Verify password against stored hash."""
        return verify_password(password, self.password_hash)

    def save(self, path: Optional[str] = None):
        """Save configuration to JSON file."""
        if path is None:
            path = get_config_path()

        # Ensure directory exists
        os.makedirs(os.path.dirname(path), exist_ok=True)

        data = {
            "password_hash": self.password_hash,
            "session_secret": self.session_secret,
            "cloud_url": self.cloud_url,
            "truck_token": self.truck_token,
            "event_id": self.event_id,
            "vehicle_number": self.vehicle_number,
            "port": self.port,
            "youtube_stream_key": self.youtube_stream_key,
            "youtube_live_url": self.youtube_live_url,
            "cloudflare_tunnel_token": self.cloudflare_tunnel_token,
            "cloudflare_tunnel_url": self.cloudflare_tunnel_url,
        }

        with open(path, 'w') as f:
            json.dump(data, f, indent=2)

        logger.info(f"Configuration saved to {path}")

    @classmethod
    def load(cls, path: Optional[str] = None) -> "DashboardConfig":
        """Load configuration from JSON file, falling back to environment."""
        if path is None:
            path = get_config_path()

        config = cls()

        # Try to load from file
        if os.path.exists(path):
            try:
                with open(path, 'r') as f:
                    data = json.load(f)

                config.password_hash = data.get("password_hash", "")
                config.session_secret = data.get("session_secret", config.session_secret)
                config.cloud_url = data.get("cloud_url", "")
                config.truck_token = data.get("truck_token", "")
                config.event_id = data.get("event_id", "")
                config.vehicle_number = data.get("vehicle_number", "000")
                config.port = data.get("port", 8080)
                config.youtube_stream_key = data.get("youtube_stream_key", "")
                config.youtube_live_url = data.get("youtube_live_url", "")
                config.cloudflare_tunnel_token = data.get("cloudflare_tunnel_token", "")
                config.cloudflare_tunnel_url = data.get("cloudflare_tunnel_url", "")

                logger.info(f"Configuration loaded from {path}")
                return config

            except (json.JSONDecodeError, IOError) as e:
                logger.warning(f"Failed to load config from {path}: {e}")

        # Override with environment variables if set
        if os.environ.get("ARGUS_CLOUD_URL"):
            config.cloud_url = os.environ["ARGUS_CLOUD_URL"]
        if os.environ.get("ARGUS_TRUCK_TOKEN"):
            config.truck_token = os.environ["ARGUS_TRUCK_TOKEN"]
        if os.environ.get("ARGUS_EVENT_ID"):
            config.event_id = os.environ["ARGUS_EVENT_ID"]
        if os.environ.get("ARGUS_VEHICLE_NUMBER"):
            config.vehicle_number = os.environ["ARGUS_VEHICLE_NUMBER"]
        if os.environ.get("ARGUS_PIT_PORT"):
            config.port = int(os.environ["ARGUS_PIT_PORT"])
        if os.environ.get("ARGUS_LEADERBOARD_POLL_SECONDS"):
            config.leaderboard_poll_seconds = int(os.environ["ARGUS_LEADERBOARD_POLL_SECONDS"])
        if os.environ.get("ARGUS_CF_TUNNEL_TOKEN"):
            config.cloudflare_tunnel_token = os.environ["ARGUS_CF_TUNNEL_TOKEN"]
        if os.environ.get("ARGUS_CF_TUNNEL_URL"):
            config.cloudflare_tunnel_url = os.environ["ARGUS_CF_TUNNEL_URL"]

        return config


# ============ Session Management ============

class SessionManager:
    """Simple session management for auth."""

    def __init__(self, secret: str, max_age: int = 86400):
        self.secret = secret.encode()
        self.max_age = max_age
        self.sessions: Dict[str, float] = {}

    def create_session(self) -> str:
        """Create a new session token."""
        token = secrets.token_hex(32)
        self.sessions[token] = time.time()
        return token

    def validate_session(self, token: str) -> bool:
        """Check if session is valid."""
        if not token or token not in self.sessions:
            return False
        created = self.sessions[token]
        if time.time() - created > self.max_age:
            del self.sessions[token]
            return False
        return True

    def invalidate_session(self, token: str):
        """Remove a session."""
        self.sessions.pop(token, None)


# ============ Telemetry State ============

@dataclass
class TelemetryState:
    """Current telemetry values.

    PIT-CAN-1: CAN-sourced temperature/pressure fields are Optional[float] = None
    to prevent phantom values (e.g., 32°F from 0°C) when CAN data is not present.
    UI displays "--" for None values.
    """
    # Engine - PIT-CAN-1: CAN-sourced fields default to None (not 0.0)
    rpm: Optional[float] = None
    coolant_temp: Optional[float] = None  # °C, None until CAN data received
    oil_pressure: Optional[float] = None  # PSI, None until CAN data received
    oil_temp: Optional[float] = None  # °C, None until CAN data received
    fuel_pressure: Optional[float] = None
    throttle_pct: Optional[float] = None
    engine_load: Optional[float] = None
    intake_air_temp: Optional[float] = None  # °C
    boost_pressure: Optional[float] = None  # PSI
    battery_voltage: Optional[float] = None  # V
    fuel_level_pct: Optional[float] = None  # %

    # Vehicle - PIT-CAN-1: CAN-sourced fields default to None
    speed_mps: Optional[float] = None
    gear: Optional[int] = None
    trans_temp: Optional[float] = None  # °C

    # NOTE: Suspension fields removed - not currently in use

    # GPS
    lat: float = 0.0
    lon: float = 0.0
    altitude_m: float = 0.0
    satellites: int = 0
    hdop: float = 0.0  # Horizontal dilution of precision
    heading_deg: float = 0.0  # Course heading in degrees (0-360, 0=North)
    gps_ts_ms: int = 0  # Timestamp of last GPS fix (for stale detection)

    # Driver vitals (from ANT+ service)
    heart_rate: int = 0  # Driver heart rate in BPM

    # Race position (from cloud leaderboard API)
    race_position: int = 0  # Current position (1 = first)
    total_vehicles: int = 0  # Total vehicles in event
    last_checkpoint: int = 0  # Last checkpoint crossed
    delta_to_leader_ms: int = 0  # Time behind leader in ms
    lap_number: int = 0  # Current lap number

    # PROGRESS-3: Course progress + competitor tracking
    progress_miles: Optional[float] = None  # Distance along course (miles)
    miles_remaining: Optional[float] = None  # Distance to finish (miles)
    course_length_miles: Optional[float] = None  # Total course length (miles)
    competitor_ahead: Optional[dict] = None  # {vehicle_number, team_name, progress_miles, miles_remaining, gap_miles}
    competitor_behind: Optional[dict] = None  # Same structure

    # Status
    last_update_ms: int = 0
    cloud_connected: bool = False
    # EDGE-CLOUD-1: Granular cloud connection detail for banner display
    # Values: "not_configured", "healthy", "event_not_live", "unreachable", "auth_rejected"
    cloud_detail: str = "not_configured"
    current_camera: str = "unknown"

    # EDGE-STATUS-1: Boot timestamp for yellow/red distinction during startup
    boot_ts_ms: int = 0

    # EDGE-3: Device status per subsystem
    # Values: "connected", "missing", "simulated", "timeout", "unknown"
    gps_device_status: str = "unknown"
    can_device_status: str = "unknown"
    ant_device_status: str = "unknown"

    def to_dict(self) -> dict:
        """Convert to JSON-serializable dict.

        PIT-CAN-1: CAN-sourced fields return None (not 0) when no data present.
        UI displays "--" for None values instead of phantom 32°F.
        """
        # PIT-CAN-1: Helper to safely round Optional[float]
        def safe_round(val: Optional[float], digits: int) -> Optional[float]:
            return round(val, digits) if val is not None else None

        return {
            "rpm": safe_round(self.rpm, 0),
            "coolant_temp": safe_round(self.coolant_temp, 1),
            "oil_pressure": safe_round(self.oil_pressure, 1),
            "oil_temp": safe_round(self.oil_temp, 1),
            "fuel_pressure": safe_round(self.fuel_pressure, 1),
            "throttle_pct": safe_round(self.throttle_pct, 1),
            "engine_load": safe_round(self.engine_load, 1),
            "intake_air_temp": safe_round(self.intake_air_temp, 1),
            "boost_pressure": safe_round(self.boost_pressure, 1),
            "battery_voltage": safe_round(self.battery_voltage, 1),
            "fuel_level_pct": safe_round(self.fuel_level_pct, 1),
            "trans_temp": safe_round(self.trans_temp, 1),
            "speed_mph": safe_round(self.speed_mps * 2.237, 1) if self.speed_mps is not None else None,
            "speed_mps": safe_round(self.speed_mps, 2),
            "gear": self.gear,
            # NOTE: Suspension fields removed - not currently in use
            "lat": self.lat,
            "lon": self.lon,
            "altitude_m": round(self.altitude_m, 1),
            "satellites": self.satellites,
            "hdop": round(self.hdop, 1),
            "heading_deg": round(self.heading_deg, 1),
            "gps_ts_ms": self.gps_ts_ms,
            "heart_rate": self.heart_rate,
            "race_position": self.race_position,
            "total_vehicles": self.total_vehicles,
            "last_checkpoint": self.last_checkpoint,
            "delta_to_leader_ms": self.delta_to_leader_ms,
            "lap_number": self.lap_number,
            "cloud_connected": self.cloud_connected,
            "cloud_detail": self.cloud_detail,
            "current_camera": self.current_camera,
            "last_update_ms": self.last_update_ms,
            "ts": int(time.time() * 1000),
            # EDGE-STATUS-1: Boot timestamp for yellow/red distinction
            "boot_ts_ms": self.boot_ts_ms,
            # EDGE-3: Device status per subsystem
            "gps_device_status": self.gps_device_status,
            "can_device_status": self.can_device_status,
            "ant_device_status": self.ant_device_status,
            # PROGRESS-3: Course progress + competitor tracking
            "progress_miles": self.progress_miles,
            "miles_remaining": self.miles_remaining,
            "course_length_miles": self.course_length_miles,
            "competitor_ahead": self.competitor_ahead,
            "competitor_behind": self.competitor_behind,
        }


# ============ Dashboard HTML ============
# ENHANCED: Complete rewrite with tabbed navigation, critical alerts,
# driver vitals, camera health panel, gear/load display, and audio status

DASHBOARD_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Pit Crew Dashboard</title>
    <script nonce="__CSP_NONCE__" src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <!-- Leaflet.js for Course Map (Feature 4) -->
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <script nonce="__CSP_NONCE__" src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <style>
        :root {
            --bg-primary: #0a0a0a;
            --bg-secondary: #171717;
            --bg-tertiary: #262626;
            --text-primary: #fafafa;
            --text-secondary: #a3a3a3;
            --text-muted: #737373;
            --accent-blue: #3b82f6;
            --accent-purple: #2563eb;
            --border: #404040;
            --success: #22c55e;
            --warning: #f59e0b;
            --danger: #ef4444;
            --info: #06b6d4;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            min-height: 100vh;
            overflow-x: hidden;
        }

        /* Critical Alerts Banner - Always visible at top when active */
        .alerts-banner {
            display: none;
            background: linear-gradient(90deg, #dc2626 0%, #b91c1c 100%);
            padding: 12px 20px;
            text-align: center;
            font-weight: 700;
            font-size: 1.1rem;
            animation: pulse-alert 1s infinite;
            position: sticky;
            top: 0;
            z-index: 1000;
        }
        .alerts-banner.active { display: block; }
        .alerts-banner .alert-icon { margin-right: 10px; }
        @keyframes pulse-alert {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.8; }
        }

        /* Header */
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 16px;
            background: var(--bg-secondary);
            border-bottom: 1px solid var(--border);
        }
        .header h1 {
            font-size: 1.25rem;
            font-weight: 700;
        }
        .header-right {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .vehicle-num {
            background: rgba(255,255,255,0.2);
            padding: 6px 14px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 1.1rem;
        }
        .header-btn {
            background: rgba(255,255,255,0.15);
            border: none;
            color: white;
            width: 44px;
            height: 44px;
            border-radius: 8px;
            cursor: pointer;
            font-size: 1.2rem;
            display: flex;
            align-items: center;
            justify-content: center;
            text-decoration: none;
        }
        .header-btn:hover { background: rgba(255,255,255,0.25); }
        .header-btn.active { background: var(--success); }
        .header-btn.active:hover { background: var(--success); opacity: 0.9; }

        /* Status Bar */
        .status-bar {
            display: flex;
            gap: 16px;
            padding: 10px 16px;
            background: var(--bg-secondary);
            border-bottom: 1px solid var(--bg-tertiary);
            flex-wrap: wrap;
            align-items: center;
        }
        .status-item {
            display: flex;
            align-items: center;
            gap: 6px;
            font-size: 0.85rem;
        }
        .status-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: var(--danger);
            flex-shrink: 0;
        }
        .status-dot.ok { background: var(--success); }
        .status-dot.warning { background: var(--warning); }
        .status-time { margin-left: auto; color: var(--text-muted); font-size: 0.8rem; }

        /* Tab Navigation */
        .tab-nav {
            display: flex;
            background: var(--bg-secondary);
            border-bottom: 2px solid var(--bg-tertiary);
            overflow-x: auto;
            -webkit-overflow-scrolling: touch;
        }
        .tab-btn {
            flex: 1;
            min-width: 80px;
            padding: 14px 8px;
            background: none;
            border: none;
            color: var(--text-muted);
            font-size: 0.8rem;
            font-weight: 600;
            cursor: pointer;
            text-align: center;
            border-bottom: 3px solid transparent;
            transition: all 0.2s;
            white-space: nowrap;
        }
        .tab-btn:hover { color: var(--text-secondary); background: rgba(255,255,255,0.03); }
        .tab-btn.active {
            color: var(--accent-blue);
            border-bottom-color: var(--accent-blue);
            background: rgba(59, 130, 246, 0.1);
        }
        .tab-btn .tab-icon { font-size: 1.2rem; display: block; margin-bottom: 4px; }

        /* Tab Content */
        .tab-content { display: none; padding: 16px; }
        .tab-content.active { display: block; }

        /* Cards */
        .card {
            background: var(--bg-secondary);
            border-radius: 12px;
            padding: 16px;
            margin-bottom: 16px;
            border: 1px solid var(--bg-tertiary);
        }
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 12px;
            padding-bottom: 10px;
            border-bottom: 1px solid var(--bg-tertiary);
        }
        .card-header h2 {
            font-size: 0.9rem;
            font-weight: 600;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        .card-header .value {
            font-size: 1.4rem;
            font-weight: 700;
        }

        /* Grid layouts */
        .grid-2 { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
        .grid-3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
        .grid-4 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; }
        @media (max-width: 600px) {
            .grid-3, .grid-4 { grid-template-columns: repeat(2, 1fr); }
        }

        /* Gauges */
        .gauge {
            text-align: center;
            padding: 14px 10px;
            background: var(--bg-primary);
            border-radius: 10px;
        }
        .gauge .label {
            font-size: 0.7rem;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 6px;
        }
        .gauge .value {
            font-size: 1.6rem;
            font-weight: 700;
        }
        .gauge .unit {
            font-size: 0.75rem;
            color: var(--text-muted);
        }
        .gauge.warning .value { color: var(--warning); }
        .gauge.danger .value { color: var(--danger); }
        .gauge.success .value { color: var(--success); }

        /* Big center display (RPM, Speed) */
        .big-display {
            text-align: center;
            padding: 20px;
            background: var(--bg-primary);
            border-radius: 12px;
            margin-bottom: 16px;
        }
        .big-display .value {
            font-size: 3.5rem;
            font-weight: 800;
            line-height: 1;
        }
        .big-display .label {
            font-size: 0.85rem;
            color: var(--text-muted);
            margin-top: 6px;
        }
        .big-display .sub-value {
            font-size: 1.2rem;
            color: var(--text-secondary);
            margin-top: 8px;
        }

        /* Gear indicator */
        .gear-display {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 60px;
            height: 60px;
            background: var(--bg-tertiary);
            border-radius: 12px;
            font-size: 2rem;
            font-weight: 800;
            color: var(--accent-blue);
        }

        /* NOTE: Suspension CSS removed - not currently in use */

        /* Camera status grid */
        .camera-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
        .camera-item {
            background: var(--bg-primary);
            border-radius: 10px;
            padding: 14px;
            display: flex;
            align-items: center;
            gap: 12px;
            border: 2px solid transparent;
        }
        .camera-item.streaming { border-color: var(--danger); background: rgba(239, 68, 68, 0.1); }
        .camera-item.online { border-color: var(--success); }
        .camera-item.offline { opacity: 0.5; }
        .camera-icon-wrap {
            width: 44px;
            height: 44px;
            background: var(--bg-tertiary);
            border-radius: 8px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.3rem;
        }
        .camera-info { flex: 1; }
        .camera-info .name { font-weight: 600; font-size: 0.9rem; }
        .camera-info .status { font-size: 0.75rem; color: var(--text-muted); }
        .camera-live-badge {
            background: var(--danger);
            color: white;
            font-size: 0.65rem;
            font-weight: 700;
            padding: 3px 8px;
            border-radius: 4px;
            animation: pulse-alert 1.5s infinite;
        }

        /* Driver vitals */
        .vitals-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; }
        .vital-card {
            background: var(--bg-primary);
            border-radius: 12px;
            padding: 20px;
            text-align: center;
        }
        .vital-icon { font-size: 2rem; margin-bottom: 8px; }
        .vital-value { font-size: 2.5rem; font-weight: 800; }
        .vital-label { font-size: 0.8rem; color: var(--text-muted); margin-top: 4px; }
        .vital-card.heart .vital-value { color: var(--danger); }
        .vital-card.heart.elevated .vital-value { animation: pulse-alert 0.5s infinite; }

        /* Audio/Intercom */
        .audio-panel {
            background: var(--bg-primary);
            border-radius: 12px;
            padding: 16px;
        }
        .audio-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 12px;
        }
        .audio-level-bar {
            height: 20px;
            background: var(--bg-tertiary);
            border-radius: 4px;
            overflow: hidden;
            position: relative;
        }
        .audio-level-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--success), var(--warning), var(--danger));
            transition: width 0.1s;
            border-radius: 4px;
        }
        .audio-level-markers {
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            display: flex;
            justify-content: space-between;
            padding: 0 4px;
            align-items: center;
            pointer-events: none;
        }
        .audio-level-markers span {
            font-size: 0.6rem;
            color: rgba(255,255,255,0.5);
        }
        .last-heard {
            margin-top: 10px;
            font-size: 0.8rem;
            color: var(--text-muted);
        }

        /* Chart containers */
        .chart-container {
            height: 180px;
            position: relative;
        }
        .chart-container.large { height: 220px; }

        /* GPS display */
        .gps-display {
            background: var(--bg-primary);
            border-radius: 10px;
            padding: 14px;
            font-family: 'SF Mono', Monaco, monospace;
        }
        .gps-coords {
            font-size: 1rem;
            margin-bottom: 8px;
        }
        .gps-meta {
            display: flex;
            gap: 16px;
            font-size: 0.8rem;
            color: var(--text-muted);
        }

        /* GPS Stale Warning */
        .gps-stale-warning {
            background: var(--danger);
            color: white;
            padding: 8px 12px;
            border-radius: 6px;
            text-align: center;
            font-weight: bold;
            margin-bottom: 10px;
            animation: pulse 1s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.6; }
        }

        /* GPS Test Mode Indicator */
        .gps-test-mode-indicator {
            background: var(--warning);
            color: #000;
            padding: 8px 12px;
            border-radius: 6px;
            text-align: center;
            font-weight: bold;
            margin-bottom: 10px;
        }

        /* Vehicle Marker Styles */
        .vehicle-marker-container {
            transition: transform 0.3s ease;
        }
        .vehicle-speed-label {
            position: absolute;
            top: 34px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(0,0,0,0.8);
            color: white;
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 10px;
            font-weight: bold;
            white-space: nowrap;
        }
        .vehicle-marker-stale .vehicle-marker-container {
            animation: blink 0.5s infinite;
        }
        @keyframes blink {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.3; }
        }

        /* Offline indicator — EDGE-CLOUD-1: supports multiple states */
        .offline-banner {
            display: none;
            background: var(--warning);
            color: #000;
            padding: 8px 16px;
            text-align: center;
            font-size: 0.85rem;
            font-weight: 600;
        }
        .offline-banner.active { display: block; }
        .offline-banner.info { background: #2196F3; color: #fff; }
        .offline-banner.error { background: var(--danger); color: #fff; }

        /* Pit notes */
        .pit-notes {
            background: var(--bg-primary);
            border-radius: 10px;
            padding: 14px;
        }
        .pit-notes-input {
            width: 100%;
            padding: 12px;
            background: var(--bg-secondary);
            border: 2px solid var(--bg-tertiary);
            border-radius: 8px;
            color: var(--text-primary);
            font-size: 1rem;
            resize: none;
        }
        .pit-notes-input:focus {
            outline: none;
            border-color: var(--accent-blue);
        }
        .pit-notes-btns {
            display: flex;
            gap: 8px;
            margin-top: 10px;
            flex-wrap: wrap;
        }
        .quick-note-btn {
            padding: 10px 14px;
            background: var(--bg-tertiary);
            border: none;
            border-radius: 6px;
            color: var(--text-primary);
            font-size: 0.8rem;
            cursor: pointer;
            white-space: nowrap;
        }
        .quick-note-btn:hover { background: var(--accent-blue); }
        .quick-note-btn.danger { background: var(--danger); }

        /* PIT-SHARING-UI-1: Generic button classes for Team tab */
        .btn {
            padding: 10px 16px;
            background: var(--accent-blue);
            border: none;
            border-radius: 6px;
            color: white;
            font-size: 0.85rem;
            font-weight: 600;
            cursor: pointer;
            transition: opacity 0.15s;
        }
        .btn:hover { opacity: 0.9; }
        .btn:disabled { opacity: 0.5; cursor: not-allowed; }
        .btn-secondary {
            background: var(--bg-tertiary);
            color: var(--text-primary);
        }
        .btn-secondary:hover { background: var(--border); }

        /* PIT-VIS-0: Fan visibility toggle buttons */
        .vis-btn {
            background: var(--bg-tertiary);
            color: var(--text-secondary);
            border: 2px solid transparent;
            transition: background 0.15s, border-color 0.15s, color 0.15s;
        }
        .vis-btn:hover { opacity: 0.9; }
        .vis-btn.vis-on {
            background: var(--success);
            color: #000;
            border-color: var(--success);
            font-weight: 700;
        }
        .vis-btn.vis-off {
            background: var(--danger);
            color: #fff;
            border-color: var(--danger);
            font-weight: 700;
        }

        /* PIT-SHARING-UI-1: Badge for status indicators */
        .badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 0.7rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.03em;
        }

        .send-note-btn {
            padding: 12px 20px;
            background: var(--accent-blue);
            border: none;
            border-radius: 8px;
            color: white;
            font-size: 0.9rem;
            font-weight: 600;
            cursor: pointer;
            margin-top: 10px;
            width: 100%;
        }
        .send-note-btn:hover { opacity: 0.9; }
        .send-note-btn:disabled { opacity: 0.7; cursor: not-allowed; }

        /* Pit Notes History */
        .pit-notes-history {
            margin-top: 12px;
            border-top: 1px solid var(--bg-secondary);
            padding-top: 10px;
        }
        .pit-notes-history-header {
            font-size: 0.75rem;
            color: var(--text-secondary);
            margin-bottom: 6px;
        }
        .pit-note-item {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 6px 8px;
            background: var(--bg-secondary);
            border-radius: 4px;
            margin-bottom: 4px;
            font-size: 0.8rem;
        }
        .pit-note-time {
            color: var(--text-secondary);
            font-size: 0.7rem;
            min-width: 55px;
        }
        .pit-note-text {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .pit-note-sync {
            font-size: 0.7rem;
        }
        .pit-note-empty {
            color: var(--text-secondary);
            font-size: 0.75rem;
            font-style: italic;
            padding: 8px;
            text-align: center;
        }

        /* P1: Fuel Level Bar */
        .fuel-level-bar {
            width: 100%;
            height: 24px;
            background: var(--bg-primary);
            border-radius: 4px;
            overflow: hidden;
            position: relative;
        }
        .fuel-level-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--danger), var(--warning), var(--success));
            transition: width 0.3s ease;
        }
        .fuel-level-bar::after {
            content: '';
            position: absolute;
            left: 25%;
            top: 0;
            bottom: 0;
            width: 2px;
            background: rgba(255,255,255,0.3);
        }
        .fuel-critical { background: var(--danger) !important; }
        .fuel-warning { background: linear-gradient(90deg, var(--danger), var(--warning)) !important; }

        /* PIT-5R: Per-axle tire tracking */
        .tire-axle-row {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px;
            background: var(--bg-tertiary);
            border-radius: 8px;
            margin-bottom: 8px;
        }
        .tire-axle-label {
            font-weight: 700;
            font-size: 0.85rem;
            color: var(--accent);
            min-width: 50px;
        }
        .tire-axle-info {
            flex: 1;
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            align-items: center;
            font-size: 0.85rem;
        }
        .tire-brand-display {
            font-weight: 600;
            color: var(--text-primary);
        }
        .tire-miles-display {
            color: var(--text-primary);
            font-weight: 700;
            font-size: 1rem;
        }
        .tire-changed-display {
            color: var(--text-muted);
            font-size: 0.75rem;
        }
        .tire-reset-btn {
            white-space: nowrap;
            font-size: 0.8rem;
        }

        /* P1: Pit Checklist */
        .pit-checklist {
            display: flex;
            flex-direction: column;
            gap: 12px;
        }
        .checklist-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px;
            background: var(--bg-tertiary);
            border-radius: 6px;
            cursor: pointer;
            min-height: 48px;
        }
        .checklist-item input[type="checkbox"] {
            width: 24px;
            height: 24px;
            accent-color: var(--success);
        }
        .checklist-item:has(input:checked) {
            background: rgba(34, 197, 94, 0.2);
            color: var(--success);
        }

        /* P1: Position highlight */
        #positionDisplay {
            background: linear-gradient(135deg, var(--bg-secondary), var(--bg-tertiary));
            border: 2px solid var(--accent-blue);
        }
        #positionDisplay.leading {
            border-color: var(--warning);
            background: linear-gradient(135deg, rgba(234, 179, 8, 0.1), var(--bg-tertiary));
        }

        /* P2: Pit Stop Timer */
        .pit-timer-panel {
            text-align: center;
            padding: 16px;
        }
        .pit-timer-display {
            font-family: 'SF Mono', 'Monaco', monospace;
            font-size: 3rem;
            font-weight: 700;
            color: var(--text-primary);
            background: var(--bg-primary);
            padding: 16px 24px;
            border-radius: 8px;
            margin-bottom: 16px;
        }
        .pit-timer-display.running {
            color: var(--success);
            animation: pulse 1s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.7; }
        }
        .pit-timer-btns {
            display: flex;
            gap: 8px;
            justify-content: center;
            margin-bottom: 16px;
        }
        .timer-btn {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            font-size: 1rem;
            font-weight: 600;
            cursor: pointer;
            min-width: 100px;
        }
        .timer-btn.start { background: var(--success); color: white; }
        .timer-btn.stop { background: var(--danger); color: white; }
        .timer-btn.reset { background: var(--bg-tertiary); color: var(--text-primary); }
        .timer-btn:disabled { opacity: 0.5; cursor: not-allowed; }
        .pit-timer-history {
            text-align: left;
            border-top: 1px solid var(--bg-tertiary);
            padding-top: 12px;
            margin-top: 12px;
        }
        .timer-history-title {
            font-size: 0.8rem;
            color: var(--text-secondary);
            margin-bottom: 8px;
        }
        #pitTimerHistory {
            font-family: monospace;
            font-size: 0.85rem;
            color: var(--text-secondary);
        }
        .pit-time-entry {
            display: flex;
            justify-content: space-between;
            padding: 4px 0;
        }
        .pit-time-entry .time { color: var(--accent-blue); }

        /* P2: Competitors List */
        .competitors-list {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        .competitor-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 12px;
            background: var(--bg-tertiary);
            border-radius: 6px;
        }
        .competitor-item.loading {
            justify-content: center;
            color: var(--text-secondary);
        }
        .competitor-item.ahead { border-left: 3px solid var(--warning); }
        .competitor-item.behind { border-left: 3px solid var(--success); }
        .competitor-num {
            font-weight: 700;
            font-size: 1.1rem;
            min-width: 50px;
        }
        .competitor-name {
            flex: 1;
            margin-left: 12px;
            color: var(--text-secondary);
        }
        .competitor-delta {
            font-family: monospace;
            font-weight: 600;
        }
        .competitor-delta.ahead { color: var(--warning); }
        .competitor-delta.behind { color: var(--success); }

        /* Device Management Styles */
        .device-list {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        .device-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 12px;
            background: var(--bg-primary);
            border-radius: 8px;
            border: 1px solid var(--bg-tertiary);
        }
        .device-item.online { border-color: var(--success); }
        .device-item.offline { border-color: var(--danger); opacity: 0.7; }
        .device-item.loading { justify-content: center; color: var(--text-secondary); }
        .device-item .device-icon { font-size: 1.5rem; margin-right: 12px; }
        .device-item .device-info { flex: 1; }
        .device-item .device-name { font-weight: 600; font-size: 0.9rem; }
        .device-item .device-path { font-size: 0.75rem; color: var(--text-muted); font-family: monospace; }
        .device-status-badge {
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 0.7rem;
            font-weight: 600;
            text-transform: uppercase;
        }
        .device-status-badge.online { background: rgba(34, 197, 94, 0.2); color: var(--success); }
        .device-status-badge.offline { background: rgba(239, 68, 68, 0.2); color: var(--danger); }
        .device-status-badge.warning { background: rgba(245, 158, 11, 0.2); color: var(--warning); }
        .device-info-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
        }
        .device-info-item {
            background: var(--bg-primary);
            padding: 10px;
            border-radius: 6px;
        }
        .device-info-item .info-label {
            display: block;
            font-size: 0.7rem;
            color: var(--text-muted);
            text-transform: uppercase;
            margin-bottom: 4px;
        }
        .device-info-item .info-value {
            font-size: 0.95rem;
            font-weight: 600;
            font-family: 'SF Mono', Monaco, monospace;
        }
        .camera-mapping-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
        }
        .mapping-item {
            display: flex;
            flex-direction: column;
            gap: 6px;
        }
        .mapping-item label {
            font-size: 0.8rem;
            color: var(--text-secondary);
        }
        .mapping-item select {
            padding: 8px 10px;
            background: var(--bg-primary);
            border: 1px solid var(--bg-tertiary);
            border-radius: 6px;
            color: var(--text-primary);
            font-size: 0.85rem;
        }
        .mapping-item select:focus {
            outline: none;
            border-color: var(--accent-blue);
        }
        .device-config-row {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .device-config-row select {
            padding: 8px 10px;
            background: var(--bg-primary);
            border: 1px solid var(--bg-tertiary);
            border-radius: 6px;
            color: var(--text-primary);
            font-size: 0.85rem;
        }
        .service-status-grid {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        .service-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 12px;
            background: var(--bg-primary);
            border-radius: 6px;
        }
        .service-name {
            font-family: 'SF Mono', Monaco, monospace;
            font-size: 0.85rem;
        }
        .service-status {
            font-size: 0.75rem;
            padding: 3px 8px;
            border-radius: 4px;
        }
        /* PIT-SVC-2: Unified service status colors */
        .service-status.ok { background: rgba(34, 197, 94, 0.2); color: var(--success); }
        .service-status.running { background: rgba(34, 197, 94, 0.2); color: var(--success); }
        .service-status.warn { background: rgba(245, 158, 11, 0.2); color: var(--warning); }
        .service-status.error { background: rgba(239, 68, 68, 0.2); color: var(--danger); }
        .service-status.stopped { background: rgba(239, 68, 68, 0.2); color: var(--danger); }
        .service-status.off { background: rgba(100, 116, 139, 0.2); color: var(--text-muted); }
        .service-status.inactive { background: rgba(100, 116, 139, 0.2); color: var(--text-muted); }
        .service-status.unknown { background: rgba(100, 116, 139, 0.2); color: var(--text-muted); }
        .service-detail { font-size: 0.65rem; color: var(--text-muted); margin-top: 2px; }

        /* Screenshot Grid Styles (Feature 1: Stream Control) */
        .screenshot-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
            margin-bottom: 16px;
        }
        .screenshot-card {
            background: var(--bg-secondary);
            border-radius: 12px;
            overflow: hidden;
            border: 1px solid var(--bg-tertiary);
        }
        .screenshot-card.live {
            border: 2px solid var(--danger);
            box-shadow: 0 0 20px rgba(239, 68, 68, 0.3);
        }
        .screenshot-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 12px;
            background: var(--bg-tertiary);
        }
        .screenshot-title {
            font-weight: 600;
            font-size: 0.85rem;
        }
        .screenshot-status-badge {
            font-size: 0.65rem;
            font-weight: 600;
            padding: 3px 8px;
            border-radius: 10px;
            text-transform: uppercase;
        }
        .screenshot-status-badge.online { background: rgba(34, 197, 94, 0.2); color: var(--success); }
        .screenshot-status-badge.offline { background: rgba(239, 68, 68, 0.2); color: var(--danger); }
        .screenshot-status-badge.error { background: rgba(245, 158, 11, 0.2); color: var(--warning); }
        .screenshot-status-badge.stale { background: rgba(100, 116, 139, 0.2); color: var(--text-muted); }
        .screenshot-container {
            position: relative;
            width: 100%;
            aspect-ratio: 4/3;
            background: var(--bg-primary);
            cursor: pointer;
            overflow: hidden;
        }
        .screenshot-img {
            width: 100%;
            height: 100%;
            object-fit: cover;
            transition: transform 0.2s;
        }
        .screenshot-container:hover .screenshot-img {
            transform: scale(1.02);
        }
        .screenshot-placeholder {
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            color: var(--text-muted);
        }
        .placeholder-icon {
            font-size: 3rem;
            opacity: 0.3;
            margin-bottom: 8px;
        }
        .placeholder-text {
            font-size: 0.85rem;
        }
        .screenshot-overlay {
            position: absolute;
            top: 8px;
            right: 8px;
        }
        .screenshot-live-badge {
            background: var(--danger);
            color: white;
            font-size: 0.7rem;
            font-weight: 700;
            padding: 4px 10px;
            border-radius: 4px;
            animation: pulse-alert 1.5s infinite;
        }
        .screenshot-footer {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 8px 12px;
            font-size: 0.75rem;
            color: var(--text-muted);
            background: rgba(0,0,0,0.2);
        }
        .screenshot-res {
            font-family: 'SF Mono', Monaco, monospace;
        }
        .screenshot-age {
            flex: 1;
            text-align: center;
        }
        .screenshot-capture-btn {
            background: var(--bg-tertiary);
            border: none;
            padding: 4px 8px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.9rem;
        }
        .screenshot-capture-btn:hover {
            background: var(--accent-blue);
        }

        /* Screenshot Modal */
        .screenshot-modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0,0,0,0.9);
            z-index: 2000;
            align-items: center;
            justify-content: center;
        }
        .screenshot-modal.active {
            display: flex;
        }
        .screenshot-modal-content {
            position: relative;
            max-width: 95vw;
            max-height: 90vh;
        }
        .screenshot-modal-content img {
            max-width: 100%;
            max-height: 85vh;
            border-radius: 8px;
        }
        .screenshot-modal-info {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            color: var(--text-secondary);
            font-size: 0.9rem;
        }
        .screenshot-modal-close {
            position: absolute;
            top: -40px;
            right: 0;
            background: none;
            border: none;
            color: white;
            font-size: 1.5rem;
            cursor: pointer;
            padding: 8px;
        }

        /* Stream Info Grid */
        .stream-info-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
        }
        .stream-info-item {
            background: var(--bg-primary);
            padding: 12px;
            border-radius: 8px;
        }
        .stream-label {
            display: block;
            font-size: 0.7rem;
            color: var(--text-muted);
            text-transform: uppercase;
            margin-bottom: 4px;
        }
        .stream-value {
            font-size: 0.95rem;
            font-weight: 600;
        }
        .stream-value.link {
            color: var(--accent-blue);
            text-decoration: none;
            word-break: break-all;
        }

        /* Streaming Control Styles */
        .stream-status-badge {
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.75rem;
            font-weight: bold;
            text-transform: uppercase;
        }
        .stream-status-badge.idle {
            background: var(--bg-tertiary);
            color: var(--text-muted);
        }
        .stream-status-badge.starting {
            background: var(--warning);
            color: #000;
            animation: pulse 1s infinite;
        }
        .stream-status-badge.live {
            background: var(--danger);
            color: #fff;
            animation: pulse 2s infinite;
        }
        .stream-status-badge.error {
            background: var(--danger);
            color: #fff;
        }
        /* EDGE-6: Paused/warning state for stream supervisor */
        .stream-status-badge.warning {
            background: var(--warning);
            color: #000;
        }
        .stream-action-btn {
            padding: 10px 20px;
            border-radius: 8px;
            font-weight: bold;
            font-size: 0.9rem;
            cursor: pointer;
            border: none;
            transition: all 0.2s;
        }
        .stream-action-btn.start {
            background: var(--success);
            color: #fff;
        }
        .stream-action-btn.start:hover {
            background: #1fa34a;
            transform: scale(1.02);
        }
        .stream-action-btn.start:disabled {
            background: var(--bg-tertiary);
            color: var(--text-muted);
            cursor: not-allowed;
            transform: none;
        }
        .stream-action-btn.stop {
            background: var(--danger);
            color: #fff;
        }
        .stream-action-btn.stop:hover {
            background: #d93636;
            transform: scale(1.02);
        }

        /* STREAM-1: Prominent error banner for streaming failures */
        .stream-error-banner {
            margin-top: 10px;
            padding: 12px 16px;
            border-radius: 8px;
            background: rgba(239, 68, 68, 0.12);
            border: 1px solid var(--danger);
            color: var(--text-primary);
            font-size: 0.85rem;
        }
        .stream-error-banner strong { color: var(--danger); }
        .stream-error-banner a {
            color: var(--accent-blue);
            text-decoration: underline;
            cursor: pointer;
            font-weight: 600;
        }

        /* NASCAR-Style Tachometer (Feature 2: Enhanced Telemetry) */
        /* PIT-3: 2x2 Engine Grid */
        .engine-2x2-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
            margin-bottom: 16px;
        }
        .engine-tile {
            background: var(--bg-secondary);
            border-radius: 12px;
            padding: 14px;
            text-align: center;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            min-height: 110px;
        }
        .engine-tile-rpm {
            padding: 8px;
        }
        .engine-tile-rpm .tachometer-container {
            width: 100%;
            height: auto;
            padding: 8px;
        }
        .engine-tile-label {
            display: block;
            font-size: 0.7rem;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 4px;
        }
        .engine-tile-value {
            display: flex;
            align-items: baseline;
            justify-content: center;
            gap: 4px;
        }
        .engine-tile-big {
            font-size: 2.2rem;
            font-weight: 800;
            color: var(--text-primary);
            font-family: 'SF Mono', Monaco, monospace;
            line-height: 1;
        }
        .engine-tile-unit {
            font-size: 0.8rem;
            color: var(--text-muted);
        }
        .engine-tile .gear-indicator {
            background: none;
            padding: 0;
        }
        .engine-tile .speed-value {
            font-size: 2.8rem;
        }
        .tachometer-container {
            position: relative;
            width: 200px;
            height: 140px;
            background: var(--bg-secondary);
            border-radius: 16px;
            padding: 16px;
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        .tachometer {
            width: 100%;
            height: 100px;
        }
        .tach-bg {
            fill: none;
            stroke: var(--bg-tertiary);
            stroke-width: 14;
            stroke-linecap: round;
        }
        .tach-warning-zone {
            fill: none;
            stroke: rgba(245, 158, 11, 0.3);
            stroke-width: 14;
            stroke-linecap: round;
        }
        .tach-redline-zone {
            fill: none;
            stroke: rgba(239, 68, 68, 0.4);
            stroke-width: 14;
            stroke-linecap: round;
        }
        .tach-active {
            fill: none;
            stroke: var(--accent-blue);
            stroke-width: 14;
            stroke-linecap: round;
            transition: stroke 0.15s;
        }
        .tach-active.warning { stroke: var(--warning); }
        .tach-active.danger { stroke: var(--danger); }
        .tach-needle {
            stroke: white;
            stroke-width: 3;
            stroke-linecap: round;
            transform-origin: 100px 100px;
            transition: transform 0.1s ease-out;
        }
        .tach-center {
            fill: var(--bg-tertiary);
            stroke: white;
            stroke-width: 2;
        }
        .tach-value {
            position: absolute;
            bottom: 10px;
            text-align: center;
            width: 100%;
        }
        .tach-value span:first-child {
            font-size: 1.8rem;
            font-weight: 800;
            color: var(--text-primary);
            font-family: 'SF Mono', Monaco, monospace;
        }
        .tach-unit {
            display: block;
            font-size: 0.7rem;
            color: var(--text-muted);
            text-transform: uppercase;
        }
        .tach-redline-label {
            position: absolute;
            top: 10px;
            right: 14px;
            font-size: 0.65rem;
            color: var(--danger);
            font-weight: 600;
        }

        /* Gear & Speed Display */
        .gear-speed-display {
            display: flex;
            flex-direction: column;
            gap: 12px;
            min-width: 140px;
        }
        .gear-indicator {
            background: var(--bg-secondary);
            border-radius: 12px;
            padding: 16px;
            text-align: center;
        }
        .gear-indicator .gear-label {
            display: block;
            font-size: 0.7rem;
            color: var(--text-muted);
            text-transform: uppercase;
            margin-bottom: 4px;
        }
        .gear-indicator .gear-value {
            font-size: 3rem;
            font-weight: 900;
            color: var(--accent-blue);
            line-height: 1;
        }
        .speed-display {
            background: var(--bg-secondary);
            border-radius: 12px;
            padding: 12px;
            text-align: center;
        }
        .speed-display .speed-value {
            font-size: 2.2rem;
            font-weight: 800;
            color: var(--text-primary);
            font-family: 'SF Mono', Monaco, monospace;
        }
        .speed-display .speed-unit {
            font-size: 0.8rem;
            color: var(--text-muted);
            margin-left: 4px;
        }
        /* Load bar styles removed (PIT-3) */

        /* Telemetry Freshness Indicator */
        .telemetry-freshness {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 8px 14px;
            background: var(--bg-secondary);
            border-radius: 8px;
            margin-bottom: 12px;
            font-size: 0.8rem;
        }
        .freshness-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: var(--success);
            animation: pulse 1s infinite;
        }
        .telemetry-freshness.stale .freshness-dot {
            background: var(--warning);
            animation: none;
        }
        .telemetry-freshness.offline .freshness-dot {
            background: var(--danger);
            animation: none;
        }

        /* 4-column grid for Engine Vitals */
        .grid-4 {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 12px;
        }
        @media (max-width: 768px) {
            .grid-4 { grid-template-columns: repeat(2, 1fr); }
        }

        /* Chart Legend */
        .chart-legend {
            display: flex;
            gap: 16px;
            font-size: 0.75rem;
        }
        .legend-item {
            display: flex;
            align-items: center;
            gap: 4px;
            color: var(--text-muted);
        }
        .legend-color {
            width: 12px;
            height: 12px;
            border-radius: 3px;
        }
        .legend-color.rpm { background: #ef4444; }
        .legend-color.throttle { background: #22c55e; }

        /* Heart Rate Zones (Feature 3) */
        .hr-hero-display {
            background: var(--bg-secondary);
            border-radius: 16px;
            padding: 24px;
            text-align: center;
            margin-bottom: 16px;
            position: relative;
            overflow: hidden;
        }
        .hr-hero-display::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: radial-gradient(circle, rgba(239, 68, 68, 0.2) 0%, transparent 70%);
            animation: hr-pulse 1s ease-in-out infinite;
            pointer-events: none;
        }
        .hr-hero-display.zone-rest::before { background: radial-gradient(circle, rgba(148, 163, 184, 0.2) 0%, transparent 70%); }
        .hr-hero-display.zone-warmup::before { background: radial-gradient(circle, rgba(59, 130, 246, 0.2) 0%, transparent 70%); }
        .hr-hero-display.zone-fatburn::before { background: radial-gradient(circle, rgba(34, 197, 94, 0.2) 0%, transparent 70%); }
        .hr-hero-display.zone-cardio::before { background: radial-gradient(circle, rgba(245, 158, 11, 0.2) 0%, transparent 70%); }
        .hr-hero-display.zone-peak::before { background: radial-gradient(circle, rgba(239, 68, 68, 0.2) 0%, transparent 70%); }
        .hr-hero-display.zone-max::before { background: radial-gradient(circle, rgba(168, 85, 247, 0.3) 0%, transparent 70%); }
        @keyframes hr-pulse {
            0%, 100% { opacity: 0.5; transform: scale(1); }
            50% { opacity: 1; transform: scale(1.05); }
        }
        .hr-value-large {
            font-size: 4.5rem;
            font-weight: 900;
            line-height: 1;
            position: relative;
            z-index: 1;
        }
        .hr-value-large.zone-rest { color: #94a3b8; }
        .hr-value-large.zone-warmup { color: #3b82f6; }
        .hr-value-large.zone-fatburn { color: #22c55e; }
        .hr-value-large.zone-cardio { color: #f59e0b; }
        .hr-value-large.zone-peak { color: #ef4444; }
        .hr-value-large.zone-max { color: #a855f7; animation: pulse-alert 0.5s infinite; }
        .hr-label {
            font-size: 0.9rem;
            color: var(--text-muted);
            margin-top: 8px;
            position: relative;
            z-index: 1;
        }
        .hr-zone-name {
            display: inline-block;
            font-size: 1.1rem;
            font-weight: 700;
            padding: 6px 16px;
            border-radius: 20px;
            margin-top: 12px;
            position: relative;
            z-index: 1;
        }
        .hr-zone-name.zone-rest { background: rgba(148, 163, 184, 0.2); color: #94a3b8; }
        .hr-zone-name.zone-warmup { background: rgba(59, 130, 246, 0.2); color: #3b82f6; }
        .hr-zone-name.zone-fatburn { background: rgba(34, 197, 94, 0.2); color: #22c55e; }
        .hr-zone-name.zone-cardio { background: rgba(245, 158, 11, 0.2); color: #f59e0b; }
        .hr-zone-name.zone-peak { background: rgba(239, 68, 68, 0.2); color: #ef4444; }
        .hr-zone-name.zone-max { background: rgba(168, 85, 247, 0.3); color: #a855f7; }

        /* HR Zone Bar */
        .hr-zone-bar {
            display: flex;
            height: 12px;
            border-radius: 6px;
            overflow: hidden;
            margin: 16px 0;
            background: var(--bg-tertiary);
        }
        .hr-zone-bar .zone-segment {
            height: 100%;
            position: relative;
        }
        .hr-zone-bar .zone-segment.rest { background: #64748b; flex: 1; }
        .hr-zone-bar .zone-segment.warmup { background: #3b82f6; flex: 1; }
        .hr-zone-bar .zone-segment.fatburn { background: #22c55e; flex: 1; }
        .hr-zone-bar .zone-segment.cardio { background: #f59e0b; flex: 1; }
        .hr-zone-bar .zone-segment.peak { background: #ef4444; flex: 1; }
        .hr-zone-bar .zone-segment.max { background: #a855f7; flex: 0.5; }
        .hr-zone-marker {
            position: absolute;
            top: -4px;
            width: 4px;
            height: 20px;
            background: white;
            border-radius: 2px;
            box-shadow: 0 0 8px rgba(0,0,0,0.5);
            transform: translateX(-50%);
            transition: left 0.2s ease-out;
        }
        .hr-zone-labels {
            display: flex;
            justify-content: space-between;
            font-size: 0.65rem;
            color: var(--text-muted);
            margin-top: 4px;
        }

        /* HR Stats Grid */
        .hr-stats-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 12px;
            margin: 16px 0;
        }
        .hr-stat-card {
            background: var(--bg-primary);
            border-radius: 10px;
            padding: 14px;
            text-align: center;
        }
        .hr-stat-value {
            font-size: 1.6rem;
            font-weight: 700;
            color: var(--text-primary);
        }
        .hr-stat-label {
            font-size: 0.7rem;
            color: var(--text-muted);
            text-transform: uppercase;
            margin-top: 4px;
        }
        .hr-stat-card.peak .hr-stat-value { color: #ef4444; }
        .hr-stat-card.avg .hr-stat-value { color: #f59e0b; }

        /* Time in Zone Display */
        .zone-time-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 8px;
        }
        .zone-time-item {
            background: var(--bg-primary);
            border-radius: 8px;
            padding: 10px;
            text-align: center;
        }
        .zone-time-item .zone-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            display: inline-block;
            margin-right: 6px;
        }
        .zone-time-item .zone-dot.rest { background: #64748b; }
        .zone-time-item .zone-dot.warmup { background: #3b82f6; }
        .zone-time-item .zone-dot.fatburn { background: #22c55e; }
        .zone-time-item .zone-dot.cardio { background: #f59e0b; }
        .zone-time-item .zone-dot.peak { background: #ef4444; }
        .zone-time-item .zone-dot.max { background: #a855f7; }
        .zone-time-item .zone-name {
            font-size: 0.7rem;
            color: var(--text-muted);
        }
        .zone-time-item .zone-duration {
            font-size: 1rem;
            font-weight: 600;
            font-family: 'SF Mono', Monaco, monospace;
        }

        /* ANT+ Status Card */
        .ant-status-card {
            display: flex;
            align-items: center;
            gap: 12px;
            background: var(--bg-primary);
            border-radius: 10px;
            padding: 12px 16px;
            margin-bottom: 16px;
        }
        .ant-status-icon {
            font-size: 1.5rem;
        }
        .ant-status-info {
            flex: 1;
        }
        .ant-status-info .device-name {
            font-weight: 600;
            font-size: 0.9rem;
        }
        .ant-status-info .device-id {
            font-size: 0.75rem;
            color: var(--text-muted);
            font-family: monospace;
        }
        .ant-battery {
            display: flex;
            align-items: center;
            gap: 6px;
            font-size: 0.8rem;
            color: var(--text-secondary);
        }

        /* Course Map Styles (Feature 4) */
        .course-map-container {
            height: 300px;
            border-radius: 12px;
            overflow: hidden;
            background: var(--bg-tertiary);
            position: relative;
        }
        .course-map-container #courseMap {
            height: 100%;
            width: 100%;
        }
        .map-placeholder {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100%;
            color: var(--text-muted);
            text-align: center;
            padding: 20px;
        }
        .map-placeholder-icon {
            font-size: 3rem;
            margin-bottom: 12px;
            opacity: 0.5;
        }
        .gpx-upload-zone {
            background: var(--bg-primary);
            border: 2px dashed var(--bg-tertiary);
            border-radius: 12px;
            padding: 24px;
            text-align: center;
            cursor: pointer;
            transition: border-color 0.2s, background 0.2s;
            margin-top: 16px;
        }
        .gpx-upload-zone:hover {
            border-color: var(--accent-blue);
            background: rgba(59, 130, 246, 0.05);
        }
        .gpx-upload-zone.dragover {
            border-color: var(--success);
            background: rgba(34, 197, 94, 0.1);
        }
        .gpx-upload-zone input[type="file"] {
            display: none;
        }
        .gpx-upload-icon {
            font-size: 2.5rem;
            margin-bottom: 8px;
        }
        .gpx-upload-text {
            color: var(--text-secondary);
            font-size: 0.9rem;
        }
        .gpx-upload-hint {
            color: var(--text-muted);
            font-size: 0.75rem;
            margin-top: 6px;
        }
        .course-progress-bar {
            height: 10px;
            background: var(--bg-tertiary);
            border-radius: 5px;
            overflow: hidden;
            margin: 16px 0;
        }
        .course-progress-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--accent-blue), var(--success));
            border-radius: 5px;
            transition: width 0.3s ease-out;
        }
        .course-stats-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 12px;
        }
        .course-stat {
            background: var(--bg-primary);
            border-radius: 10px;
            padding: 12px;
            text-align: center;
        }
        .course-stat-value {
            font-size: 1.4rem;
            font-weight: 700;
            color: var(--text-primary);
            font-family: 'SF Mono', Monaco, monospace;
        }
        .course-stat-label {
            font-size: 0.65rem;
            color: var(--text-muted);
            text-transform: uppercase;
            margin-top: 4px;
        }
        .course-loaded-info {
            display: flex;
            align-items: center;
            gap: 12px;
            background: var(--bg-primary);
            border-radius: 10px;
            padding: 12px 16px;
            margin-bottom: 16px;
        }
        .course-loaded-icon {
            font-size: 1.5rem;
        }
        .course-loaded-details {
            flex: 1;
        }
        .course-loaded-name {
            font-weight: 600;
            font-size: 0.9rem;
        }
        .course-loaded-meta {
            font-size: 0.75rem;
            color: var(--text-muted);
        }
        .course-clear-btn {
            background: var(--bg-tertiary);
            border: none;
            padding: 8px 12px;
            border-radius: 6px;
            color: var(--text-secondary);
            font-size: 0.8rem;
            cursor: pointer;
        }
        .course-clear-btn:hover {
            background: var(--danger);
            color: white;
        }
        @media (max-width: 768px) {
            .course-stats-grid { grid-template-columns: repeat(2, 1fr); }
        }

        /* Responsive */
        @media (max-width: 600px) {
            .big-display .value { font-size: 2.5rem; }
            .gauge .value { font-size: 1.3rem; }
            .vitals-grid { grid-template-columns: 1fr; }
            .camera-grid { grid-template-columns: 1fr; }
            .device-info-grid { grid-template-columns: 1fr; }
            .camera-mapping-grid { grid-template-columns: 1fr; }
            .screenshot-grid { grid-template-columns: 1fr; }
            .stream-info-grid { grid-template-columns: 1fr; }
            .screenshot-title { font-size: 0.8rem; }
            .tachometer-container { width: 100%; }
            .gear-indicator .gear-value { font-size: 2.5rem; }
            .engine-tile .speed-value { font-size: 2rem; }
            .engine-tile-big { font-size: 1.8rem; }
            .engine-2x2-grid { gap: 8px; }
        }
    </style>
</head>
<body>
    <!-- Critical Alerts Banner -->
    <div class="alerts-banner" id="alertsBanner">
        <span class="alert-icon">!</span>
        <span id="alertText">SYSTEM ALERT</span>
    </div>

    <!-- Offline Banner -->
    <div class="offline-banner" id="offlineBanner">
        Cloud connection lost - Data buffered locally
    </div>

    <!-- Tunnel Not Configured Banner — persistent until Cloudflare Tunnel is set up -->
    <div id="tunnelBanner" style="display:__TUNNEL_BANNER_DISPLAY__;background:rgba(245,158,11,0.15);border-bottom:1px solid rgba(245,158,11,0.4);color:#fcd34d;text-align:center;padding:8px 16px;font-size:0.8rem;">
        <strong>No Cloudflare Tunnel configured.</strong>
        Remote access is unavailable (Starlink/CGNAT blocks inbound connections).
        <a href="/settings" style="color:#fbbf24;text-decoration:underline;margin-left:6px;">Configure in Settings</a>
    </div>

    <!-- Header -->
    <div class="header">
        <h1>Pit Crew</h1>
        <div class="header-right">
            <span class="vehicle-num" id="vehicleNum">#---</span>
            <button class="header-btn active" id="voiceAlertBtn" data-click="toggleVoiceAlerts" title="Voice Alerts">Voice</button>
            <a href="/settings" class="header-btn" title="Settings">Settings</a>
            <button class="header-btn" data-click="logout" title="Logout">Logout</button>
        </div>
    </div>

    <!-- Status Bar — EDGE-3: Status dots now show tooltips with device status detail -->
    <!-- EDGE-4: Added edge readiness indicator as first item -->
    <div class="status-bar">
        <div class="status-item">
            <div class="status-dot" id="edgeReadiness" title="Edge: checking..."></div>
            <span id="edgeReadinessLabel">Edge</span>
        </div>
        <div style="border-left: 1px solid rgba(255,255,255,0.2); height: 20px; margin: 0 4px;"></div>
        <div class="status-item">
            <div class="status-dot" id="canStatus" title="CAN: unknown"></div>
            <span>CAN</span>
        </div>
        <div class="status-item">
            <div class="status-dot" id="gpsStatus" title="GPS: unknown"></div>
            <span>GPS</span>
        </div>
        <div class="status-item">
            <div class="status-dot" id="cloudStatus"></div>
            <span>Cloud</span>
        </div>
        <div class="status-item">
            <div class="status-dot" id="antStatus" title="ANT+: unknown"></div>
            <span>ANT+</span>
        </div>
        <div class="status-item">
            <div class="status-dot" id="audioStatus"></div>
            <span>Audio</span>
        </div>
        <span class="status-time" id="lastUpdate">--:--:--</span>
    </div>

    <!-- Tab Navigation -->
    <nav class="tab-nav">
        <button class="tab-btn active" data-tab="engine">
            Engine
        </button>
        <button class="tab-btn" data-tab="vehicle">
            Vehicle
        </button>
        <button class="tab-btn" data-tab="cameras">
            Cameras
        </button>
        <button class="tab-btn" data-tab="driver">
            Driver
        </button>
        <button class="tab-btn" data-tab="comms">
            Comms
        </button>
        <button class="tab-btn" data-tab="race">
            Race
        </button>
        <button class="tab-btn" data-tab="course">
            Course
        </button>
        <button class="tab-btn" data-tab="team">
            Team
        </button>
        <button class="tab-btn" data-tab="devices">
            Devices
        </button>
    </nav>

    <!-- Tab: Engine - ENHANCED with NASCAR-style tachometer -->
    <div class="tab-content active" id="tab-engine">
        <!-- PIT-3: Primary Engine Display — 2x2 Grid: Speed/RPM/Gear/Coolant -->
        <div class="engine-2x2-grid">
            <!-- Top-left: Speed -->
            <div class="engine-tile">
                <span class="engine-tile-label">SPEED</span>
                <div class="engine-tile-value">
                    <span class="speed-value" id="speedValueEngine">0</span>
                    <span class="engine-tile-unit">MPH</span>
                </div>
            </div>
            <!-- Top-right: RPM with tachometer -->
            <div class="engine-tile engine-tile-rpm">
                <div class="tachometer-container">
                    <svg class="tachometer" viewBox="0 0 200 120">
                        <path class="tach-bg" d="M20,100 A80,80 0 0,1 180,100" />
                        <path class="tach-warning-zone" d="M155,35 A80,80 0 0,1 180,100" />
                        <path class="tach-redline-zone" d="M170,60 A80,80 0 0,1 180,100" />
                        <path class="tach-active" id="tachArc" d="M20,100 A80,80 0 0,1 20,100" />
                        <line class="tach-needle" id="tachNeedle" x1="100" y1="100" x2="100" y2="25" />
                        <circle class="tach-center" cx="100" cy="100" r="8" />
                    </svg>
                    <div class="tach-value">
                        <span id="rpmValue">0</span>
                        <span class="tach-unit">RPM</span>
                    </div>
                    <div class="tach-redline-label">7500</div>
                </div>
            </div>
            <!-- Bottom-left: Gear -->
            <div class="engine-tile">
                <span class="engine-tile-label">GEAR</span>
                <div class="gear-indicator" id="gearIndicator">
                    <span class="gear-value" id="gearValue">N</span>
                </div>
            </div>
            <!-- Bottom-right: Coolant Temp -->
            <div class="engine-tile" id="coolantTile">
                <span class="engine-tile-label">COOLANT</span>
                <div class="engine-tile-value">
                    <span class="engine-tile-big" id="coolantTileValue">--</span>
                    <span class="engine-tile-unit">°F</span>
                </div>
                <div class="gauge-bar" style="margin-top:8px;"><div class="gauge-fill" id="coolantTileFill"></div></div>
            </div>
        </div>

        <!-- Telemetry Freshness Indicator -->
        <div class="telemetry-freshness" id="telemetryFreshness">
            <span class="freshness-dot"></span>
            <span class="freshness-text">CAN: <span id="canDataAge">--</span></span>
        </div>

        <!-- Engine Vitals Grid - 2 rows of 4 -->
        <div class="card">
            <div class="card-header">
                <h2>Engine Vitals</h2>
            </div>
            <div class="grid-4">
                <div class="gauge" id="coolantGauge">
                    <div class="label">Coolant</div>
                    <div class="value"><span id="coolantValue">--</span>°F</div>
                    <div class="gauge-bar"><div class="gauge-fill" id="coolantFill"></div></div>
                </div>
                <div class="gauge" id="oilPressGauge">
                    <div class="label">Oil PSI</div>
                    <div class="value"><span id="oilValue">--</span></div>
                    <div class="gauge-bar"><div class="gauge-fill" id="oilFill"></div></div>
                </div>
                <div class="gauge" id="oilTempGauge">
                    <div class="label">Oil Temp</div>
                    <div class="value"><span id="oilTempValue">--</span>°F</div>
                    <div class="gauge-bar"><div class="gauge-fill" id="oilTempFill"></div></div>
                </div>
                <div class="gauge" id="fuelPressGauge">
                    <div class="label">Fuel PSI</div>
                    <div class="value"><span id="fuelValue">0</span></div>
                    <div class="gauge-bar"><div class="gauge-fill" id="fuelFill"></div></div>
                </div>
                <div class="gauge" id="throttleGauge">
                    <div class="label">Throttle</div>
                    <div class="value"><span id="throttleValue">0</span>%</div>
                    <div class="gauge-bar"><div class="gauge-fill" id="throttleFill"></div></div>
                </div>
                <div class="gauge" id="intakeTempGauge">
                    <div class="label">IAT</div>
                    <div class="value"><span id="intakeTempValue">--</span>°F</div>
                    <div class="gauge-bar"><div class="gauge-fill" id="iatFill"></div></div>
                </div>
                <div class="gauge" id="boostGauge">
                    <div class="label">Boost</div>
                    <div class="value"><span id="boostValue">--</span> PSI</div>
                    <div class="gauge-bar"><div class="gauge-fill" id="boostFill"></div></div>
                </div>
                <div class="gauge" id="batteryGauge">
                    <div class="label">Battery</div>
                    <div class="value"><span id="batteryValue">--</span>V</div>
                    <div class="gauge-bar"><div class="gauge-fill" id="batteryFill"></div></div>
                </div>
            </div>
        </div>

        <!-- RPM & Throttle History Chart -->
        <div class="card">
            <div class="card-header">
                <h2>RPM & Throttle History</h2>
                <span class="chart-legend">
                    <span class="legend-item"><span class="legend-color rpm"></span>RPM</span>
                    <span class="legend-item"><span class="legend-color throttle"></span>Throttle</span>
                </span>
            </div>
            <div class="chart-container large">
                <canvas id="rpmChart"></canvas>
            </div>
        </div>

        <!-- Fuel Level -->
        <div class="card">
            <div class="card-header">
                <h2>Fuel Level</h2>
                <span id="fuelLevelPct">--</span>%
            </div>
            <div class="fuel-level-bar">
                <div class="fuel-level-fill" id="fuelLevelFill" style="width:100%"></div>
            </div>
            <div style="display:flex; justify-content:space-between; margin-top:8px; font-size:0.75rem; color:var(--text-muted);">
                <span>0%</span>
                <span id="fuelEstimate">Est. range: --</span>
                <span>100%</span>
            </div>
        </div>
    </div>

    <!-- Tab: Vehicle -->
    <div class="tab-content" id="tab-vehicle">
        <div class="big-display">
            <div class="value" id="speedValue">0</div>
            <div class="label">MPH</div>
        </div>

        <div class="card">
            <div class="card-header">
                <h2>Speed History</h2>
            </div>
            <div class="chart-container">
                <canvas id="speedChart"></canvas>
            </div>
        </div>

        <!-- NOTE: Suspension Travel card removed - not currently in use -->

        <div class="card">
            <div class="card-header">
                <h2>GPS Location</h2>
            </div>
            <div class="gps-display">
                <div class="gps-coords">
                    <span id="gpsLat">0.000000</span>, <span id="gpsLon">0.000000</span>
                </div>
                <div class="gps-meta">
                    <span><span id="gpsSats">0</span> sats</span>
                    <span><span id="gpsHdop">--</span> HDOP</span>
                    <span><span id="gpsAlt">--</span>m alt</span>
                </div>
            </div>
        </div>
    </div>

    <!-- Tab: Cameras -->
    <!-- Tab: Cameras - ENHANCED with live screenshots -->
    <div class="tab-content" id="tab-cameras">
        <!-- Stream Control Header -->
        <div class="card">
            <div class="card-header">
                <h2>Stream Control</h2>
                <div style="display:flex; gap:8px; align-items:center;">
                    <span id="streamStatusBadge" class="stream-status-badge idle">IDLE</span>
                    <button class="quick-note-btn" data-click="refreshAllScreenshots" id="refreshScreenshotsBtn">Refresh</button>
                </div>
            </div>
            <!-- Streaming Controls -->
            <div class="stream-controls" style="padding:12px 0; border-bottom:1px solid var(--bg-tertiary); margin-bottom:12px;">
                <div style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                    <button id="startStreamBtn" class="stream-action-btn start" data-click="startStream">
                        Start Stream
                    </button>
                    <button id="stopStreamBtn" class="stream-action-btn stop" data-click="stopStream" style="display:none;">
                        Stop Stream
                    </button>
                    <button id="switchStreamBtn" class="stream-action-btn" data-click="switchStream" style="display:none; background:var(--accent-blue, #3b82f6); color:#fff; padding:8px 16px; border-radius:6px; border:none; cursor:pointer; font-weight:600;">
                        Switch Camera
                    </button>
                    <!-- CAM-CONTRACT-0: Canonical 4-camera slots -->
                    <select id="streamCameraSelect" data-change-val="handleCameraSelectChange" style="padding:8px 12px; border-radius:6px; background:var(--bg-tertiary); color:var(--text-primary); border:none;">
                        <option value="main">Main Cam</option>
                        <option value="cockpit">Cockpit</option>
                        <option value="chase">Chase Cam</option>
                        <option value="suspension">Suspension</option>
                    </select>
                    <span id="streamError" style="color:var(--danger); font-size:0.8rem; display:none;"></span>
                    <span id="streamConfigWarning" style="color:var(--accent-yellow, #f0ad4e); font-size:0.8rem; display:none;">No YouTube stream key — configure in Settings</span>
                </div>
                <!-- STREAM-1: Prominent error banner with actionable guidance -->
                <div id="streamErrorBanner" class="stream-error-banner" style="display:none;">
                    <div style="display:flex; align-items:flex-start; gap:10px;">
                        <span style="font-size:1.1rem; line-height:1;">&#9888;</span>
                        <div style="flex:1;">
                            <strong id="streamErrorTitle">Stream failed</strong>
                            <div id="streamErrorMsg" style="margin-top:4px;"></div>
                            <div id="streamErrorAction" style="margin-top:6px;"></div>
                        </div>
                    </div>
                </div>
                <div id="streamInfo" style="margin-top:8px; font-size:0.8rem; color:var(--text-muted); display:none;">
                    <span>Active Camera: <strong id="activeStreamCamera">--</strong></span>
                    <span style="margin-left:12px;">Uptime: <strong id="streamUptime">--</strong></span>
                    <!-- EDGE-6: Restart counter -->
                    <span id="streamRestarts" style="margin-left:12px; color:var(--warning); display:none;">Restarts: --</span>
                </div>
            </div>
            <!-- STREAM-2: Stream Quality Control -->
            <div id="streamQualitySection" style="padding:12px 0; border-bottom:1px solid var(--bg-tertiary); margin-bottom:12px;">
                <div style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                    <span style="font-size:0.8rem; color:var(--text-muted); font-weight:600;">Stream Quality</span>
                    <select id="streamProfileSelect" data-change-val="handleProfileChange" style="padding:6px 10px; border-radius:6px; background:var(--bg-tertiary); color:var(--text-primary); border:none; font-size:0.85rem;">
                        <option value="1080p30">1080p (4500k)</option>
                        <option value="720p30">720p (2500k)</option>
                        <option value="480p30">480p (1200k)</option>
                        <option value="360p30">360p (800k)</option>
                    </select>
                    <label style="display:flex; align-items:center; gap:6px; font-size:0.8rem; color:var(--text-muted); cursor:pointer;">
                        <input type="checkbox" id="streamAutoToggle" data-change-bool="handleAutoToggle" style="accent-color:var(--accent); width:16px; height:16px; cursor:pointer;" />
                        Auto
                    </label>
                </div>
                <div id="streamQualityStatus" style="margin-top:6px; font-size:0.75rem; color:var(--text-muted); display:none;">
                    Applied: <strong id="streamQualityLabel">--</strong> &middot; <span id="streamQualityTime">--</span>
                </div>
            </div>
            <div class="status-bar" style="padding:8px 0; border:none; flex-wrap:wrap;">
                <div class="status-item">
                    <span class="status-dot" id="screenshotLoopStatus"></span>
                    <span>Auto-capture</span>
                </div>
                <div class="status-item" style="margin-left:auto;">
                    <span style="font-size:0.75rem; color:var(--text-muted);">Updates every 60s | Last: <span id="lastScreenshotTime">--</span></span>
                </div>
            </div>
        </div>

        <!-- CAM-CONTRACT-0: Camera Screenshots Grid - 2x2 layout with canonical 4 slots -->
        <div class="screenshot-grid">
            <!-- Main Cam (Primary Broadcast) -->
            <div class="screenshot-card" id="screenshot-main">
                <div class="screenshot-header">
                    <span class="screenshot-title">Main Cam</span>
                    <span class="screenshot-status-badge" id="main-badge">Offline</span>
                </div>
                <div class="screenshot-container" data-click="enlargeScreenshot" data-arg="main">
                    <img id="screenshot-img-main" src="" alt="Main Camera" class="screenshot-img" data-hide-error>
                    <div class="screenshot-placeholder" id="placeholder-main">
                        <div class="placeholder-icon">--</div>
                        <div class="placeholder-text">No Feed</div>
                    </div>
                    <div class="screenshot-overlay">
                        <span class="screenshot-live-badge" id="main-live-badge" style="display:none;">LIVE</span>
                    </div>
                </div>
                <div class="screenshot-footer">
                    <span class="screenshot-res" id="main-resolution">--</span>
                    <span class="screenshot-age" id="main-age">--</span>
                    <button class="screenshot-capture-btn" data-click="captureScreenshot" data-arg="main" title="Manual capture">Capture</button>
                </div>
            </div>

            <!-- Cockpit Cam (Driver POV) -->
            <div class="screenshot-card" id="screenshot-cockpit">
                <div class="screenshot-header">
                    <span class="screenshot-title">Cockpit</span>
                    <span class="screenshot-status-badge" id="cockpit-badge">Offline</span>
                </div>
                <div class="screenshot-container" data-click="enlargeScreenshot" data-arg="cockpit">
                    <img id="screenshot-img-cockpit" src="" alt="Cockpit Camera" class="screenshot-img" data-hide-error>
                    <div class="screenshot-placeholder" id="placeholder-cockpit">
                        <div class="placeholder-icon">--</div>
                        <div class="placeholder-text">No Feed</div>
                    </div>
                    <div class="screenshot-overlay">
                        <span class="screenshot-live-badge" id="cockpit-live-badge" style="display:none;">LIVE</span>
                    </div>
                </div>
                <div class="screenshot-footer">
                    <span class="screenshot-res" id="cockpit-resolution">--</span>
                    <span class="screenshot-age" id="cockpit-age">--</span>
                    <button class="screenshot-capture-btn" data-click="captureScreenshot" data-arg="cockpit" title="Manual capture">Capture</button>
                </div>
            </div>

            <!-- Chase Cam (Following View) -->
            <div class="screenshot-card" id="screenshot-chase">
                <div class="screenshot-header">
                    <span class="screenshot-title">Chase Cam</span>
                    <span class="screenshot-status-badge" id="chase-badge">Offline</span>
                </div>
                <div class="screenshot-container" data-click="enlargeScreenshot" data-arg="chase">
                    <img id="screenshot-img-chase" src="" alt="Chase Camera" class="screenshot-img" data-hide-error>
                    <div class="screenshot-placeholder" id="placeholder-chase">
                        <div class="placeholder-icon">--</div>
                        <div class="placeholder-text">No Feed</div>
                    </div>
                    <div class="screenshot-overlay">
                        <span class="screenshot-live-badge" id="chase-live-badge" style="display:none;">LIVE</span>
                    </div>
                </div>
                <div class="screenshot-footer">
                    <span class="screenshot-res" id="chase-resolution">--</span>
                    <span class="screenshot-age" id="chase-age">--</span>
                    <button class="screenshot-capture-btn" data-click="captureScreenshot" data-arg="chase" title="Manual capture">Capture</button>
                </div>
            </div>

            <!-- Suspension Cam -->
            <div class="screenshot-card" id="screenshot-suspension">
                <div class="screenshot-header">
                    <span class="screenshot-title">Suspension</span>
                    <span class="screenshot-status-badge" id="suspension-badge">Offline</span>
                </div>
                <div class="screenshot-container" data-click="enlargeScreenshot" data-arg="suspension">
                    <img id="screenshot-img-suspension" src="" alt="Suspension Camera" class="screenshot-img" data-hide-error>
                    <div class="screenshot-placeholder" id="placeholder-suspension">
                        <div class="placeholder-icon">--</div>
                        <div class="placeholder-text">No Feed</div>
                    </div>
                    <div class="screenshot-overlay">
                        <span class="screenshot-live-badge" id="suspension-live-badge" style="display:none;">LIVE</span>
                    </div>
                </div>
                <div class="screenshot-footer">
                    <span class="screenshot-res" id="suspension-resolution">--</span>
                    <span class="screenshot-age" id="suspension-age">--</span>
                    <button class="screenshot-capture-btn" data-click="captureScreenshot" data-arg="suspension" title="Manual capture">Capture</button>
                </div>
            </div>
        </div>

        <!-- Stream Info -->
        <div class="card">
            <div class="card-header">
                <h2>Stream Info</h2>
            </div>
            <div class="stream-info-grid">
                <div class="stream-info-item">
                    <span class="stream-label">YouTube URL</span>
                    <a href="#" id="youtubeUrl" target="_blank" class="stream-value link">Not configured</a>
                </div>
                <div class="stream-info-item">
                    <span class="stream-label">Bitrate</span>
                    <span class="stream-value" id="streamBitrate">--</span>
                </div>
                <div class="stream-info-item">
                    <span class="stream-label">FPS</span>
                    <span class="stream-value" id="streamFps">--</span>
                </div>
                <div class="stream-info-item">
                    <span class="stream-label">Encoding</span>
                    <span class="stream-value" id="streamEncoding">H.264</span>
                </div>
            </div>
        </div>
    </div>

    <!-- Screenshot Enlarged Modal -->
    <div id="screenshotModal" class="screenshot-modal" data-click="closeScreenshotModal">
        <div class="screenshot-modal-content" data-click-stop>
            <img id="screenshotModalImg" src="" alt="Enlarged Screenshot">
            <div class="screenshot-modal-info">
                <span id="screenshotModalTitle">Camera</span>
                <span id="screenshotModalTime">--</span>
            </div>
            <button class="screenshot-modal-close" data-click="closeScreenshotModal">X</button>
        </div>
    </div>

    <!-- Tab: Driver - ENHANCED with ANT+ Heart Rate Zones -->
    <div class="tab-content" id="tab-driver">
        <!-- ANT+ Device Status -->
        <div class="ant-status-card" id="antStatusCard">
            <span class="ant-status-icon" id="antIcon">--</span>
            <div class="ant-status-info">
                <div class="device-name" id="antDeviceName">ANT+ Heart Rate Monitor</div>
                <div class="device-id" id="antDeviceId">Searching...</div>
            </div>
            <div class="ant-battery" id="antBattery">
                <span></span>
                <span id="antBatteryPct">--%</span>
            </div>
        </div>

        <!-- Hero Heart Rate Display -->
        <div class="hr-hero-display" id="hrHeroDisplay">
            <div class="hr-value-large" id="hrValueLarge">--</div>
            <div class="hr-label">BPM</div>
            <div class="hr-zone-name" id="hrZoneName">NO SIGNAL</div>
        </div>

        <!-- HR Zone Bar -->
        <div class="card">
            <div class="hr-zone-bar" id="hrZoneBar">
                <div class="zone-segment rest"></div>
                <div class="zone-segment warmup"></div>
                <div class="zone-segment fatburn"></div>
                <div class="zone-segment cardio"></div>
                <div class="zone-segment peak"></div>
                <div class="zone-segment max">
                    <div class="hr-zone-marker" id="hrZoneMarker" style="left:0%"></div>
                </div>
            </div>
            <div class="hr-zone-labels">
                <span>Rest</span>
                <span>Warm Up</span>
                <span>Fat Burn</span>
                <span>Cardio</span>
                <span>Peak</span>
                <span>Max</span>
            </div>
        </div>

        <!-- HR Stats -->
        <div class="hr-stats-grid">
            <div class="hr-stat-card peak">
                <div class="hr-stat-value" id="hrPeak">--</div>
                <div class="hr-stat-label">Peak HR</div>
            </div>
            <div class="hr-stat-card avg">
                <div class="hr-stat-value" id="hrAvg">--</div>
                <div class="hr-stat-label">Avg HR</div>
            </div>
            <div class="hr-stat-card">
                <div class="hr-stat-value" id="driverTime">--:--</div>
                <div class="hr-stat-label">Drive Time</div>
            </div>
        </div>

        <!-- Heart Rate History Chart -->
        <div class="card">
            <div class="card-header">
                <h2>Heart Rate History</h2>
                <span style="font-size:0.75rem;color:var(--text-muted);">Last 2 minutes</span>
            </div>
            <div class="chart-container">
                <canvas id="heartChart"></canvas>
            </div>
        </div>

        <!-- Time in Zone -->
        <div class="card">
            <div class="card-header">
                <h2>Time in Zone</h2>
            </div>
            <div class="zone-time-grid">
                <div class="zone-time-item">
                    <span class="zone-dot rest"></span>
                    <span class="zone-name">Rest</span>
                    <div class="zone-duration" id="zoneTimeRest">0:00</div>
                </div>
                <div class="zone-time-item">
                    <span class="zone-dot warmup"></span>
                    <span class="zone-name">Warm Up</span>
                    <div class="zone-duration" id="zoneTimeWarmup">0:00</div>
                </div>
                <div class="zone-time-item">
                    <span class="zone-dot fatburn"></span>
                    <span class="zone-name">Fat Burn</span>
                    <div class="zone-duration" id="zoneTimeFatburn">0:00</div>
                </div>
                <div class="zone-time-item">
                    <span class="zone-dot cardio"></span>
                    <span class="zone-name">Cardio</span>
                    <div class="zone-duration" id="zoneTimeCardio">0:00</div>
                </div>
                <div class="zone-time-item">
                    <span class="zone-dot peak"></span>
                    <span class="zone-name">Peak</span>
                    <div class="zone-duration" id="zoneTimePeak">0:00</div>
                </div>
                <div class="zone-time-item">
                    <span class="zone-dot max"></span>
                    <span class="zone-name">Max</span>
                    <div class="zone-duration" id="zoneTimeMax">0:00</div>
                </div>
            </div>
        </div>

        <!-- Zone Reference Card -->
        <div class="card">
            <div class="card-header">
                <h2>Zone Reference</h2>
                <span style="font-size:0.7rem;color:var(--text-muted);">Based on 185 max HR</span>
            </div>
            <div style="font-size:0.8rem; color:var(--text-secondary); line-height:1.8;">
                <div><span style="color:#64748b">●</span> <b>Rest:</b> &lt;93 BPM (50%)</div>
                <div><span style="color:#3b82f6">●</span> <b>Warm Up:</b> 93-111 BPM (50-60%)</div>
                <div><span style="color:#22c55e">●</span> <b>Fat Burn:</b> 111-130 BPM (60-70%)</div>
                <div><span style="color:#f59e0b">●</span> <b>Cardio:</b> 130-148 BPM (70-80%)</div>
                <div><span style="color:#ef4444">●</span> <b>Peak:</b> 148-167 BPM (80-90%)</div>
                <div><span style="color:#a855f7">●</span> <b>Max:</b> &gt;167 BPM (90%+)</div>
            </div>
        </div>
    </div>

    <!-- Tab: Comms -->
    <div class="tab-content" id="tab-comms">
        <div class="card">
            <div class="card-header">
                <h2>Intercom Audio Level</h2>
            </div>
            <div class="audio-panel">
                <div class="audio-level-bar">
                    <div class="audio-level-fill" id="audioLevel" style="width:0%"></div>
                    <div class="audio-level-markers">
                        <span>0</span><span>-20dB</span><span>-10dB</span><span>0dB</span>
                    </div>
                </div>
                <div class="last-heard">
                    Last heard from driver: <span id="lastHeard">--</span>
                </div>
            </div>
        </div>

        <div class="card">
            <div class="card-header">
                <h2>Quick Pit Notes</h2>
                <!-- PIT-COMMS-1: Sync status indicator -->
                <div id="pitNotesSyncStatus" style="font-size:0.75rem; color:var(--text-muted); margin-top:4px;">
                    <span id="pitNotesCloudStatus">Cloud: --</span>
                    <span style="margin-left:12px;" id="pitNotesQueueCount">Queued: 0</span>
                </div>
            </div>
            <div class="pit-notes">
                <textarea class="pit-notes-input" id="pitNoteInput" rows="2" placeholder="Type a note to send to race control..."></textarea>
                <div class="pit-notes-btns">
                    <button class="quick-note-btn" data-click="sendQuickNote" data-arg="PIT IN">PIT IN</button>
                    <button class="quick-note-btn" data-click="sendQuickNote" data-arg="PIT OUT">PIT OUT</button>
                    <button class="quick-note-btn" data-click="sendQuickNote" data-arg="CHANGING TIRES">TIRES</button>
                    <button class="quick-note-btn" data-click="sendQuickNote" data-arg="REFUELING">FUEL</button>
                    <button class="quick-note-btn danger" data-click="sendQuickNote" data-arg="MECHANICAL ISSUE">MECHANICAL</button>
                    <button class="quick-note-btn danger" data-click="sendQuickNote" data-arg="DRIVER CONCERN">DRIVER</button>
                </div>
                <button class="send-note-btn" data-click="sendPitNote">Send Note to Race Control</button>
                <div class="pit-notes-history">
                    <div class="pit-notes-history-header">Recent Notes:</div>
                    <div id="pitNotesHistory"><div class="pit-note-empty">Loading...</div></div>
                </div>
            </div>
        </div>

        <div class="card">
            <div class="card-header">
                <h2>Connection Status</h2>
            </div>
            <div class="grid-2">
                <div class="gauge" id="queueGauge">
                    <div class="label">Queue Depth</div>
                    <div class="value"><span id="queueDepth">0</span></div>
                </div>
                <div class="gauge">
                    <div class="label">Last Sync</div>
                    <div class="value" style="font-size:1rem;"><span id="lastSync">--</span></div>
                </div>
            </div>
        </div>
    </div>

    <!-- Tab: Race (P1 Features) -->
    <div class="tab-content" id="tab-race">
        <!-- Race Position Display -->
        <div class="big-display" id="positionDisplay">
            <div class="value" style="font-size:3.5rem;">P<span id="racePosition">--</span></div>
            <div class="label">of <span id="totalVehicles">--</span> vehicles</div>
            <div class="sub-value" id="deltaToLeader">
                <span id="deltaValue">--</span> behind leader
            </div>
            <div class="sub-value" id="milesRemainingDisplay" style="margin-top:6px; font-size:1.1rem; color:var(--accent);">
                <span id="milesRemainingValue">—</span>
            </div>
        </div>

        <div class="grid-2">
            <!-- Lap Counter -->
            <div class="card">
                <div class="card-header">
                    <h2>Lap Progress</h2>
                </div>
                <div class="gauge" style="padding:20px; text-align:center;">
                    <div class="value" style="font-size:3rem;"><span id="lapNumber">0</span></div>
                    <div class="label">Current Lap</div>
                    <div style="margin-top:10px; color:var(--text-secondary);">
                        Checkpoint: <span id="lastCheckpoint">--</span>
                    </div>
                </div>
            </div>

            <!-- Fuel Strategy Card -->
            <div class="card">
                <div class="card-header">
                    <h2>Fuel Strategy</h2>
                    <button class="quick-note-btn" data-click="toggleFuelConfig" style="padding:4px 8px; font-size:0.8rem;">Config</button>
                </div>
                <div id="fuelPanel">
                    <!-- Fuel Level Bar (only shown when fuel is set) -->
                    <div class="fuel-level-bar" id="fuelLevelBar" style="display:none;">
                        <div class="fuel-level-fill" id="fuelLevelFill" style="width:0%;"></div>
                    </div>

                    <!-- Fuel Not Set Warning -->
                    <div id="fuelUnsetWarning" style="padding:15px; text-align:center; background:var(--warning-bg, rgba(255,193,7,0.1)); border-radius:8px; margin-bottom:10px;">
                        <div style="font-size:1.5rem; margin-bottom:8px;">!</div>
                        <div style="color:var(--warning-color, #ffc107); font-weight:bold;">Fuel Not Set</div>
                        <div style="font-size:0.85rem; color:var(--text-muted); margin-top:4px;">Tap below to set current fuel level</div>
                    </div>

                    <div class="grid-2" style="margin-top:10px;">
                        <div class="gauge" style="cursor:pointer;" data-click="promptFuelLevel">
                            <div class="label">Remaining <span style="font-size:0.7rem; opacity:0.6;">(tap to edit)</span></div>
                            <div class="value">
                                <span id="fuelRemaining" style="border-bottom:1px dashed var(--text-muted);">--</span>
                                <span id="fuelUnit"> gal</span>
                            </div>
                        </div>
                        <div class="gauge">
                            <div class="label" id="fuelRemainingLabel">Est. Miles Left</div>
                            <div class="value"><span id="fuelLapsRemaining">--</span></div>
                        </div>
                    </div>

                    <!-- Tank Configuration (hidden by default) -->
                    <div id="fuelConfigPanel" style="display:none; margin-top:10px; padding:10px; background:var(--bg-secondary, #1a1a2e); border-radius:8px;">
                        <div class="grid-2" style="gap:10px;">
                            <div>
                                <label style="font-size:0.8rem; color:var(--text-muted);">Tank Capacity (gal)</label>
                                <input type="number" id="tankCapacityInput" value="" min="1" max="250" step="0.5" placeholder="95"
                                    style="width:100%; padding:8px; margin-top:4px; border-radius:4px; background:var(--card-bg); color:var(--text-color); border:1px solid var(--border-color);">
                            </div>
                            <div>
                                <label style="font-size:0.8rem; color:var(--text-muted);">Est. MPG</label>
                                <input type="number" id="fuelMpgInput" value="2.0" min="0.1" max="30" step="0.1"
                                    style="width:100%; padding:8px; margin-top:4px; border-radius:4px; background:var(--card-bg); color:var(--text-color); border:1px solid var(--border-color);">
                            </div>
                        </div>
                        <button class="quick-note-btn" data-click="saveFuelConfig" style="width:100%; margin-top:10px;">
                            Save Configuration
                        </button>
                    </div>

                    <div style="margin-top:10px; display:flex; gap:8px;">
                        <button class="quick-note-btn" data-click="recordFuelFill" style="flex:1;">
                            TANK FILLED
                        </button>
                    </div>

                    <!-- PIT-1R: Range & Trip Miles -->
                    <div id="rangePanel" style="margin-top:12px; padding:10px; background:var(--bg-secondary, #1a1a2e); border-radius:8px;">
                        <div style="font-size:0.8rem; font-weight:bold; color:var(--text-muted); margin-bottom:8px; text-transform:uppercase; letter-spacing:0.5px;">Range & Trip</div>
                        <div class="grid-2" style="gap:8px;">
                            <div class="gauge">
                                <div class="label">MPG Avg</div>
                                <div class="value"><span id="rangeMpgAvg">--</span></div>
                            </div>
                            <div class="gauge">
                                <div class="label">Fuel Remaining</div>
                                <div class="value"><span id="rangeFuelRemaining">--</span> <span style="font-size:0.7rem;">gal</span></div>
                            </div>
                            <div class="gauge">
                                <div class="label">Est. Range</div>
                                <div class="value"><span id="rangeEstRemaining">--</span> <span style="font-size:0.7rem;">mi</span></div>
                            </div>
                            <div class="gauge">
                                <div class="label">Trip Miles</div>
                                <div class="value"><span id="tripMilesValue">--</span> <span style="font-size:0.7rem;">mi</span></div>
                            </div>
                        </div>
                        <div style="margin-top:6px; font-size:0.75rem; color:var(--text-muted);">
                            Trip since: <span id="tripStartTime">--</span>
                        </div>
                        <button class="quick-note-btn" data-click="resetTripMiles" style="width:100%; margin-top:8px; font-size:0.8rem;">
                            Reset Trip Miles
                        </button>
                    </div>
                </div>
            </div>
        </div>

        <!-- Tire Tracking Card (PIT-5R: Front/Rear Independent) -->
        <div class="card">
            <div class="card-header">
                <h2>Tire Tracking</h2>
                <select id="tireBrandSelect" data-change-val="updateTireBrand" style="padding:6px 10px; border-radius:6px; background:var(--bg-tertiary); color:var(--text-primary); border:none; font-size:0.85rem;">
                    <option value="Toyo">Toyo</option>
                    <option value="BFG">BFG</option>
                    <option value="Maxxis">Maxxis</option>
                    <option value="Other">Other</option>
                </select>
            </div>
            <div id="tirePanel">
                <!-- Front Axle -->
                <div class="tire-axle-row" id="tireFrontRow">
                    <div class="tire-axle-label">FRONT</div>
                    <div class="tire-axle-info">
                        <span class="tire-brand-display" id="tireFrontBrand">Toyo</span>
                        <span class="tire-miles-display"><span id="tireFrontMiles">0.0</span> mi</span>
                        <span class="tire-changed-display">Changed: <span id="tireFrontChanged">--</span></span>
                    </div>
                    <button class="quick-note-btn tire-reset-btn" id="tireFrontResetBtn" data-click="resetTireAxle" data-arg="front">Reset Front</button>
                </div>
                <!-- Rear Axle -->
                <div class="tire-axle-row" id="tireRearRow">
                    <div class="tire-axle-label">REAR</div>
                    <div class="tire-axle-info">
                        <span class="tire-brand-display" id="tireRearBrand">Toyo</span>
                        <span class="tire-miles-display"><span id="tireRearMiles">0.0</span> mi</span>
                        <span class="tire-changed-display">Changed: <span id="tireRearChanged">--</span></span>
                    </div>
                    <button class="quick-note-btn tire-reset-btn" id="tireRearResetBtn" data-click="resetTireAxle" data-arg="rear">Reset Rear</button>
                </div>
            </div>
        </div>

        <!-- Pit Stop Readiness -->
        <div class="card">
            <div class="card-header">
                <h2>Pit Readiness Checklist</h2>
            </div>
            <div class="pit-checklist">
                <label class="checklist-item">
                    <input type="checkbox" id="chkFuel"> Fuel ready
                </label>
                <label class="checklist-item">
                    <input type="checkbox" id="chkTires"> Tires staged
                </label>
                <label class="checklist-item">
                    <input type="checkbox" id="chkTools"> Tools in position
                </label>
                <label class="checklist-item">
                    <input type="checkbox" id="chkCrew"> Crew briefed
                </label>
            </div>
        </div>

        <!-- P2: Weather Panel -->
        <div class="card">
            <div class="card-header">
                <h2>Weather Conditions</h2>
            </div>
            <div class="grid-3">
                <div class="gauge">
                    <div class="label">Temperature</div>
                    <div class="value"><span id="weatherTemp">--</span>°F</div>
                </div>
                <div class="gauge">
                    <div class="label">Wind</div>
                    <div class="value"><span id="weatherWind">--</span> mph</div>
                </div>
                <div class="gauge">
                    <div class="label">Conditions</div>
                    <div class="value" style="font-size:1rem;"><span id="weatherCond">--</span></div>
                </div>
            </div>
            <div style="margin-top:8px; color:var(--text-secondary); font-size:0.75rem;">
                Last updated: <span id="weatherUpdated">--</span>
            </div>
        </div>

        <!-- P2: Pit Stop Timer -->
        <div class="card">
            <div class="card-header">
                <h2>Pit Stop Timer</h2>
            </div>
            <div class="pit-timer-panel">
                <div class="pit-timer-display" id="pitTimerDisplay">00:00.0</div>
                <div class="pit-timer-btns">
                    <button class="timer-btn start" data-click="startPitTimer" id="pitTimerStart">START</button>
                    <button class="timer-btn stop" data-click="stopPitTimer" id="pitTimerStop" disabled>STOP</button>
                    <button class="timer-btn reset" data-click="resetPitTimer">RESET</button>
                </div>
                <div class="pit-timer-history">
                    <div class="timer-history-title">Recent Pit Stops:</div>
                    <div id="pitTimerHistory">No pit stops recorded</div>
                </div>
            </div>
        </div>

        <!-- P2: Nearby Competitors -->
        <div class="card">
            <div class="card-header">
                <h2>Nearby Competitors</h2>
            </div>
            <div id="competitorsPanel" class="competitors-list">
                <div class="competitor-item loading">Loading competitor data...</div>
            </div>
        </div>
    </div>

    <!-- Tab: Course (GPX Map - Feature 4) -->
    <div class="tab-content" id="tab-course">
        <!-- Course Info (shown when GPX loaded) -->
        <div class="course-loaded-info" id="courseLoadedInfo" style="display:none;">
            <span class="course-loaded-icon"></span>
            <div class="course-loaded-details">
                <div class="course-loaded-name" id="courseFileName">course.gpx</div>
                <div class="course-loaded-meta" id="courseMeta">-- mi • -- waypoints</div>
            </div>
            <button class="course-clear-btn" data-click="clearCourse">X Clear</button>
        </div>

        <!-- Course Progress Bar -->
        <div class="card" id="courseProgressCard" style="display:none;">
            <div class="card-header">
                <h2>Course Progress</h2>
                <div style="display:flex; align-items:center; gap:8px;">
                    <select id="raceTypeSelect" data-change-val="setRaceType" style="padding:4px 8px; border-radius:4px; background:var(--card-bg); color:var(--text-color); border:1px solid var(--border-color);">
                        <option value="point_to_point">Point-to-Point</option>
                        <option value="lap_based">Lap Race</option>
                    </select>
                    <div id="lapCountDiv" style="display:none; align-items:center; gap:4px;">
                        <input type="number" id="lapCountInput" value="1" min="1" max="99" data-change-val="setTotalLaps" style="width:40px; padding:4px; border-radius:4px; background:var(--card-bg); color:var(--text-color); border:1px solid var(--border-color); text-align:center;">
                        <span style="font-size:0.8rem;">laps</span>
                    </div>
                    <span id="courseProgressPct">0%</span>
                </div>
            </div>
            <div class="course-progress-bar">
                <div class="course-progress-fill" id="courseProgressFill" style="width:0%"></div>
            </div>
            <div class="course-stats-grid">
                <div class="course-stat">
                    <div class="course-stat-value" id="courseDistanceDone">0.0</div>
                    <div class="course-stat-label" id="courseDistanceDoneLabel">mi Done</div>
                </div>
                <div class="course-stat">
                    <div class="course-stat-value" id="courseDistanceLeft">--</div>
                    <div class="course-stat-label" id="courseDistanceLeftLabel">mi Left</div>
                </div>
                <div class="course-stat">
                    <div class="course-stat-value" id="courseETA">--:--</div>
                    <div class="course-stat-label">ETA</div>
                </div>
                <div class="course-stat">
                    <div class="course-stat-value" id="courseNextWaypoint">--</div>
                    <div class="course-stat-label">Next WP</div>
                </div>
            </div>
        </div>

        <!-- Course Map -->
        <div class="card">
            <div class="card-header">
                <h2>Course Map</h2>
                <button class="quick-note-btn" data-click="centerOnVehicle" id="centerVehicleBtn">
                    Center
                </button>
            </div>
            <div class="course-map-container" id="courseMapContainer">
                <div id="courseMap"></div>
                <div class="map-placeholder" id="mapPlaceholder">
                    <div class="map-placeholder-icon">--</div>
                    <div>No course loaded</div>
                    <div style="font-size:0.8rem;color:var(--text-muted);margin-top:8px;">
                        Upload a GPX file to see the course
                    </div>
                </div>
            </div>
        </div>

        <!-- GPX Upload Zone -->
        <div class="gpx-upload-zone" id="gpxUploadZone" data-click="triggerGpxUpload">
            <div class="gpx-upload-icon">Upload</div>
            <div class="gpx-upload-text">Drop GPX file here or click to upload</div>
            <div class="gpx-upload-hint">Supports .gpx files from Strava, Garmin, etc.</div>
            <input type="file" id="gpxFileInput" accept=".gpx" data-change-event="handleGPXUpload">
        </div>

        <!-- Current Position Display -->
        <div class="card">
            <div class="card-header">
                <h2>Current Position</h2>
                <button class="quick-note-btn" data-click="toggleGpsTestMode" id="gpsTestModeBtn" style="padding:4px 8px; font-size:0.75rem;">
                    Test
                </button>
            </div>
            <!-- GPS Stale Warning -->
            <div id="gpsStaleWarning" class="gps-stale-warning" style="display:none;">
                GPS STALE
            </div>
            <!-- GPS Test Mode Indicator -->
            <div id="gpsTestModeIndicator" class="gps-test-mode-indicator" style="display:none;">
                TEST MODE - Simulated GPS
            </div>
            <div class="gps-display">
                <div class="gps-coords">
                    <span id="courseGpsLat">0.000000</span>, <span id="courseGpsLon">0.000000</span>
                </div>
                <div class="gps-meta">
                    <span><span id="courseGpsSats">0</span> sats</span>
                    <span><span id="courseHeading">--</span>°</span>
                    <span><span id="courseGpsAccuracy">--</span>m accuracy</span>
                </div>
            </div>
        </div>
    </div>

    <!-- Tab: Team — TEAM-3: Migrated from cloud TeamDashboard -->
    <div class="tab-content" id="tab-team">
        <!-- Fan Visibility Toggle -->
        <div class="card">
            <div class="card-header">
                <h2>Fan Visibility</h2>
                <span class="badge" id="visibilityBadge" style="background: var(--success); color: #000;">Visible</span>
            </div>
            <p style="color: var(--text-muted); font-size: 0.85rem; margin-bottom: 12px;">
                Control whether fans can see your vehicle on the live dashboard. When hidden, your position, telemetry, and video are not shown to public viewers.
            </p>
            <div style="display: flex; gap: 8px;">
                <button class="btn vis-btn vis-on" id="btnVisibilityOn" data-click="setFanVisibility" data-arg="true" style="flex: 1;">
                    Visible to Fans
                </button>
                <button class="btn vis-btn" id="btnVisibilityOff" data-click="setFanVisibility" data-arg="false" style="flex: 1;">
                    Hidden from Fans
                </button>
            </div>
            <div id="visibilitySyncStatus" style="margin-top: 8px; font-size: 0.8rem; color: var(--text-muted);"></div>
        </div>

        <!-- Telemetry Sharing Policy -->
        <div class="card">
            <div class="card-header">
                <h2>Telemetry Sharing</h2>
            </div>
            <p style="color: var(--text-muted); font-size: 0.85rem; margin-bottom: 12px;">
                Choose which telemetry fields production and fans can see. Fans only see a subset of what production sees.
            </p>

            <!-- Presets -->
            <div style="display: flex; gap: 6px; margin-bottom: 12px; flex-wrap: wrap;">
                <button class="btn btn-secondary" data-click="applyPreset" data-arg="none" style="font-size: 0.8rem; padding: 6px 12px;">None</button>
                <button class="btn btn-secondary" data-click="applyPreset" data-arg="gps" style="font-size: 0.8rem; padding: 6px 12px;">GPS Only</button>
                <button class="btn btn-secondary" data-click="applyPreset" data-arg="basic" style="font-size: 0.8rem; padding: 6px 12px;">Basic</button>
                <button class="btn btn-secondary" data-click="applyPreset" data-arg="full" style="font-size: 0.8rem; padding: 6px 12px;">Full</button>
            </div>

            <!-- Field groups -->
            <div id="sharingFieldGroups">
                <div class="card" style="background: var(--bg-secondary); padding: 10px; margin-bottom: 8px;">
                    <h3 style="font-size: 0.85rem; margin: 0 0 8px 0; color: var(--text-secondary);">GPS</h3>
                    <div id="sharing-gps" style="display: flex; flex-wrap: wrap; gap: 6px;"></div>
                </div>
                <div class="card" style="background: var(--bg-secondary); padding: 10px; margin-bottom: 8px;">
                    <h3 style="font-size: 0.85rem; margin: 0 0 8px 0; color: var(--text-secondary);">Engine Basic</h3>
                    <div id="sharing-engine_basic" style="display: flex; flex-wrap: wrap; gap: 6px;"></div>
                </div>
                <div class="card" style="background: var(--bg-secondary); padding: 10px; margin-bottom: 8px;">
                    <h3 style="font-size: 0.85rem; margin: 0 0 8px 0; color: var(--text-secondary);">Engine Advanced</h3>
                    <div id="sharing-engine_advanced" style="display: flex; flex-wrap: wrap; gap: 6px;"></div>
                </div>
                <div class="card" style="background: var(--bg-secondary); padding: 10px; margin-bottom: 8px;">
                    <h3 style="font-size: 0.85rem; margin: 0 0 8px 0; color: var(--text-secondary);">Biometrics</h3>
                    <div id="sharing-biometrics" style="display: flex; flex-wrap: wrap; gap: 6px;"></div>
                </div>
            </div>

            <button class="btn" data-click="saveSharingPolicy" style="width: 100%; margin-top: 8px;">
                Save & Sync to Cloud
            </button>
            <div id="sharingSyncStatus" style="margin-top: 8px; font-size: 0.8rem; color: var(--text-muted);"></div>
        </div>
    </div>

    <!-- Tab: Devices (Hardware Configuration) -->
    <div class="tab-content" id="tab-devices">
        <div class="card">
            <div class="card-header">
                <h2>Device Scanner</h2>
                <button class="quick-note-btn" data-click="scanDevices" id="scanDevicesBtn">
                    Scan Devices
                </button>
            </div>
            <div id="deviceScanStatus" style="color:var(--text-secondary); font-size:0.85rem; margin-bottom:12px;">
                Click "Scan Devices" to detect connected hardware
            </div>
        </div>

        <!-- USB Cameras -->
        <div class="card">
            <div class="card-header">
                <h2>USB Cameras</h2>
            </div>
            <div id="cameraDevicesPanel">
                <div class="device-list" id="cameraDevicesList">
                    <div class="device-item loading">Scan to detect cameras...</div>
                </div>
            </div>
            <div class="device-mapping-section" style="margin-top:16px; padding-top:16px; border-top:1px solid var(--bg-tertiary);">
                <h3 style="font-size:0.85rem; color:var(--text-secondary); margin-bottom:12px;">Camera Assignments</h3>
                <!-- CAM-CONTRACT-1B: Canonical 4-camera slot mapping -->
                <div class="camera-mapping-grid">
                    <div class="mapping-item">
                        <label>Main</label>
                        <select id="mappingMain" data-change-val="updateCameraMapping" data-arg="main">
                            <option value="">-- Not assigned --</option>
                        </select>
                    </div>
                    <div class="mapping-item">
                        <label>Cockpit</label>
                        <select id="mappingCockpit" data-change-val="updateCameraMapping" data-arg="cockpit">
                            <option value="">-- Not assigned --</option>
                        </select>
                    </div>
                    <div class="mapping-item">
                        <label>Chase</label>
                        <select id="mappingChase" data-change-val="updateCameraMapping" data-arg="chase">
                            <option value="">-- Not assigned --</option>
                        </select>
                    </div>
                    <div class="mapping-item">
                        <label>Suspension</label>
                        <select id="mappingSuspension" data-change-val="updateCameraMapping" data-arg="suspension">
                            <option value="">-- Not assigned --</option>
                        </select>
                    </div>
                </div>
                <button class="send-note-btn" style="margin-top:12px;" data-click="saveCameraMappings">
                    Save Camera Assignments
                </button>
            </div>
        </div>

        <!-- GPS Device -->
        <div class="card">
            <div class="card-header">
                <h2>GPS Device</h2>
                <span class="device-status-badge" id="gpsDeviceStatus">Unknown</span>
            </div>
            <div id="gpsDevicePanel">
                <div class="device-info-grid">
                    <div class="device-info-item">
                        <span class="info-label">Device</span>
                        <span class="info-value" id="gpsDevicePath">--</span>
                    </div>
                    <div class="device-info-item">
                        <span class="info-label">Type</span>
                        <span class="info-value" id="gpsDeviceType">--</span>
                    </div>
                    <div class="device-info-item">
                        <span class="info-label">Baud Rate</span>
                        <span class="info-value" id="gpsDeviceBaud">--</span>
                    </div>
                    <div class="device-info-item">
                        <span class="info-label">Satellites</span>
                        <span class="info-value" id="gpsDeviceSats">--</span>
                    </div>
                </div>
                <div class="device-config-row" style="margin-top:12px;">
                    <label style="font-size:0.8rem; color:var(--text-secondary);">GPS Serial Port:</label>
                    <select id="gpsPortSelect" style="flex:1;" data-change-call="updateGpsConfig">
                        <option value="">-- Auto-detect --</option>
                    </select>
                </div>
            </div>
        </div>

        <!-- ANT+ Device -->
        <div class="card">
            <div class="card-header">
                <h2>ANT+ USB Stick</h2>
                <span class="device-status-badge" id="antDeviceStatus">Unknown</span>
            </div>
            <div id="antDevicePanel">
                <div class="device-info-grid">
                    <div class="device-info-item">
                        <span class="info-label">USB Device</span>
                        <span class="info-value" id="antDevicePath">--</span>
                    </div>
                    <div class="device-info-item">
                        <span class="info-label">Product</span>
                        <span class="info-value" id="antDeviceProduct">--</span>
                    </div>
                    <div class="device-info-item">
                        <span class="info-label">Status</span>
                        <span class="info-value" id="antServiceStatus">--</span>
                    </div>
                    <div class="device-info-item">
                        <span class="info-label">Heart Rate</span>
                        <span class="info-value" id="antCurrentHR">-- BPM</span>
                    </div>
                </div>
                <div style="margin-top:12px; display:flex; gap:8px;">
                    <button class="quick-note-btn" data-click="pairAntDevice">Pair Device</button>
                    <button class="quick-note-btn" data-click="restartAntService">Restart Service</button>
                </div>
            </div>
        </div>

        <!-- CAN Bus Interface -->
        <div class="card">
            <div class="card-header">
                <h2>CAN Bus Interface</h2>
                <span class="device-status-badge" id="canDeviceStatus">Unknown</span>
            </div>
            <div id="canDevicePanel">
                <div class="device-info-grid">
                    <div class="device-info-item">
                        <span class="info-label">Interface</span>
                        <span class="info-value" id="canInterface">--</span>
                    </div>
                    <div class="device-info-item">
                        <span class="info-label">Bitrate</span>
                        <span class="info-value" id="canBitrate">--</span>
                    </div>
                    <div class="device-info-item">
                        <span class="info-label">RX Count</span>
                        <span class="info-value" id="canRxCount">--</span>
                    </div>
                    <div class="device-info-item">
                        <span class="info-label">Errors</span>
                        <span class="info-value" id="canErrors">--</span>
                    </div>
                </div>
            </div>
        </div>

        <!-- All USB Devices (Debug) -->
        <div class="card">
            <div class="card-header">
                <h2>All USB Devices</h2>
                <button class="quick-note-btn" data-click="toggleUsbList">Toggle List</button>
            </div>
            <div id="allUsbDevicesPanel" style="display:none;">
                <div class="device-list" id="allUsbDevicesList">
                    <div class="device-item loading">Scan to show all USB devices...</div>
                </div>
            </div>
        </div>

        <!-- Service Status — PIT-SVC-2: Unified status model -->
        <div class="card">
            <div class="card-header">
                <h2>Service Status</h2>
            </div>
            <div class="service-status-grid" id="serviceStatusGrid">
                <div class="service-item">
                    <div><span class="service-name">argus-gps</span><div class="service-detail" id="svcGpsDetail"></div></div>
                    <span class="service-status" id="svcGps">--</span>
                </div>
                <div class="service-item">
                    <div><span class="service-name">argus-can</span><div class="service-detail" id="svcCanDetail"></div></div>
                    <span class="service-status" id="svcCan">--</span>
                </div>
                <div class="service-item">
                    <div><span class="service-name">argus-ant</span><div class="service-detail" id="svcAntDetail"></div></div>
                    <span class="service-status" id="svcAnt">--</span>
                </div>
                <div class="service-item">
                    <div><span class="service-name">argus-uplink</span><div class="service-detail" id="svcUplinkDetail"></div></div>
                    <span class="service-status" id="svcUplink">--</span>
                </div>
                <div class="service-item">
                    <div><span class="service-name">argus-video</span><div class="service-detail" id="svcVideoDetail"></div></div>
                    <span class="service-status" id="svcVideo">--</span>
                </div>
                <div class="service-item">
                    <div><span class="service-name">Cloudflare Tunnel</span><div class="service-detail" id="svcCloudflaredDetail"></div></div>
                    <span class="service-status" id="svcCloudflared">--</span>
                </div>
            </div>
            <div id="tunnelUrlRow" style="display:none; padding: 8px 12px; margin-top: 4px; background: var(--bg-tertiary); border-radius: 6px; font-size: 0.8rem;">
                <span style="color: var(--text-muted);">Tunnel URL:</span>
                <a id="tunnelUrlLink" href="#" target="_blank" rel="noopener" style="color: var(--primary); margin-left: 6px;"></a>
            </div>
            <button class="send-note-btn" style="margin-top:12px;" data-click="restartAllServices">
                Restart All Services
            </button>
        </div>
    </div>

    <script nonce="__CSP_NONCE__">
        // ============ State ============
        let currentTab = 'engine';
        let alertActive = false;
        let alertTimeout = null;
        // CAM-CONTRACT-1B: Canonical 4-camera slots
        let cameraStatus = { main: 'offline', cockpit: 'offline', chase: 'offline', suspension: 'offline' };
        let currentCamera = 'main';
        let heartRateHistory = [];
        let driveStartTime = Date.now();

        // ============ Heart Rate Zone Tracking (Feature 3) ============
        const HR_MAX = 185;  // Default max HR, could be configurable
        const HR_ZONES = {
            rest:    { min: 0,   max: 0.50, name: 'REST',     class: 'zone-rest' },
            warmup:  { min: 0.50, max: 0.60, name: 'WARM UP',  class: 'zone-warmup' },
            fatburn: { min: 0.60, max: 0.70, name: 'FAT BURN', class: 'zone-fatburn' },
            cardio:  { min: 0.70, max: 0.80, name: 'CARDIO',   class: 'zone-cardio' },
            peak:    { min: 0.80, max: 0.90, name: 'PEAK',     class: 'zone-peak' },
            max:     { min: 0.90, max: 1.10, name: 'MAX',      class: 'zone-max' }
        };
        let hrPeakSession = 0;
        let hrSumSession = 0;
        let hrCountSession = 0;
        let hrZoneSeconds = { rest: 0, warmup: 0, fatburn: 0, cardio: 0, peak: 0, max: 0 };
        let hrLastZone = null;
        let hrLastUpdate = Date.now();
        let antConnected = false;

        function getHRZone(hr) {
            if (!hr || hr <= 0) return null;
            const pct = hr / HR_MAX;
            for (const [key, zone] of Object.entries(HR_ZONES)) {
                if (pct >= zone.min && pct < zone.max) {
                    return { key, ...zone };
                }
            }
            return { key: 'max', ...HR_ZONES.max };
        }

        function formatZoneTime(seconds) {
            const mins = Math.floor(seconds / 60);
            const secs = seconds % 60;
            return mins + ':' + String(secs).padStart(2, '0');
        }

        function updateHeartRateDisplay(hr) {
            const hrLarge = document.getElementById('hrValueLarge');
            const hrHero = document.getElementById('hrHeroDisplay');
            const hrZoneName = document.getElementById('hrZoneName');
            const hrMarker = document.getElementById('hrZoneMarker');

            // Clear previous zone classes
            const allZoneClasses = Object.values(HR_ZONES).map(z => z.class);
            hrLarge.classList.remove(...allZoneClasses);
            hrHero.classList.remove(...allZoneClasses);
            hrZoneName.classList.remove(...allZoneClasses);

            if (!hr || hr <= 0) {
                hrLarge.textContent = '--';
                hrZoneName.textContent = 'NO SIGNAL';
                hrMarker.style.left = '0%';
                document.getElementById('antIcon').textContent = '--';
                document.getElementById('antDeviceId').textContent = 'Searching...';
                antConnected = false;
                return;
            }

            antConnected = true;
            hrLarge.textContent = hr;
            document.getElementById('antIcon').textContent = 'HR';
            document.getElementById('antDeviceId').textContent = 'Connected';

            const zone = getHRZone(hr);
            if (zone) {
                hrLarge.classList.add(zone.class);
                hrHero.classList.add(zone.class);
                hrZoneName.classList.add(zone.class);
                hrZoneName.textContent = zone.name;

                // Update marker position (0-100% across the bar)
                const pct = Math.min((hr / HR_MAX) * 100, 100);
                // Map HR percentage to bar position (bar shows 50%-100% of max HR)
                const markerPos = Math.max(0, Math.min(100, (pct - 50) * 2));
                hrMarker.style.left = markerPos + '%';

                // Track time in zone
                const now = Date.now();
                const elapsed = Math.floor((now - hrLastUpdate) / 1000);
                if (hrLastZone && elapsed > 0 && elapsed < 5) {
                    hrZoneSeconds[hrLastZone] += elapsed;
                }
                hrLastZone = zone.key;
                hrLastUpdate = now;

                // Zone change alert
                if (zone.key === 'max' && hrLastZone !== 'max') {
                    // Could trigger voice alert here
                }
            }

            // Update peak and average
            if (hr > hrPeakSession) {
                hrPeakSession = hr;
                document.getElementById('hrPeak').textContent = hrPeakSession;
            }
            hrSumSession += hr;
            hrCountSession++;
            const hrAvg = Math.round(hrSumSession / hrCountSession);
            document.getElementById('hrAvg').textContent = hrAvg;

            // Update zone time displays
            for (const [zoneKey, seconds] of Object.entries(hrZoneSeconds)) {
                const el = document.getElementById('zoneTime' + zoneKey.charAt(0).toUpperCase() + zoneKey.slice(1));
                if (el) el.textContent = formatZoneTime(seconds);
            }
        }

        // ============ Tab Navigation ============
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
                document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
                btn.classList.add('active');
                const tabId = 'tab-' + btn.dataset.tab;
                document.getElementById(tabId).classList.add('active');
                currentTab = btn.dataset.tab;
            });
        });

        // ============ Charts ============
        const chartDefaults = {
            responsive: true,
            maintainAspectRatio: false,
            animation: false,
            plugins: { legend: { display: false } },
            scales: {
                x: { display: false },
                y: { beginAtZero: true, grid: { color: '#334155' }, ticks: { color: '#94a3b8' } }
            }
        };

        // Speed chart
        const speedCtx = document.getElementById('speedChart').getContext('2d');
        const speedChart = new Chart(speedCtx, {
            type: 'line',
            data: {
                labels: Array(60).fill(''),
                datasets: [{
                    data: Array(60).fill(0),
                    borderColor: '#3b82f6',
                    borderWidth: 2,
                    fill: true,
                    backgroundColor: 'rgba(59, 130, 246, 0.1)',
                    tension: 0.3,
                    pointRadius: 0
                }]
            },
            options: chartDefaults
        });

        // RPM/Throttle chart
        const rpmCtx = document.getElementById('rpmChart').getContext('2d');
        const rpmChart = new Chart(rpmCtx, {
            type: 'line',
            data: {
                labels: Array(120).fill(''),
                datasets: [
                    { label: 'RPM', data: Array(120).fill(0), borderColor: '#ef4444', borderWidth: 2, fill: false, tension: 0.2, pointRadius: 0, yAxisID: 'y' },
                    { label: 'Throttle', data: Array(120).fill(0), borderColor: '#22c55e', borderWidth: 2, fill: false, tension: 0.2, pointRadius: 0, yAxisID: 'y1' }
                ]
            },
            options: {
                ...chartDefaults,
                plugins: { legend: { display: true, position: 'top', labels: { color: '#94a3b8', boxWidth: 12 } } },
                scales: {
                    x: { display: false },
                    y: { type: 'linear', position: 'left', min: 0, max: 8000, grid: { color: '#334155' }, ticks: { color: '#ef4444' } },
                    y1: { type: 'linear', position: 'right', min: 0, max: 100, grid: { drawOnChartArea: false }, ticks: { color: '#22c55e' } }
                }
            }
        });

        // Heart rate chart
        const heartCtx = document.getElementById('heartChart').getContext('2d');
        const heartChart = new Chart(heartCtx, {
            type: 'line',
            data: {
                labels: Array(60).fill(''),
                datasets: [{
                    data: Array(60).fill(null),
                    borderColor: '#ef4444',
                    borderWidth: 2,
                    fill: true,
                    backgroundColor: 'rgba(239, 68, 68, 0.1)',
                    tension: 0.3,
                    pointRadius: 0
                }]
            },
            options: { ...chartDefaults, scales: { ...chartDefaults.scales, y: { ...chartDefaults.scales.y, min: 40, max: 200 } } }
        });

        // ============ Units & Race Configuration ============
        // Units: 'imperial' (miles, mph) or 'metric' (km, km/h)
        const UNITS = 'imperial';  // Default for off-road racing in USA
        // Race type: 'point_to_point' or 'lap_based'
        let raceType = 'point_to_point';  // Default for desert racing (King of Hammers, Baja, etc.)
        let totalLaps = 1;  // For lap-based races like Laughlin

        function setRaceType(type) {
            raceType = type;
            // Show/hide lap count input based on race type
            const lapCountDiv = document.getElementById('lapCountDiv');
            if (lapCountDiv) {
                lapCountDiv.style.display = type === 'lap_based' ? 'flex' : 'none';
            }
            // Reload fuel and tire status to update labels
            loadFuelStatus();
            loadTireStatus();
            // Save preference
            localStorage.setItem('argus_race_type', type);
        }

        function setTotalLaps(laps) {
            totalLaps = parseInt(laps) || 1;
            localStorage.setItem('argus_total_laps', totalLaps);
        }

        // Unit conversion helpers
        const EARTH_RADIUS_MI = 3959;  // Earth's radius in miles
        const EARTH_RADIUS_KM = 6371;  // Earth's radius in km
        const KM_TO_MI = 0.621371;
        const MI_TO_KM = 1.60934;

        function getDistanceUnit() {
            return UNITS === 'imperial' ? 'mi' : 'km';
        }

        function getSpeedUnit() {
            return UNITS === 'imperial' ? 'mph' : 'km/h';
        }

        function formatDistance(distanceMiles) {
            // All internal distances stored in miles, convert for display if metric
            if (UNITS === 'metric') {
                return (distanceMiles * MI_TO_KM).toFixed(1);
            }
            return distanceMiles.toFixed(1);
        }

        // ============ Course Map (Feature 4) ============
        let courseMap = null;
        let coursePath = null;
        let coursePoints = [];
        let vehicleMarker = null;
        let courseLoaded = false;
        let courseTotalDistance = 0;  // Always stored in miles internally
        let courseStartTime = null;
        let lastGpsTs = 0;  // Track last GPS timestamp for stale detection
        let lastHeading = 0;  // Last known heading
        let gpsTestMode = false;  // Test mode for simulated GPS

        // GPS stale threshold (5 seconds)
        const GPS_STALE_THRESHOLD_MS = 5000;

        function createVehicleMarkerHtml(heading, speed, isStale) {
            // Arrow marker that rotates with heading
            const color = isStale ? '#ef4444' : '#3b82f6';  // Red if stale, blue otherwise
            const arrowHtml = `
                <div class="vehicle-marker-container" style="transform: rotate(${heading}deg);">
                    <svg width="32" height="32" viewBox="0 0 32 32" style="filter: drop-shadow(0 2px 4px rgba(0,0,0,0.5));">
                        <polygon points="16,2 28,28 16,22 4,28" fill="${color}" stroke="white" stroke-width="2"/>
                    </svg>
                </div>
                ${speed > 0 ? `<div class="vehicle-speed-label">${Math.round(speed)} mph</div>` : ''}
            `;
            return arrowHtml;
        }

        function initCourseMap() {
            if (courseMap) return; // Already initialized

            const mapContainer = document.getElementById('courseMap');
            if (!mapContainer) return;

            // Initialize map centered on a default location
            courseMap = L.map('courseMap', {
                zoomControl: true,
                attributionControl: false
            }).setView([33.7490, -117.8732], 10); // Default: Southern California

            // EDGE-MAP-0: Basemap with automatic fallback (Topo -> Streets)
            const basemapStyles = {
                topo: {
                    url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
                    maxZoom: 17,
                    label: 'Topo'
                },
                street: {
                    url: 'https://{s}.basemaps.cartocdn.com/voyager/{z}/{x}/{y}{r}.png',
                    maxZoom: 19,
                    label: 'Street'
                }
            };

            let currentBasemapKey = 'topo';
            let topoAvailable = true;
            let topoErrorCount = 0;
            const TOPO_ERROR_THRESHOLD = 3;

            // Streets layer always present underneath as safety net
            const streetLayer = L.tileLayer(basemapStyles.street.url, {
                maxZoom: basemapStyles.street.maxZoom
            }).addTo(courseMap);

            // Topo layer on top (covers streets when working)
            let topoLayer = L.tileLayer(basemapStyles.topo.url, {
                maxZoom: basemapStyles.topo.maxZoom
            }).addTo(courseMap);

            // EDGE-MAP-0: Detect topo tile failures and auto-fallback
            function showMapBanner(msg) {
                let banner = document.getElementById('mapTileBanner');
                if (!banner) {
                    banner = document.createElement('div');
                    banner.id = 'mapTileBanner';
                    banner.style.cssText = 'position:absolute;top:8px;left:50%;transform:translateX(-50%);' +
                        'z-index:1000;padding:6px 14px;border-radius:6px;font-size:0.75rem;font-weight:600;' +
                        'background:rgba(245,158,11,0.95);color:#000;pointer-events:none;white-space:nowrap;';
                    var container = document.getElementById('courseMapContainer');
                    if (container) container.appendChild(banner);
                }
                banner.textContent = msg;
                banner.style.display = '';
            }

            function hideMapBanner() {
                var banner = document.getElementById('mapTileBanner');
                if (banner) banner.style.display = 'none';
            }

            function fallbackToStreets() {
                if (!topoAvailable) return;
                topoAvailable = false;
                courseMap.removeLayer(topoLayer);
                currentBasemapKey = 'street';
                showMapBanner('Topo basemap unavailable \u2014 showing Streets');
                var btn = document.getElementById('basemapToggleBtn');
                if (btn) {
                    btn.textContent = 'Street';
                    btn.title = 'Topo unavailable \u2014 showing Streets';
                }
                console.warn('EDGE-MAP-0: Topo tiles failed after ' + TOPO_ERROR_THRESHOLD + ' errors, fell back to Streets');
            }

            topoLayer.on('tileerror', function() {
                topoErrorCount++;
                if (topoErrorCount >= TOPO_ERROR_THRESHOLD) {
                    fallbackToStreets();
                }
            });

            // Add basemap toggle control (top-right)
            const basemapToggle = L.control({ position: 'topright' });
            basemapToggle.onAdd = function() {
                const div = L.DomUtil.create('div', 'leaflet-bar');
                div.innerHTML = '<a href="#" id="basemapToggleBtn" title="Switch basemap" style="' +
                    'display:flex;align-items:center;justify-content:center;' +
                    'width:34px;height:34px;font-size:14px;background:white;' +
                    'color:#333;text-decoration:none;font-weight:bold;' +
                    'cursor:pointer;user-select:none;">Topo</a>';
                L.DomEvent.disableClickPropagation(div);
                div.querySelector('#basemapToggleBtn').addEventListener('click', function(e) {
                    e.preventDefault();
                    if (currentBasemapKey === 'topo') {
                        // Switch to street: remove topo overlay, show streets underneath
                        courseMap.removeLayer(topoLayer);
                        currentBasemapKey = 'street';
                        this.textContent = 'Street';
                        this.title = 'Current: Street (click to switch)';
                        hideMapBanner();
                    } else {
                        // Switch to topo: re-add topo overlay on top
                        if (!topoAvailable) {
                            // Topo previously failed — retry with fresh layer
                            topoErrorCount = 0;
                            topoAvailable = true;
                        }
                        topoLayer = L.tileLayer(basemapStyles.topo.url, {
                            maxZoom: basemapStyles.topo.maxZoom
                        }).addTo(courseMap);
                        topoLayer.on('tileerror', function() {
                            topoErrorCount++;
                            if (topoErrorCount >= TOPO_ERROR_THRESHOLD) {
                                fallbackToStreets();
                            }
                        });
                        currentBasemapKey = 'topo';
                        this.textContent = 'Topo';
                        this.title = 'Current: Topo (click to switch)';
                        hideMapBanner();
                    }
                });
                return div;
            };
            basemapToggle.addTo(courseMap);

            // Create vehicle marker (arrow icon that shows heading)
            const vehicleIcon = L.divIcon({
                className: 'vehicle-marker',
                html: createVehicleMarkerHtml(0, 0, false),
                iconSize: [32, 32],
                iconAnchor: [16, 16]
            });
            vehicleMarker = L.marker([0, 0], { icon: vehicleIcon }).addTo(courseMap);
            vehicleMarker.setOpacity(0);

            document.getElementById('mapPlaceholder').style.display = 'none';

            // Start GPS stale checker
            setInterval(checkGpsStale, 1000);
        }

        function checkGpsStale() {
            if (!vehicleMarker || lastGpsTs === 0) return;

            const now = Date.now();
            const isStale = (now - lastGpsTs) > GPS_STALE_THRESHOLD_MS;
            const staleWarning = document.getElementById('gpsStaleWarning');

            if (isStale && !gpsTestMode) {
                // Update marker to show stale state (not in test mode)
                const newIcon = L.divIcon({
                    className: 'vehicle-marker vehicle-marker-stale',
                    html: createVehicleMarkerHtml(lastHeading, 0, true),
                    iconSize: [32, 32],
                    iconAnchor: [16, 16]
                });
                vehicleMarker.setIcon(newIcon);

                // Show stale warning
                if (staleWarning) {
                    const staleSecs = Math.round((now - lastGpsTs) / 1000);
                    staleWarning.style.display = 'block';
                    staleWarning.innerHTML = `GPS STALE (${staleSecs}s ago)`;
                }
            } else {
                if (staleWarning) {
                    staleWarning.style.display = 'none';
                }
            }
        }

        // ============ GPS Test Mode ============
        // Simulates GPS updates along the loaded course for verification
        let gpsTestInterval = null;
        let gpsTestIndex = 0;
        let gpsTestSpeed = 45;  // Simulated speed in mph

        function toggleGpsTestMode() {
            gpsTestMode = !gpsTestMode;
            const btn = document.getElementById('gpsTestModeBtn');
            const indicator = document.getElementById('gpsTestModeIndicator');

            if (gpsTestMode) {
                if (!courseLoaded || coursePoints.length < 2) {
                    alert('Load a GPX course first to use test mode');
                    gpsTestMode = false;
                    return;
                }

                btn.textContent = 'Stop';
                btn.style.background = 'var(--danger)';
                indicator.style.display = 'block';

                // Start simulating GPS along course
                gpsTestIndex = 0;
                gpsTestInterval = setInterval(runGpsTestTick, 1000);  // 1 Hz updates
                console.log('GPS Test Mode: STARTED - Simulating vehicle along course');
            } else {
                btn.textContent = 'Test';
                btn.style.background = '';
                indicator.style.display = 'none';

                if (gpsTestInterval) {
                    clearInterval(gpsTestInterval);
                    gpsTestInterval = null;
                }
                console.log('GPS Test Mode: STOPPED');
            }
        }

        function runGpsTestTick() {
            if (!gpsTestMode || !courseLoaded || coursePoints.length < 2) return;

            // Get current and next point
            const currentPoint = coursePoints[gpsTestIndex];
            const nextIndex = Math.min(gpsTestIndex + 1, coursePoints.length - 1);
            const nextPoint = coursePoints[nextIndex];

            // Calculate heading to next point
            const heading = calculateBearing(currentPoint, nextPoint);

            // Add small random variation to simulate GPS noise
            const lat = currentPoint[0] + (Math.random() - 0.5) * 0.00005;
            const lon = currentPoint[1] + (Math.random() - 0.5) * 0.00005;

            // Vary speed slightly
            const speed = gpsTestSpeed + (Math.random() - 0.5) * 10;

            // Update position
            updateCoursePosition(lat, lon, speed, heading, Date.now());

            // Move to next point (advance ~0.1 miles per second at 45mph)
            // 45 mph = 0.0125 miles per second, so advance 1-3 points per tick
            const pointsPerTick = Math.max(1, Math.floor(coursePoints.length / 100));
            gpsTestIndex += pointsPerTick;

            // Loop back to start when reaching end
            if (gpsTestIndex >= coursePoints.length) {
                gpsTestIndex = 0;
                console.log('GPS Test Mode: Lap completed, restarting');
            }
        }

        function calculateBearing(p1, p2) {
            const lat1 = p1[0] * Math.PI / 180;
            const lat2 = p2[0] * Math.PI / 180;
            const dLon = (p2[1] - p1[1]) * Math.PI / 180;

            const x = Math.sin(dLon) * Math.cos(lat2);
            const y = Math.cos(lat1) * Math.sin(lat2) -
                      Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);

            let bearing = Math.atan2(x, y) * 180 / Math.PI;
            return (bearing + 360) % 360;
        }

        function parseGPX(gpxText) {
            const parser = new DOMParser();
            const gpx = parser.parseFromString(gpxText, 'text/xml');

            const points = [];
            const trkpts = gpx.querySelectorAll('trkpt');

            trkpts.forEach(pt => {
                const lat = parseFloat(pt.getAttribute('lat'));
                const lon = parseFloat(pt.getAttribute('lon'));
                if (!isNaN(lat) && !isNaN(lon)) {
                    points.push([lat, lon]);
                }
            });

            // Also check for route points (rtept) and waypoints (wpt)
            if (points.length === 0) {
                const rtepts = gpx.querySelectorAll('rtept');
                rtepts.forEach(pt => {
                    const lat = parseFloat(pt.getAttribute('lat'));
                    const lon = parseFloat(pt.getAttribute('lon'));
                    if (!isNaN(lat) && !isNaN(lon)) {
                        points.push([lat, lon]);
                    }
                });
            }

            return points;
        }

        function calculateTotalDistance(points) {
            let total = 0;
            for (let i = 1; i < points.length; i++) {
                total += haversineDistance(points[i-1], points[i]);
            }
            return total;
        }

        function haversineDistance(p1, p2) {
            // Returns distance in MILES (for imperial/off-road racing default)
            const R = EARTH_RADIUS_MI;  // 3959 miles
            const dLat = (p2[0] - p1[0]) * Math.PI / 180;
            const dLon = (p2[1] - p1[1]) * Math.PI / 180;
            const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                      Math.cos(p1[0] * Math.PI / 180) * Math.cos(p2[0] * Math.PI / 180) *
                      Math.sin(dLon/2) * Math.sin(dLon/2);
            const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
            return R * c;
        }

        function loadCourse(points, fileName) {
            if (!courseMap) initCourseMap();
            if (points.length < 2) {
                alert('GPX file does not contain enough track points');
                return;
            }

            coursePoints = points;
            courseTotalDistance = calculateTotalDistance(points);
            courseLoaded = true;
            courseStartTime = Date.now();

            // Remove existing path
            if (coursePath) {
                courseMap.removeLayer(coursePath);
            }

            // Draw course path
            coursePath = L.polyline(points, {
                color: '#3b82f6',
                weight: 4,
                opacity: 0.8
            }).addTo(courseMap);

            // Add start and finish markers
            L.circleMarker(points[0], {
                radius: 8,
                color: '#22c55e',
                fillColor: '#22c55e',
                fillOpacity: 1
            }).addTo(courseMap).bindPopup('Start');

            L.circleMarker(points[points.length - 1], {
                radius: 8,
                color: '#ef4444',
                fillColor: '#ef4444',
                fillOpacity: 1
            }).addTo(courseMap).bindPopup('Finish');

            // Fit map to course bounds
            courseMap.fitBounds(coursePath.getBounds(), { padding: [30, 30] });

            // Update UI with correct units
            document.getElementById('courseLoadedInfo').style.display = 'flex';
            document.getElementById('courseProgressCard').style.display = 'block';
            document.getElementById('mapPlaceholder').style.display = 'none';
            document.getElementById('courseFileName').textContent = fileName;
            document.getElementById('courseMeta').textContent =
                formatDistance(courseTotalDistance) + ' ' + getDistanceUnit() + ' • ' + points.length + ' waypoints';
            document.getElementById('courseDistanceLeft').textContent = formatDistance(courseTotalDistance);

            // Update unit labels in the UI
            const doneLabel = document.getElementById('courseDistanceDoneLabel');
            const leftLabel = document.getElementById('courseDistanceLeftLabel');
            if (doneLabel) doneLabel.textContent = getDistanceUnit() + ' Done';
            if (leftLabel) leftLabel.textContent = getDistanceUnit() + ' Left';
        }

        function handleGPXUpload(event) {
            const file = event.target.files[0];
            if (!file) return;

            const reader = new FileReader();
            reader.onload = function(e) {
                const gpxText = e.target.result;
                const points = parseGPX(gpxText);
                loadCourse(points, file.name);

                // Save to server (persists across devices)
                fetch('/api/course/upload', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ filename: file.name, gpx_data: gpxText })
                }).then(r => {
                    if (!r.ok) throw new Error('Server returned ' + r.status);
                    return r.json();
                }).then(data => {
                    if (data.success) {
                        console.log('Course saved to server:', file.name);
                        // Show brief save confirmation
                        const meta = document.getElementById('courseMeta');
                        if (meta) {
                            const origText = meta.textContent;
                            meta.textContent = 'Saved to server';
                            setTimeout(() => { meta.textContent = origText; }, 2000);
                        }
                    } else {
                        console.error('Failed to save course:', data.error);
                    }
                }).catch(err => {
                    console.error('Failed to save course:', err);
                    alert('Warning: Course loaded locally but failed to save to server. Other devices may not see it.');
                });
            };
            reader.readAsText(file);
        }

        function clearCourse() {
            if (coursePath) {
                courseMap.removeLayer(coursePath);
                coursePath = null;
            }
            coursePoints = [];
            courseLoaded = false;
            courseTotalDistance = 0;

            document.getElementById('courseLoadedInfo').style.display = 'none';
            document.getElementById('courseProgressCard').style.display = 'none';
            document.getElementById('mapPlaceholder').style.display = 'flex';
            document.getElementById('gpxFileInput').value = '';

            fetch('/api/course/clear', { method: 'POST' }).catch(() => {});
        }

        function centerOnVehicle() {
            if (courseMap && vehicleMarker) {
                const pos = vehicleMarker.getLatLng();
                if (pos.lat !== 0 || pos.lng !== 0) {
                    courseMap.setView(pos, 15);
                }
            }
        }

        function findClosestPointOnCourse(lat, lon) {
            if (!coursePoints.length) return { index: 0, distance: 0, progress: 0 };

            let minDist = Infinity;
            let closestIdx = 0;

            for (let i = 0; i < coursePoints.length; i++) {
                const dist = haversineDistance([lat, lon], coursePoints[i]);
                if (dist < minDist) {
                    minDist = dist;
                    closestIdx = i;
                }
            }

            // Calculate distance traveled along course
            let traveled = 0;
            for (let i = 1; i <= closestIdx; i++) {
                traveled += haversineDistance(coursePoints[i-1], coursePoints[i]);
            }

            const progress = courseTotalDistance > 0 ? (traveled / courseTotalDistance) * 100 : 0;

            return {
                index: closestIdx,
                distanceFromCourse: minDist,
                distanceTraveled: traveled,
                progress: Math.min(progress, 100)
            };
        }

        function updateCoursePosition(lat, lon, speed, heading, gpsTs) {
            if (!courseMap || !vehicleMarker) return;
            if (lat === 0 && lon === 0) return;

            // Track GPS timestamp for stale detection
            if (gpsTs && gpsTs > 0) {
                lastGpsTs = gpsTs;
            } else {
                lastGpsTs = Date.now();  // Use current time if not provided
            }

            // Update heading (use last known if not provided)
            if (heading !== undefined && heading !== null) {
                lastHeading = heading;
            }

            // Update vehicle marker position and icon
            vehicleMarker.setLatLng([lat, lon]);
            vehicleMarker.setOpacity(1);

            // Update marker icon with heading and speed
            const newIcon = L.divIcon({
                className: 'vehicle-marker',
                html: createVehicleMarkerHtml(lastHeading, speed, false),
                iconSize: [32, 32],
                iconAnchor: [16, 16]
            });
            vehicleMarker.setIcon(newIcon);

            // Update GPS display
            document.getElementById('courseGpsLat').textContent = lat.toFixed(6);
            document.getElementById('courseGpsLon').textContent = lon.toFixed(6);

            // Update heading display
            const headingEl = document.getElementById('courseHeading');
            if (headingEl) {
                headingEl.textContent = Math.round(lastHeading);
            }

            // If course is loaded, calculate progress
            if (courseLoaded && coursePoints.length > 0) {
                const position = findClosestPointOnCourse(lat, lon);

                // All distances in miles internally
                const distanceDone = position.distanceTraveled;
                const distanceLeft = Math.max(0, courseTotalDistance - distanceDone);

                document.getElementById('courseProgressFill').style.width = position.progress + '%';
                document.getElementById('courseProgressPct').textContent = Math.round(position.progress) + '%';
                document.getElementById('courseDistanceDone').textContent = formatDistance(distanceDone);
                document.getElementById('courseDistanceLeft').textContent = formatDistance(distanceLeft);

                // Calculate ETA based on current speed (speed is in mph for telemetry)
                if (speed > 0) {
                    // distanceLeft is in miles, speed is in mph
                    const hoursRemaining = distanceLeft / speed;
                    const minutesRemaining = Math.round(hoursRemaining * 60);
                    if (minutesRemaining <= 0) {
                        document.getElementById('courseETA').textContent = 'Done';
                    } else if (minutesRemaining < 60) {
                        document.getElementById('courseETA').textContent = minutesRemaining + 'm';
                    } else {
                        document.getElementById('courseETA').textContent =
                            Math.floor(minutesRemaining / 60) + 'h ' + (minutesRemaining % 60) + 'm';
                    }
                }

                // Show next waypoint number
                document.getElementById('courseNextWaypoint').textContent =
                    Math.min(position.index + 1, coursePoints.length);
            }
        }

        // Setup drag & drop for GPX upload
        document.addEventListener('DOMContentLoaded', function() {
            // Restore race type preferences
            const savedType = localStorage.getItem('argus_race_type');
            if (savedType) {
                raceType = savedType;
                const select = document.getElementById('raceTypeSelect');
                if (select) select.value = savedType;
                const lapCountDiv = document.getElementById('lapCountDiv');
                if (lapCountDiv) lapCountDiv.style.display = savedType === 'lap_based' ? 'flex' : 'none';
            }
            const savedLaps = localStorage.getItem('argus_total_laps');
            if (savedLaps) {
                totalLaps = parseInt(savedLaps) || 1;
                const lapInput = document.getElementById('lapCountInput');
                if (lapInput) lapInput.value = totalLaps;
            }

            const dropZone = document.getElementById('gpxUploadZone');
            if (dropZone) {
                dropZone.addEventListener('dragover', (e) => {
                    e.preventDefault();
                    dropZone.classList.add('dragover');
                });
                dropZone.addEventListener('dragleave', () => {
                    dropZone.classList.remove('dragover');
                });
                dropZone.addEventListener('drop', (e) => {
                    e.preventDefault();
                    dropZone.classList.remove('dragover');
                    const file = e.dataTransfer.files[0];
                    if (file && file.name.endsWith('.gpx')) {
                        const reader = new FileReader();
                        reader.onload = function(ev) {
                            const gpxText = ev.target.result;
                            const points = parseGPX(gpxText);
                            loadCourse(points, file.name);
                            // Also save to server (same as file input handler)
                            fetch('/api/course/upload', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({ filename: file.name, gpx_data: gpxText })
                            }).then(r => r.ok ? r.json() : Promise.reject('HTTP ' + r.status))
                              .then(() => console.log('Course saved via drag-drop'))
                              .catch(err => console.error('Failed to save dropped course:', err));
                        };
                        reader.readAsText(file);
                    }
                });
            }

            // Load any saved course from server (shared across all devices)
            fetch('/api/course').then(r => {
                if (!r.ok) {
                    console.error('Failed to load saved course: HTTP ' + r.status);
                    return {};
                }
                return r.json();
            }).then(data => {
                if (data.gpx_data && data.filename) {
                    console.log('Loading saved course:', data.filename);
                    initCourseMap();
                    const points = parseGPX(data.gpx_data);
                    if (points.length > 0) {
                        loadCourse(points, data.filename);
                    } else {
                        console.warn('Saved course has no valid track points');
                    }
                } else {
                    console.log('No saved course found');
                }
            }).catch(err => {
                console.error('Error loading saved course:', err);
            });
        });

        // ============ SSE Connection ============
        let eventSource = null;
        let reconnectTimer = null;

        function connect() {
            if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
            eventSource = new EventSource('/api/telemetry/stream');

            eventSource.onmessage = (event) => {
                const data = JSON.parse(event.data);
                updateDashboard(data);
            };

            eventSource.onerror = () => {
                console.log('SSE error, reconnecting...');
                eventSource.close();
                reconnectTimer = setTimeout(connect, 2000);
            };
        }

        // ============ Dashboard Update ============
        // PIT-CAN-1: Check for null to show "--" until real CAN data arrives
        function updateDashboard(data) {
            // EDGE-CLOUD-2: Update banner FIRST, before any DOM access that might crash.
            // This ensures the banner always reflects backend reality, even if
            // other UI elements fail to render (missing DOM nodes, etc).
            try {
                var banner = document.getElementById('offlineBanner');
                if (banner) {
                    var detail = data.cloud_detail || 'not_configured';
                    banner.classList.remove('info', 'error');
                    if (detail === 'healthy') {
                        banner.classList.remove('active');
                    } else {
                        banner.classList.add('active');
                        if (detail === 'not_configured') {
                            banner.classList.add('info');
                            banner.textContent = 'Cloud not configured \u2014 Go to Settings to connect';
                        } else if (detail === 'event_not_live') {
                            banner.classList.add('info');
                            banner.textContent = 'Cloud connected \u2014 Waiting for event to go live';
                        } else if (detail === 'auth_rejected') {
                            banner.classList.add('error');
                            banner.textContent = 'Cloud auth rejected \u2014 Check truck token in Settings';
                        } else {
                            banner.textContent = 'Cloud connection lost \u2014 Data buffered locally';
                        }
                    }
                }
            } catch (bannerErr) {
                console.warn('Banner update failed:', bannerErr);
            }

            // Wrap remaining UI updates in try-catch so DOM errors
            // never propagate and break the EventSource handler.
            try {
            const maxRpm = 7500;

            // Engine tab - NASCAR-style Tachometer
            // PIT-CAN-1: Handle null RPM
            if (data.rpm !== null && data.rpm !== undefined) {
                const rpm = data.rpm;
                document.getElementById('rpmValue').textContent = Math.round(rpm).toLocaleString();
                const rpmPct = Math.min(rpm / maxRpm, 1);
                const needleAngle = -135 + (rpmPct * 270);
                document.getElementById('tachNeedle').style.transform = 'rotate(' + needleAngle + 'deg)';
                // Update tachometer arc color based on RPM zone
                const tachArc = document.getElementById('tachArc');
                tachArc.classList.remove('warning', 'danger');
                if (rpm > 7000) {
                    tachArc.classList.add('danger');
                } else if (rpm > 6000) {
                    tachArc.classList.add('warning');
                }
            } else {
                document.getElementById('rpmValue').textContent = '--';
                document.getElementById('tachNeedle').style.transform = 'rotate(-135deg)';
                document.getElementById('tachArc').classList.remove('warning', 'danger');
            }

            // Gear display - PIT-CAN-1: Handle null gear
            if (data.gear !== null && data.gear !== undefined) {
                const gear = data.gear;
                document.getElementById('gearValue').textContent = gear === 0 ? 'N' : (gear === -1 ? 'R' : gear);
            } else {
                document.getElementById('gearValue').textContent = '--';
            }

            // Speed in engine tab - PIT-CAN-1: Handle null speed
            if (data.speed_mph !== null && data.speed_mph !== undefined) {
                document.getElementById('speedValueEngine').textContent = Math.round(data.speed_mph);
            } else {
                document.getElementById('speedValueEngine').textContent = '--';
            }

            // PIT-CAN-1: Coolant tile in 2x2 grid (with color coding)
            // Check for null/undefined to show placeholder until real CAN data arrives
            const coolantC = data.coolant_temp;
            const coolantTileEl = document.getElementById('coolantTileValue');
            const coolantTileFill = document.getElementById('coolantTileFill');
            if (coolantC !== null && coolantC !== undefined) {
                const coolantTileF = coolantC * 1.8 + 32;
                coolantTileEl.textContent = Math.round(coolantTileF);
                coolantTileFill.style.width = Math.min(coolantTileF / 260 * 100, 100) + '%';
                // Color code: normal < 220F, warning 220-250F, danger > 250F
                const tile = document.getElementById('coolantTile');
                tile.style.borderLeft = coolantTileF > 250 ? '3px solid var(--danger)' :
                    coolantTileF > 220 ? '3px solid var(--warning)' : '3px solid transparent';
            } else {
                coolantTileEl.textContent = '--';
                coolantTileFill.style.width = '0%';
                document.getElementById('coolantTile').style.borderLeft = '3px solid transparent';
            }

            // CAN data age indicator
            const now = Date.now();
            const canAge = data.last_update_ms ? (now - data.last_update_ms) : 99999;
            const freshnessEl = document.getElementById('telemetryFreshness');
            document.getElementById('canDataAge').textContent = canAge < 1000 ? 'Live' : (canAge / 1000).toFixed(1) + 's ago';
            freshnessEl.classList.remove('stale', 'offline');
            if (canAge > 5000) freshnessEl.classList.add('offline');
            else if (canAge > 2000) freshnessEl.classList.add('stale');

            // PIT-CAN-1: Engine vitals grid - with gauge bar fills
            // Check for null to show "--" placeholder until real CAN data arrives
            if (data.coolant_temp !== null && data.coolant_temp !== undefined) {
                const coolantF = data.coolant_temp * 1.8 + 32;
                document.getElementById('coolantValue').textContent = Math.round(coolantF);
                document.getElementById('coolantFill').style.width = Math.min(coolantF / 260 * 100, 100) + '%';
            } else {
                document.getElementById('coolantValue').textContent = '--';
                document.getElementById('coolantFill').style.width = '0%';
            }

            if (data.oil_pressure !== null && data.oil_pressure !== undefined) {
                document.getElementById('oilValue').textContent = Math.round(data.oil_pressure);
                document.getElementById('oilFill').style.width = Math.min(data.oil_pressure / 80 * 100, 100) + '%';
            } else {
                document.getElementById('oilValue').textContent = '--';
                document.getElementById('oilFill').style.width = '0%';
            }

            if (data.oil_temp !== null && data.oil_temp !== undefined) {
                const oilTempF = data.oil_temp * 1.8 + 32;
                document.getElementById('oilTempValue').textContent = Math.round(oilTempF);
                document.getElementById('oilTempFill').style.width = Math.min(oilTempF / 300 * 100, 100) + '%';
            } else {
                document.getElementById('oilTempValue').textContent = '--';
                document.getElementById('oilTempFill').style.width = '0%';
            }

            if (data.fuel_pressure !== null && data.fuel_pressure !== undefined) {
                document.getElementById('fuelValue').textContent = Math.round(data.fuel_pressure);
                document.getElementById('fuelFill').style.width = Math.min(data.fuel_pressure / 60 * 100, 100) + '%';
            } else {
                document.getElementById('fuelValue').textContent = '--';
                document.getElementById('fuelFill').style.width = '0%';
            }

            if (data.throttle_pct !== null && data.throttle_pct !== undefined) {
                document.getElementById('throttleValue').textContent = Math.round(data.throttle_pct);
                document.getElementById('throttleFill').style.width = data.throttle_pct + '%';
            } else {
                document.getElementById('throttleValue').textContent = '--';
                document.getElementById('throttleFill').style.width = '0%';
            }

            // Intake Air Temperature (IAT)
            const iatF = (data.intake_air_temp || 0) * 1.8 + 32;
            document.getElementById('intakeTempValue').textContent = data.intake_air_temp ? Math.round(iatF) : '--';
            document.getElementById('iatFill').style.width = Math.min(iatF / 200 * 100, 100) + '%';

            // Boost pressure
            document.getElementById('boostValue').textContent = data.boost_pressure ? data.boost_pressure.toFixed(1) : '--';
            document.getElementById('boostFill').style.width = Math.min(((data.boost_pressure || 0) + 14.7) / 35 * 100, 100) + '%';

            // Battery voltage
            document.getElementById('batteryValue').textContent = data.battery_voltage ? data.battery_voltage.toFixed(1) : '--';
            const battPct = Math.max(0, Math.min(((data.battery_voltage || 12) - 10) / 6 * 100, 100));
            document.getElementById('batteryFill').style.width = battPct + '%';

            // PIT-CAN-1: Warning states for new gauges - only when data is valid
            if (data.oil_temp !== null && data.oil_temp !== undefined) {
                const oilTempF = data.oil_temp * 1.8 + 32;
                setGaugeState('oilTempGauge', oilTempF > 280 ? 'danger' : oilTempF > 250 ? 'warning' : '');
            } else {
                setGaugeState('oilTempGauge', '');
            }
            if (data.intake_air_temp !== null && data.intake_air_temp !== undefined) {
                const iatF = data.intake_air_temp * 1.8 + 32;
                setGaugeState('intakeTempGauge', iatF > 150 ? 'danger' : iatF > 130 ? 'warning' : '');
            } else {
                setGaugeState('intakeTempGauge', '');
            }
            if (data.battery_voltage !== null && data.battery_voltage !== undefined) {
                setGaugeState('batteryGauge', data.battery_voltage < 11 ? 'danger' : data.battery_voltage < 12 ? 'warning' : '');
            } else {
                setGaugeState('batteryGauge', '');
            }

            // PIT-CAN-1: Fuel level display - handle null
            if (data.fuel_level_pct !== null && data.fuel_level_pct !== undefined) {
                document.getElementById('fuelLevelPct').textContent = Math.round(data.fuel_level_pct);
                document.getElementById('fuelLevelFill').style.width = data.fuel_level_pct + '%';
                // Add danger class if fuel is critically low
                const fuelFill = document.getElementById('fuelLevelFill');
                if (data.fuel_level_pct < 10) {
                    fuelFill.classList.add('fuel-critical');
                } else {
                    fuelFill.classList.remove('fuel-critical');
                }
            } else {
                document.getElementById('fuelLevelPct').textContent = '--';
                document.getElementById('fuelLevelFill').style.width = '0%';
                document.getElementById('fuelLevelFill').classList.remove('fuel-critical');
            }

            // Vehicle tab - PIT-CAN-1: Handle null speed
            if (data.speed_mph !== null && data.speed_mph !== undefined) {
                document.getElementById('speedValue').textContent = Math.round(data.speed_mph);
            } else {
                document.getElementById('speedValue').textContent = '--';
            }

            // NOTE: Suspension update code removed - not currently in use

            // GPS
            document.getElementById('gpsLat').textContent = (data.lat || 0).toFixed(6);
            document.getElementById('gpsLon').textContent = (data.lon || 0).toFixed(6);
            document.getElementById('gpsSats').textContent = data.satellites || 0;
            document.getElementById('gpsAlt').textContent = Math.round(data.altitude_m || 0);

            // Update course map position (Feature 4)
            updateCoursePosition(data.lat || 0, data.lon || 0, data.speed_mph || 0, data.heading_deg || 0, data.gps_ts_ms || 0);
            document.getElementById('courseGpsSats').textContent = data.satellites || 0;
            if (data.hdop) {
                document.getElementById('courseGpsAccuracy').textContent = (data.hdop * 2.5).toFixed(1);
            }

            // Update weather based on GPS location (Feature 5)
            updateWeather(data.lat || 0, data.lon || 0);

            // Camera status
            // PIT-COMMS-1: Guard getElementById — productionCamera element may not exist
            if (data.current_camera) {
                currentCamera = data.current_camera;
                const prodCamEl = document.getElementById('productionCamera');
                if (prodCamEl) prodCamEl.textContent = currentCamera.toUpperCase();
                updateCameraDisplay();
            }

            // Status indicators (now already declared above)
            // EDGE-STATUS-1: Wider freshness windows — CAN 5s (bus can be intermittent), GPS 10s + satellites
            const canFresh = data.last_update_ms && (now - data.last_update_ms) < 5000;
            const gpsFresh = (data.satellites || 0) > 0 && data.gps_ts_ms && (now - data.gps_ts_ms) < 10000;

            // EDGE-STATUS-1: Tri-state status with boot window
            const bootTs = data.boot_ts_ms || 0;
            setDeviceStatusDot('canStatus', data.can_device_status || 'unknown', canFresh, bootTs);
            setDeviceStatusDot('gpsStatus', data.gps_device_status || 'unknown', gpsFresh, bootTs);
            setDeviceStatusDot('antStatus', data.ant_device_status || 'unknown', data.heart_rate > 0, bootTs);
            // EDGE-STATUS-1: Cloud dot uses cloud_detail for tri-state
            setCloudStatusDot('cloudStatus', data.cloud_detail || 'not_configured', data.cloud_connected);
            document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString();

            // (Banner update moved to top of updateDashboard — EDGE-CLOUD-2)

            // PIT-CAN-1: Warning thresholds & alerts - only apply when data is valid
            if (data.coolant_temp !== null && data.coolant_temp !== undefined) {
                const coolantF = data.coolant_temp * 1.8 + 32;
                setGaugeState('coolantGauge', coolantF > 230 ? 'danger' : coolantF > 210 ? 'warning' : '');
                checkAlerts(data, coolantF);
            } else {
                setGaugeState('coolantGauge', '');
                checkAlerts(data, null);
            }
            if (data.oil_pressure !== null && data.oil_pressure !== undefined) {
                setGaugeState('oilPressGauge', data.oil_pressure < 20 ? 'danger' : data.oil_pressure < 30 ? 'warning' : '');
            } else {
                setGaugeState('oilPressGauge', '');
            }

            // Heart rate - Enhanced zone tracking (Feature 3)
            updateHeartRateDisplay(data.heart_rate || 0);

            // Update heart rate chart
            heartChart.data.datasets[0].data.shift();
            heartChart.data.datasets[0].data.push(data.heart_rate || 0);
            if (currentTab === 'driver') heartChart.update('none');

            // Drive time
            const driveMinutes = Math.floor((now - driveStartTime) / 60000);
            document.getElementById('driverTime').textContent =
                Math.floor(driveMinutes / 60) + ':' + String(driveMinutes % 60).padStart(2, '0');

            // Update charts
            speedChart.data.datasets[0].data.shift();
            speedChart.data.datasets[0].data.push(data.speed_mph || 0);
            if (currentTab === 'vehicle') speedChart.update('none');

            rpmChart.data.datasets[0].data.shift();
            rpmChart.data.datasets[0].data.push(data.rpm || 0);
            rpmChart.data.datasets[1].data.shift();
            rpmChart.data.datasets[1].data.push(data.throttle_pct || 0);
            if (currentTab === 'engine') rpmChart.update('none');

            // P1: Update race position (from cloud leaderboard)
            updateRacePosition(data);
            } catch (uiErr) {
                // EDGE-CLOUD-2: DOM errors must not crash the SSE handler.
                // Banner was already updated above, so connection status is always accurate.
                console.warn('Dashboard UI update error (non-fatal):', uiErr);
            }
        }

        // EDGE-3: Enhanced status dot with three states
        function setStatusDot(id, ok) {
            const el = document.getElementById(id);
            if (!el) return;
            el.classList.toggle('ok', ok);
            el.classList.remove('warning');
        }

        // EDGE-STATUS-1: Cloud status dot using cloud_detail
        // GREEN: healthy, YELLOW: event_not_live / not_configured, RED: unreachable / auth_rejected
        function setCloudStatusDot(id, detail, connected) {
            const el = document.getElementById(id);
            if (!el) return;
            el.classList.remove('ok', 'warning');
            if (detail === 'healthy') {
                el.classList.add('ok');
                el.title = 'Cloud connected, event live';
            } else if (detail === 'event_not_live') {
                el.classList.add('warning');
                el.title = 'Cloud connected, no active event';
            } else if (detail === 'not_configured') {
                el.classList.add('warning');
                el.title = 'Cloud URL not configured';
            } else if (detail === 'auth_rejected') {
                el.title = 'Cloud auth rejected \u2014 check truck token';
            } else {
                // unreachable or unknown
                el.title = 'Cloud unreachable';
            }
        }

        // EDGE-STATUS-1: Tri-state status dot with boot window awareness
        // GREEN: connected + data flowing
        // YELLOW: present but waiting, or still within boot window (120s)
        // RED: offline / missing after boot window
        const BOOT_WINDOW_MS = 120000;
        function setDeviceStatusDot(id, deviceStatus, dataOk, bootTsMs) {
            const el = document.getElementById(id);
            if (!el) return;
            el.classList.remove('ok', 'warning');
            const now = Date.now();
            const inBootWindow = bootTsMs && (now - bootTsMs) < BOOT_WINDOW_MS;
            if (deviceStatus === 'connected' && dataOk) {
                el.classList.add('ok');
                el.title = 'Hardware connected, data flowing';
            } else if (deviceStatus === 'connected') {
                el.classList.add('warning');
                el.title = 'Hardware connected, waiting for data';
            } else if (deviceStatus === 'simulated') {
                el.classList.add('warning');
                el.title = 'Running in simulation mode (no hardware)';
            } else if (deviceStatus === 'timeout') {
                el.classList.add('warning');
                el.title = 'Hardware connected but data timed out';
            } else if (deviceStatus === 'missing') {
                el.classList.add('warning');
                el.title = 'Hardware not detected';
            } else if (deviceStatus === 'unknown' && inBootWindow) {
                el.classList.add('warning');
                el.title = 'Starting up\u2026 waiting for hardware detection';
            } else {
                // unknown after boot window or unexpected status → RED
                el.title = 'Hardware not responding';
            }
        }

        function setGaugeState(id, state) {
            const el = document.getElementById(id);
            el.classList.remove('warning', 'danger', 'success');
            if (state) el.classList.add(state);
        }

        // PIT-CAN-1: Only show alerts when CAN data is valid (not null)
        function checkAlerts(data, coolantF) {
            let alertMsg = null;
            const oilTempF = (data.oil_temp !== null && data.oil_temp !== undefined) ? data.oil_temp * 1.8 + 32 : null;

            // CRITICAL alerts (highest priority) - only check if data is valid
            if (coolantF !== null && coolantF > 240) alertMsg = 'CRITICAL: OVERHEATING - ' + Math.round(coolantF) + '°F';
            else if (data.oil_pressure !== null && data.oil_pressure !== undefined && data.oil_pressure < 15) alertMsg = 'CRITICAL: LOW OIL PRESSURE - ' + Math.round(data.oil_pressure) + ' PSI';
            else if (data.battery_voltage !== null && data.battery_voltage !== undefined && data.battery_voltage < 10.5) alertMsg = 'CRITICAL: BATTERY FAILING - ' + data.battery_voltage.toFixed(1) + 'V';

            // HIGH alerts
            else if (data.fuel_level_pct !== null && data.fuel_level_pct !== undefined && data.fuel_level_pct < 5) alertMsg = 'ALERT: FUEL CRITICAL - ' + Math.round(data.fuel_level_pct) + '%';
            else if (oilTempF !== null && oilTempF > 290) alertMsg = 'ALERT: OIL TOO HOT - ' + Math.round(oilTempF) + '°F';
            else if ((data.heart_rate || 0) > 180) alertMsg = 'ALERT: HIGH HEART RATE - ' + data.heart_rate + ' BPM';

            // WARNING alerts (lower priority)
            else if (data.fuel_level_pct !== null && data.fuel_level_pct !== undefined && data.fuel_level_pct < 15) alertMsg = 'WARNING: LOW FUEL - ' + Math.round(data.fuel_level_pct) + '%';
            else if (data.battery_voltage !== null && data.battery_voltage !== undefined && data.battery_voltage < 11.5) alertMsg = 'WARNING: LOW BATTERY - ' + data.battery_voltage.toFixed(1) + 'V';
            else if ((data.satellites || 0) === 0 && data.speed_mph > 10) alertMsg = 'WARNING: GPS SIGNAL LOST';
            else if (coolantF !== null && coolantF > 225) alertMsg = 'WARNING: ENGINE GETTING HOT - ' + Math.round(coolantF) + '°F';

            if (alertMsg) {
                showAlert(alertMsg);
            } else {
                hideAlert();
            }
        }

        // Voice alerts state
        let voiceAlertsEnabled = true;
        let lastVoiceAlert = '';
        let lastVoiceAlertTime = 0;
        const VOICE_ALERT_COOLDOWN = 10000; // 10 seconds between same alerts

        function showAlert(msg) {
            document.getElementById('alertText').textContent = msg;
            document.getElementById('alertsBanner').classList.add('active');
            alertActive = true;

            // Speak the alert if voice alerts are enabled
            if (voiceAlertsEnabled && msg !== lastVoiceAlert) {
                const now = Date.now();
                if (now - lastVoiceAlertTime > VOICE_ALERT_COOLDOWN) {
                    speakAlert(msg);
                    lastVoiceAlert = msg;
                    lastVoiceAlertTime = now;
                }
            }
        }

        function hideAlert() {
            document.getElementById('alertsBanner').classList.remove('active');
            alertActive = false;
        }

        function speakAlert(text) {
            if ('speechSynthesis' in window) {
                // Cancel any ongoing speech
                speechSynthesis.cancel();

                // Clean up the message for speech
                const cleanText = text
                    .replace(/CRITICAL:/g, 'Critical alert.')
                    .replace(/ALERT:/g, 'Alert.')
                    .replace(/WARNING:/g, 'Warning.')
                    .replace(/°F/g, ' degrees Fahrenheit')
                    .replace(/PSI/g, ' P S I')
                    .replace(/BPM/g, ' beats per minute');

                const utterance = new SpeechSynthesisUtterance(cleanText);
                utterance.rate = 1.1;
                utterance.pitch = 1.0;
                utterance.volume = 1.0;

                // Try to use a clear voice
                const voices = speechSynthesis.getVoices();
                const englishVoice = voices.find(v => v.lang.startsWith('en') && v.name.includes('Enhanced'));
                if (englishVoice) {
                    utterance.voice = englishVoice;
                }

                speechSynthesis.speak(utterance);
            }
        }

        function toggleVoiceAlerts() {
            voiceAlertsEnabled = !voiceAlertsEnabled;
            const btn = document.getElementById('voiceAlertBtn');
            if (btn) {
                btn.textContent = voiceAlertsEnabled ? 'Voice ON' : 'Voice OFF';
                btn.classList.toggle('active', voiceAlertsEnabled);
            }
            // Test speak
            if (voiceAlertsEnabled) {
                speakAlert('Voice alerts enabled');
            }
        }

        // ============ Camera Status & Screenshots (Feature 1: Stream Control) ============
        let screenshotData = {};
        let screenshotRefreshInterval = null;

        function updateCameraDisplay() {
            ['main', 'cockpit', 'chase', 'suspension'].forEach(cam => {
                const isLive = streamingStatus.status === 'live' && streamingStatus.camera === cam;
                const camData = screenshotData[cam] || {};
                const status = camData.status || cameraStatus[cam] || 'offline';
                const isOnline = status === 'online';

                // Update screenshot card
                const card = document.getElementById('screenshot-' + cam);
                if (card) {
                    card.classList.toggle('live', isLive);
                }

                // Update status badge
                const badge = document.getElementById(cam + '-badge');
                if (badge) {
                    badge.textContent = isLive ? 'LIVE' : (isOnline ? 'Online' : status);
                    badge.className = 'screenshot-status-badge ' + (isLive ? 'online' : status);
                }

                // Update live badge
                const liveBadge = document.getElementById(cam + '-live-badge');
                if (liveBadge) {
                    liveBadge.style.display = isLive ? 'inline-block' : 'none';
                }

                // Update screenshot image
                const img = document.getElementById('screenshot-img-' + cam);
                const placeholder = document.getElementById('placeholder-' + cam);
                if (img && camData.has_screenshot) {
                    // Add cache-busting timestamp to force refresh
                    const ts = camData.last_capture_ms || Date.now();
                    img.src = '/api/cameras/preview/' + cam + '.jpg?t=' + ts;
                    img.style.display = 'block';
                    if (placeholder) placeholder.style.display = 'none';
                } else if (img) {
                    img.style.display = 'none';
                    if (placeholder) placeholder.style.display = 'flex';
                }

                // Update resolution
                const resEl = document.getElementById(cam + '-resolution');
                if (resEl) {
                    resEl.textContent = camData.resolution || '--';
                }

                // Update age
                const ageEl = document.getElementById(cam + '-age');
                if (ageEl && camData.age_ms !== null) {
                    const ageSec = Math.floor(camData.age_ms / 1000);
                    if (ageSec < 60) {
                        ageEl.textContent = ageSec + 's ago';
                    } else {
                        ageEl.textContent = Math.floor(ageSec / 60) + 'm ago';
                    }
                    ageEl.style.color = camData.is_stale ? 'var(--warning)' : 'var(--text-muted)';
                } else if (ageEl) {
                    ageEl.textContent = '--';
                }
            });

        }

        // Poll screenshot status
        async function pollScreenshotStatus() {
            try {
                const resp = await fetch('/api/cameras/screenshots/status');
                if (resp.ok) {
                    const data = await resp.json();
                    screenshotData = data.cameras || {};

                    // Update loop status indicator
                    const loopStatus = document.getElementById('screenshotLoopStatus');
                    if (loopStatus) {
                        loopStatus.classList.toggle('ok', data.capture_in_progress || Object.values(screenshotData).some(c => c.has_screenshot));
                    }

                    // Update last capture time
                    const lastTimeEl = document.getElementById('lastScreenshotTime');
                    if (lastTimeEl) {
                        const times = Object.values(screenshotData).map(c => c.last_capture_ms).filter(t => t > 0);
                        if (times.length > 0) {
                            const latest = Math.max(...times);
                            lastTimeEl.textContent = new Date(latest).toLocaleTimeString();
                        }
                    }

                    // Update camera status from screenshot data
                    Object.entries(screenshotData).forEach(([cam, data]) => {
                        cameraStatus[cam] = data.status;
                    });

                    updateCameraDisplay();
                }
            } catch (e) {
                console.log('Screenshot status poll failed:', e);
            }
        }

        // Refresh all screenshots manually
        async function refreshAllScreenshots() {
            const btn = document.getElementById('refreshScreenshotsBtn');
            btn.disabled = true;
            btn.textContent = 'Capturing...';

            for (const cam of ['main', 'cockpit', 'chase', 'suspension']) {
                await captureScreenshot(cam, true);
            }

            btn.disabled = false;
            btn.textContent = 'Refresh';
            await pollScreenshotStatus();
        }

        // Capture single screenshot
        async function captureScreenshot(camera, silent = false) {
            try {
                const resp = await fetch('/api/cameras/preview/' + camera + '/capture', { method: 'POST' });
                if (resp.ok && !silent) {
                    const data = await resp.json();
                    if (data.success) {
                        showAlert(camera + ' captured', 'success');
                    }
                }
                // Refresh status after capture
                await pollScreenshotStatus();
            } catch (e) {
                if (!silent) {
                    showAlert('Capture failed: ' + e.message, 'warning');
                }
            }
        }

        // Enlarge screenshot in modal
        function enlargeScreenshot(camera) {
            const camData = screenshotData[camera] || {};
            if (!camData.has_screenshot) return;

            const modal = document.getElementById('screenshotModal');
            const img = document.getElementById('screenshotModalImg');
            const title = document.getElementById('screenshotModalTitle');
            const time = document.getElementById('screenshotModalTime');

            img.src = '/api/cameras/preview/' + camera + '.jpg?t=' + Date.now();
            title.textContent = camera.charAt(0).toUpperCase() + camera.slice(1) + ' Camera';
            time.textContent = camData.last_capture_ms ? new Date(camData.last_capture_ms).toLocaleString() : '--';
            modal.classList.add('active');
        }

        function closeScreenshotModal() {
            document.getElementById('screenshotModal').classList.remove('active');
        }

        // Initialize screenshot polling
        setInterval(pollScreenshotStatus, 10000); // Poll every 10 seconds
        pollScreenshotStatus(); // Initial poll

        // Also poll legacy camera status for production camera info
        async function pollCameraStatus() {
            try {
                const resp = await fetch('/api/cameras/status');
                if (resp.ok) {
                    const data = await resp.json();
                    if (data.cameras) {
                        Object.assign(cameraStatus, data.cameras);
                    }
                    updateCameraDisplay();
                }
            } catch (e) { console.log('Camera status poll failed'); }
        }
        setInterval(pollCameraStatus, 5000);
        pollCameraStatus();

        // ============ Streaming Control ============
        let streamingStatus = { status: 'idle', camera: 'main' };
        // Track user's manual dropdown selection — preserved when idle
        let userSelectedCamera = null;

        async function pollStreamingStatus() {
            // EDGE-PROG-3: Use Program State as authoritative source
            try {
                const resp = await fetch('/api/program/status');
                if (resp.ok) {
                    const progState = await resp.json();
                    // Map program_state fields to streaming UI expectations
                    streamingStatus = {
                        status: progState.streaming ? 'live' : (progState.last_error ? 'error' : 'idle'),
                        camera: progState.active_camera,
                        started_at: progState.last_stream_start_at,
                        error: progState.last_error,
                        youtube_configured: progState.youtube_configured,
                        youtube_url: progState.youtube_url,
                        stream_profile: progState.stream_profile,
                        supervisor: progState.supervisor_state ? { state: progState.supervisor_state } : null,
                    };
                    updateStreamingUI();
                }
            } catch (e) { console.log('Program status poll failed:', e); }
        }

        function updateStreamingUI() {
            const badge = document.getElementById('streamStatusBadge');
            const startBtn = document.getElementById('startStreamBtn');
            const stopBtn = document.getElementById('stopStreamBtn');
            const cameraSelect = document.getElementById('streamCameraSelect');
            const errorSpan = document.getElementById('streamError');
            const infoDiv = document.getElementById('streamInfo');
            const activeCamera = document.getElementById('activeStreamCamera');
            const uptime = document.getElementById('streamUptime');

            // Update badge
            badge.className = 'stream-status-badge ' + streamingStatus.status;
            badge.textContent = streamingStatus.status.toUpperCase();

            // Show/hide buttons based on status
            if (streamingStatus.status === 'live' || streamingStatus.status === 'starting') {
                startBtn.style.display = 'none';
                stopBtn.style.display = 'inline-block';
                cameraSelect.disabled = false;
                infoDiv.style.display = 'block';
                activeCamera.textContent = streamingStatus.camera || '--';

                // Calculate uptime
                if (streamingStatus.started_at) {
                    const uptimeMs = Date.now() - streamingStatus.started_at;
                    const mins = Math.floor(uptimeMs / 60000);
                    const secs = Math.floor((uptimeMs % 60000) / 1000);
                    uptime.textContent = mins + 'm ' + secs + 's';
                } else {
                    uptime.textContent = '--';
                }
            } else {
                startBtn.style.display = 'inline-block';
                stopBtn.style.display = 'none';
                cameraSelect.disabled = false;
                infoDiv.style.display = 'none';
            }

            // EDGE-6: Show supervisor state if available
            const sv = streamingStatus.supervisor;
            if (sv) {
                const svState = sv.state || 'unknown';
                if (svState === 'paused' || svState === 'retrying' || svState === 'error') {
                    badge.className = 'stream-status-badge error';
                    let label = svState.toUpperCase();
                    if (svState === 'retrying' && sv.backoff_delay_s) {
                        label += ' (' + sv.backoff_delay_s + 's)';
                    }
                    if (svState === 'paused') {
                        label = 'PAUSED';
                        badge.className = 'stream-status-badge warning';
                    }
                    badge.textContent = label;
                } else if (svState === 'active') {
                    badge.className = 'stream-status-badge live';
                    badge.textContent = 'ACTIVE';
                }
                if (sv.total_restarts > 0) {
                    const restartInfo = document.getElementById('streamRestarts');
                    if (restartInfo) {
                        restartInfo.textContent = sv.restart_count + ' consecutive / ' + sv.total_restarts + ' total';
                        restartInfo.style.display = 'inline';
                    }
                }
            }

            // STREAM-1: Show error in prominent banner if any
            if (streamingStatus.error && streamingStatus.status === 'error') {
                showStreamError(streamingStatus.error);
            } else if (sv && sv.last_error && (sv.state === 'paused' || sv.state === 'error')) {
                // EDGE-6: Show supervisor error
                showStreamError(sv.last_error.substring(0, 120));
            } else {
                hideStreamError();
            }

            // Update camera select to match current streaming camera only when
            // actively streaming. When idle, preserve the user's manual selection.
            const switchBtn = document.getElementById('switchStreamBtn');
            if (streamingStatus.status === 'live' || streamingStatus.status === 'starting') {
                // Sync dropdown to the actual streaming camera
                if (streamingStatus.camera) {
                    cameraSelect.value = streamingStatus.camera;
                }
                // Show switch button when streaming and dropdown differs from active camera
                if (switchBtn) {
                    switchBtn.style.display = (cameraSelect.value !== streamingStatus.camera) ? 'inline-block' : 'none';
                }
            } else {
                // Idle/error: restore user's previous selection if they made one
                if (userSelectedCamera) {
                    cameraSelect.value = userSelectedCamera;
                }
                if (switchBtn) switchBtn.style.display = 'none';
            }

            // LINK-3: Check YouTube configuration — show visible warning, not just tooltip
            const configWarning = document.getElementById('streamConfigWarning');
            if (!streamingStatus.youtube_configured) {
                startBtn.disabled = true;
                startBtn.title = 'Configure YouTube stream key in Settings first';
                if (configWarning) configWarning.style.display = 'inline';
            } else {
                startBtn.disabled = false;
                startBtn.title = '';
                if (configWarning) configWarning.style.display = 'none';
            }

            // Update YouTube URL in Stream Info section
            const youtubeUrlEl = document.getElementById('youtubeUrl');
            if (youtubeUrlEl && streamingStatus.youtube_url) {
                youtubeUrlEl.href = streamingStatus.youtube_url;
                youtubeUrlEl.textContent = streamingStatus.youtube_url;
            }

            // Refresh camera LIVE badges based on streaming state
            updateCameraDisplay();
        }

        // STREAM-1/STREAM-2: Show streaming error banner with actionable guidance.
        // Accepts errorMsg (string) and optional errorCode from structured API response.
        function showStreamError(errorMsg, errorCode) {
            const banner = document.getElementById('streamErrorBanner');
            const msgEl = document.getElementById('streamErrorMsg');
            const actionEl = document.getElementById('streamErrorAction');
            const errorSpan = document.getElementById('streamError');
            if (!banner) return;

            msgEl.textContent = errorMsg;

            // STREAM-2: Match on error_code first (structured), fall back to string matching
            var action = '';
            var code = (errorCode || '').toUpperCase();
            if (code === 'MISSING_YOUTUBE_KEY') {
                action = '<a href="#" data-click="switchToTab" data-arg="settings">Go to Settings</a> and enter your YouTube stream key.';
            } else if (code === 'CAMERA_NOT_FOUND') {
                action = '<a href="#" data-click="switchToTab" data-arg="devices">Go to Devices</a> and run a device scan. Check USB camera connections.';
            } else if (code === 'FFMPEG_MISSING') {
                action = 'Run on the edge host: <code style="background:var(--bg-tertiary);padding:2px 6px;border-radius:4px;">sudo apt install -y ffmpeg</code>';
            } else if (code === 'FFMPEG_EXITED') {
                action = 'Check that the YouTube stream key is valid and the camera device has correct permissions.';
            } else if (code === 'ALREADY_STREAMING') {
                action = 'A stream is already running. Stop it first, then start a new one.';
            } else {
                // Fallback: string matching for legacy/unstructured errors
                var errLower = errorMsg.toLowerCase();
                if (errLower.includes('stream key') || errLower.includes('youtube')) {
                    action = '<a href="#" data-click="switchToTab" data-arg="settings">Go to Settings</a> and enter your YouTube stream key.';
                } else if (errLower.includes('camera') && errLower.includes('not found')) {
                    action = '<a href="#" data-click="switchToTab" data-arg="devices">Go to Devices</a> and run a device scan. Check USB camera connections.';
                } else if (errLower.includes('ffmpeg not installed')) {
                    action = 'Run on the edge host: <code style="background:var(--bg-tertiary);padding:2px 6px;border-radius:4px;">sudo apt install -y ffmpeg</code>';
                } else if (errLower.includes('ffmpeg') || errLower.includes('exited')) {
                    action = 'Check that the YouTube stream key is valid and the camera device has correct permissions.';
                } else if (errLower.includes('already streaming')) {
                    action = 'A stream is already running. Stop it first, then start a new one.';
                }
            }
            actionEl.innerHTML = action;

            banner.style.display = 'block';

            // Also update the inline error span for consistency
            if (errorSpan) {
                errorSpan.textContent = errorMsg;
                errorSpan.style.display = 'inline';
            }
        }

        function hideStreamError() {
            var banner = document.getElementById('streamErrorBanner');
            var errorSpan = document.getElementById('streamError');
            if (banner) banner.style.display = 'none';
            if (errorSpan) { errorSpan.style.display = 'none'; errorSpan.textContent = ''; }
        }

        // STREAM-1: Helper to switch tabs (used by actionable links in error banner)
        function switchToTab(tabName) {
            var tabBtn = document.querySelector('[data-tab="' + tabName + '"]');
            if (tabBtn) tabBtn.click();
        }

        async function startStream() {
            const camera = document.getElementById('streamCameraSelect').value;
            const startBtn = document.getElementById('startStreamBtn');

            startBtn.disabled = true;
            startBtn.textContent = 'Starting...';
            hideStreamError();

            // STREAM-1: Preflight gate — check streaming status before calling start
            try {
                const preResp = await fetch('/api/streaming/status');
                if (preResp.ok) {
                    const preData = await preResp.json();
                    if (preData.youtube_configured === false) {
                        showStreamError('No YouTube stream key configured. Set it in Settings.');
                        showAlert('Stream key missing — configure in Settings', 'warning');
                        startBtn.disabled = false;
                        startBtn.textContent = 'Start Stream';
                        return;
                    }
                }
            } catch (e) {
                // Preflight failed — continue to start and let backend validate
                console.warn('STREAM-1: Preflight check failed, continuing:', e);
            }

            try {
                const resp = await fetch('/api/streaming/start', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ camera: camera })
                });
                const data = await resp.json();

                if (!data.success) {
                    showStreamError(data.error || data.message || 'Unknown error', data.error_code);
                    showAlert('Stream failed — see details below', 'error');
                } else {
                    hideStreamError();
                    showAlert('Stream started on ' + camera, 'success');
                }
            } catch (e) {
                showStreamError('Network error: ' + e.message);
                showAlert('Failed to start stream', 'error');
            }

            startBtn.disabled = false;
            startBtn.textContent = 'Start Stream';
            await pollStreamingStatus();
        }

        async function stopStream() {
            const stopBtn = document.getElementById('stopStreamBtn');

            stopBtn.disabled = true;
            stopBtn.textContent = 'Stopping...';

            try {
                const resp = await fetch('/api/streaming/stop', { method: 'POST' });
                const data = await resp.json();

                if (data.success) {
                    showAlert('Stream stopped', 'success');
                } else {
                    showAlert('Stop failed: ' + data.error, 'warning');
                }
            } catch (e) {
                showAlert('Failed to stop stream: ' + e.message, 'warning');
            }

            stopBtn.disabled = false;
            stopBtn.textContent = 'Stop Stream';
            await pollStreamingStatus();
        }

        async function handleCameraSelectChange(camera) {
            // Track the user's selection so polling doesn't overwrite it
            userSelectedCamera = camera;

            // Show/hide switch button when streaming and selection differs
            const switchBtn = document.getElementById('switchStreamBtn');
            if (streamingStatus.status === 'live' || streamingStatus.status === 'starting') {
                if (switchBtn) {
                    switchBtn.style.display = (camera !== streamingStatus.camera) ? 'inline-block' : 'none';
                }
            }
            // Don't auto-switch on dropdown change — user clicks Switch Camera button
        }

        async function switchStream() {
            const camera = document.getElementById('streamCameraSelect').value;
            const switchBtn = document.getElementById('switchStreamBtn');

            if (!(streamingStatus.status === 'live' || streamingStatus.status === 'starting')) {
                showAlert('Not currently streaming — use Start Stream instead', 'warning');
                return;
            }

            if (camera === streamingStatus.camera) {
                showAlert('Already streaming on ' + camera, 'success');
                return;
            }

            switchBtn.disabled = true;
            switchBtn.textContent = 'Switching...';
            hideStreamError();

            try {
                const resp = await fetch('/api/streaming/switch-camera', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ camera: camera })
                });
                const data = await resp.json();
                if (data.success) {
                    hideStreamError();
                    showAlert('Switched to ' + camera, 'success');
                    userSelectedCamera = null; // Clear — now synced with server
                } else {
                    showStreamError(data.error || data.message || 'Switch failed', data.error_code);
                    showAlert('Camera switch failed — see details below', 'error');
                }
            } catch (e) {
                showStreamError('Network error: ' + e.message);
                showAlert('Failed to switch camera', 'error');
            }

            switchBtn.disabled = false;
            switchBtn.textContent = 'Switch Camera';
            await pollStreamingStatus();
        }

        // Poll streaming status every 3 seconds
        setInterval(pollStreamingStatus, 3000);
        pollStreamingStatus();

        // ============ STREAM-2: Stream Quality Control ============
        const PROFILE_LABELS = {
            '1080p30': '1080p @ 4500k',
            '720p30': '720p @ 2500k',
            '480p30': '480p @ 1200k',
            '360p30': '360p @ 800k',
        };
        let currentProfileState = { current: '1080p30', auto_mode: false };

        function updateQualityStatusUI(profileId, timestamp) {
            const statusDiv = document.getElementById('streamQualityStatus');
            const label = document.getElementById('streamQualityLabel');
            const timeSpan = document.getElementById('streamQualityTime');
            if (!statusDiv || !label) return;
            statusDiv.style.display = 'block';
            label.textContent = PROFILE_LABELS[profileId] || profileId;
            if (timestamp) {
                const d = new Date(timestamp);
                timeSpan.textContent = d.toLocaleTimeString();
            } else {
                timeSpan.textContent = '--';
            }
        }

        async function loadStreamProfile() {
            try {
                const resp = await fetch('/api/stream/profile');
                if (resp.ok) {
                    const data = await resp.json();
                    currentProfileState = data;
                    const sel = document.getElementById('streamProfileSelect');
                    const autoTgl = document.getElementById('streamAutoToggle');
                    if (sel) sel.value = data.current;
                    if (autoTgl) autoTgl.checked = data.auto_mode || false;
                    updateQualityStatusUI(data.current, null);
                }
            } catch (e) { console.log('Profile load failed:', e); }
        }
        loadStreamProfile();

        async function handleProfileChange(profile) {
            const sel = document.getElementById('streamProfileSelect');
            const prev = currentProfileState.current;
            sel.disabled = true;
            try {
                const resp = await fetch('/api/stream/profile', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ profile: profile })
                });
                const data = await resp.json();
                if (data.success) {
                    currentProfileState.current = profile;
                    currentProfileState.auto_mode = false;
                    const autoTgl = document.getElementById('streamAutoToggle');
                    if (autoTgl) autoTgl.checked = false;
                    updateQualityStatusUI(profile, data.applied_at);
                    showAlert('Quality: ' + (PROFILE_LABELS[profile] || profile) + (data.restarted ? ' (stream restarted)' : ''), 'success');
                } else {
                    sel.value = prev;
                    showAlert('Quality change failed: ' + (data.error || 'unknown'), 'warning');
                }
            } catch (e) {
                sel.value = prev;
                showAlert('Failed to change quality: ' + e.message, 'warning');
            }
            sel.disabled = false;
            await pollStreamingStatus();
        }

        async function handleAutoToggle(enabled) {
            const autoTgl = document.getElementById('streamAutoToggle');
            try {
                const resp = await fetch('/api/stream/auto', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ enabled: enabled })
                });
                const data = await resp.json();
                if (data.success) {
                    currentProfileState.auto_mode = enabled;
                    showAlert('Auto quality ' + (enabled ? 'enabled' : 'disabled'), 'success');
                } else {
                    autoTgl.checked = !enabled;
                    showAlert('Auto toggle failed: ' + (data.error || 'unknown'), 'warning');
                }
            } catch (e) {
                autoTgl.checked = !enabled;
                showAlert('Auto toggle failed: ' + e.message, 'warning');
            }
        }

        // ============ Audio Level ============
        async function pollAudioLevel() {
            try {
                const resp = await fetch('/api/audio/level');
                if (resp.ok) {
                    const data = await resp.json();
                    const pct = Math.min(100, Math.max(0, (data.level + 60) * (100/60)));
                    document.getElementById('audioLevel').style.width = pct + '%';
                    // EDGE-STATUS-1: Audio tri-state: GREEN if signal, YELLOW if system up but quiet
                    const audioEl = document.getElementById('audioStatus');
                    if (audioEl) {
                        audioEl.classList.remove('ok', 'warning');
                        if (data.level > -50) {
                            audioEl.classList.add('ok');
                            audioEl.title = 'Audio detected';
                        } else {
                            audioEl.classList.add('warning');
                            audioEl.title = 'Audio system running, no signal';
                        }
                    }
                    if (data.last_activity) {
                        const ago = Math.floor((Date.now() - data.last_activity) / 1000);
                        document.getElementById('lastHeard').textContent = ago < 60 ? ago + 's ago' : Math.floor(ago/60) + 'm ago';
                    }
                }
            } catch (e) {}
        }
        setInterval(pollAudioLevel, 1000);

        // ============ EDGE-4: Edge Readiness Status ============
        async function pollEdgeStatus() {
            try {
                const resp = await fetch('/api/edge/status');
                if (resp.ok) {
                    const data = await resp.json();
                    const dot = document.getElementById('edgeReadiness');
                    const label = document.getElementById('edgeReadinessLabel');
                    if (!dot) return;

                    dot.classList.remove('ok', 'warning');
                    if (data.status === 'OPERATIONAL') {
                        dot.classList.add('ok');
                        dot.title = 'Edge: OPERATIONAL — All Tier 1 systems green';
                        label.textContent = 'Edge';
                    } else if (data.status === 'DEGRADED') {
                        dot.classList.add('warning');
                        dot.title = 'Edge: DEGRADED — Tier 1 OK, Tier 2 partial';
                        label.textContent = 'Edge';
                    } else {
                        // DOWN or UNKNOWN
                        dot.title = 'Edge: ' + (data.status || 'UNKNOWN') + ' — Tier 1 issues detected';
                        label.textContent = 'Edge';
                    }

                    // Show boot timing in tooltip if available
                    if (data.boot_timing && data.boot_timing.time_to_operational_sec >= 0) {
                        dot.title += ' | Boot: ' + data.boot_timing.time_to_operational_sec + 's to operational';
                    }

                    // EDGE-5: Show disk and queue info in tooltip
                    if (data.disk_pct !== undefined) {
                        dot.title += ' | Disk: ' + data.disk_pct + '%';
                        if (data.disk_pct >= 95) dot.title += ' CRITICAL';
                        else if (data.disk_pct >= 85) dot.title += ' HIGH';
                    }
                    if (data.queue_depth !== undefined) {
                        dot.title += ' | Queue: ' + data.queue_depth + ' (' + data.queue_mb + ' MB)';
                    }
                }
            } catch (e) {}
        }
        pollEdgeStatus();
        setInterval(pollEdgeStatus, 15000); // Poll every 15 seconds

        // ============ Pit Notes ============
        function sendQuickNote(note) {
            document.getElementById('pitNoteInput').value = note;
            sendPitNote();
        }

        async function sendPitNote() {
            const note = document.getElementById('pitNoteInput').value.trim();
            if (!note) return;

            const btn = document.querySelector('.send-note-btn');
            const originalText = btn.textContent;
            btn.textContent = 'Sending...';
            btn.disabled = true;

            try {
                const resp = await fetch('/api/pit-note', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ note: note, ts: Date.now() })
                });

                if (resp.ok) {
                    const data = await resp.json();
                    document.getElementById('pitNoteInput').value = '';
                    // PIT-COMMS-1: Show success with sync status
                    if (data.note && data.note.synced) {
                        btn.textContent = 'Sent!';
                        btn.style.background = 'var(--accent-green)';
                    } else {
                        // Note is queued locally, background sync will retry
                        btn.textContent = 'Queued (will sync)';
                        btn.style.background = 'var(--accent-yellow, #f59e0b)';
                    }
                    // Refresh history
                    loadPitNotesHistory();
                } else {
                    const errData = await resp.json().catch(() => ({}));
                    btn.textContent = 'Failed: ' + (errData.error || resp.statusText);
                    btn.style.background = 'var(--danger)';
                }

                setTimeout(() => {
                    btn.textContent = originalText;
                    btn.style.background = '';
                    btn.disabled = false;
                }, 2500);
            } catch (e) {
                console.error('Failed to send pit note', e);
                btn.textContent = 'Network Error';
                btn.style.background = 'var(--danger)';
                setTimeout(() => {
                    btn.textContent = originalText;
                    btn.style.background = '';
                    btn.disabled = false;
                }, 2500);
            }
        }

        async function loadPitNotesHistory() {
            try {
                const resp = await fetch('/api/pit-notes?limit=5');
                if (resp.ok) {
                    const data = await resp.json();
                    const historyEl = document.getElementById('pitNotesHistory');
                    if (!historyEl) return;

                    if (data.notes && data.notes.length > 0) {
                        historyEl.innerHTML = data.notes.map(n => {
                            const time = new Date(n.timestamp).toLocaleTimeString();
                            const syncIcon = n.synced ? 'Cloud' : 'Local';
                            return `<div class="pit-note-item">
                                <span class="pit-note-time">${time}</span>
                                <span class="pit-note-text">${escapeHtml(n.text)}</span>
                                <span class="pit-note-sync" title="${n.synced ? 'Synced to cloud' : 'Saved locally'}">${syncIcon}</span>
                            </div>`;
                        }).join('');
                    } else {
                        historyEl.innerHTML = '<div class="pit-note-empty">No notes yet</div>';
                    }
                }
            } catch (e) {
                console.error('Failed to load pit notes history', e);
            }
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        // PIT-COMMS-1: Load and display sync status
        async function loadPitNotesSyncStatus() {
            try {
                const resp = await fetch('/api/pit-notes/sync-status');
                if (resp.ok) {
                    const data = await resp.json();
                    const cloudEl = document.getElementById('pitNotesCloudStatus');
                    const queueEl = document.getElementById('pitNotesQueueCount');

                    if (cloudEl) {
                        if (data.waiting_for_event) {
                            cloudEl.innerHTML = 'Cloud: <span style="color:var(--accent-yellow);">Waiting for event assignment</span>';
                        } else if (data.cloud_connected) {
                            cloudEl.innerHTML = 'Cloud: <span style="color:var(--accent-green);">Connected</span>';
                        } else if (data.cloud_configured) {
                            cloudEl.innerHTML = 'Cloud: <span style="color:var(--accent-yellow);">Disconnected</span>';
                        } else {
                            cloudEl.innerHTML = 'Cloud: <span style="color:var(--text-muted);">Not configured</span>';
                        }
                    }
                    if (queueEl) {
                        if (data.queued > 0) {
                            queueEl.innerHTML = `Queued: <span style="color:var(--accent-yellow);">${data.queued}</span>`;
                        } else {
                            queueEl.textContent = 'Queued: 0';
                        }
                    }
                }
            } catch (e) {
                console.error('Failed to load pit notes sync status', e);
            }
        }

        // Load notes history and sync status on page load
        document.addEventListener('DOMContentLoaded', () => {
            loadPitNotesHistory();
            loadPitNotesSyncStatus();
            // Poll sync status every 10 seconds
            setInterval(loadPitNotesSyncStatus, 10000);
        });

        // ============ P1: Fuel Strategy ============
        let fuelConfigVisible = false;

        function toggleFuelConfig() {
            fuelConfigVisible = !fuelConfigVisible;
            document.getElementById('fuelConfigPanel').style.display = fuelConfigVisible ? 'block' : 'none';
        }

        async function promptFuelLevel() {
            // PIT-FUEL-0: Get tank capacity from API (single source of truth)
            let currentFuel = '--';
            let tankCapacity = null;
            const MAX_CAPACITY = 250;  // PIT-FUEL-0: Must match MAX_TANK_CAPACITY_GAL
            try {
                const resp = await fetch('/api/fuel/status');
                if (resp.ok) {
                    const data = await resp.json();
                    tankCapacity = data.tank_capacity_gal;
                    if (data.fuel_set && data.current_fuel_gal !== null) {
                        currentFuel = data.current_fuel_gal.toFixed(1);
                    }
                }
            } catch (e) {
                console.error('Failed to get current fuel level', e);
            }

            if (tankCapacity === null || tankCapacity === undefined) {
                showAlert('Could not load tank capacity. Please refresh the page.', 'error');
                return;
            }

            // PIT-FUEL-0: Prompt shows max possible range (250), not just current tank capacity.
            // This prevents the hidden "change config first" workflow.
            const input = prompt(
                `Enter current fuel level in gallons (0 - ${MAX_CAPACITY}).\nCurrent tank capacity: ${tankCapacity} gal (auto-adjusts if needed).`,
                currentFuel === '--' ? '' : currentFuel
            );

            if (input === null) return; // Cancelled

            const fuelLevel = parseFloat(input);
            if (isNaN(fuelLevel)) {
                showAlert('Invalid fuel level', 'error');
                return;
            }
            if (fuelLevel < 0 || fuelLevel > MAX_CAPACITY) {
                showAlert(`Fuel must be between 0 and ${MAX_CAPACITY} gallons`, 'error');
                return;
            }

            // PIT-FUEL-0: If fuel level > current tank capacity, auto-expand capacity.
            // This eliminates the hidden two-step workflow that blocked values >95.
            const payload = { current_fuel_gal: fuelLevel };
            if (fuelLevel > tankCapacity) {
                payload.tank_capacity_gal = fuelLevel;
            }

            // Update fuel level (and capacity if needed)
            try {
                const resp = await fetch('/api/fuel/update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                if (resp.ok) {
                    let msg = `Fuel set to ${fuelLevel.toFixed(1)} gallons`;
                    if (fuelLevel > tankCapacity) {
                        msg += ` (tank capacity updated to ${fuelLevel} gal)`;
                    }
                    showAlert(msg, 'success');
                    loadFuelStatus();
                } else {
                    const err = await resp.json();
                    showAlert(err.error || 'Failed to update fuel', 'error');
                }
            } catch (e) {
                console.error('Failed to update fuel level', e);
                showAlert('Failed to update fuel level', 'error');
            }
        }

        async function saveFuelConfig() {
            const tankCapacity = parseFloat(document.getElementById('tankCapacityInput').value);
            const mpg = parseFloat(document.getElementById('fuelMpgInput').value);

            if (isNaN(tankCapacity) || tankCapacity < 1 || tankCapacity > 250) {
                showAlert('Tank capacity must be 1-250 gallons', 'error');
                return;
            }
            if (isNaN(mpg) || mpg < 0.1 || mpg > 30) {
                showAlert('MPG must be 0.1-30', 'error');
                return;
            }

            try {
                const resp = await fetch('/api/fuel/update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        tank_capacity_gal: tankCapacity,
                        consumption_rate_mpg: mpg
                    })
                });
                if (resp.ok) {
                    showAlert('Fuel configuration saved', 'success');
                    toggleFuelConfig(); // Close config panel
                    loadFuelStatus();
                } else {
                    const err = await resp.json();
                    showAlert(err.error || 'Failed to save config', 'error');
                }
            } catch (e) {
                console.error('Failed to save fuel config', e);
                showAlert('Failed to save configuration', 'error');
            }
        }

        async function recordFuelFill() {
            try {
                const resp = await fetch('/api/fuel/update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ filled: true })
                });
                if (resp.ok) {
                    showAlert('Fuel fill recorded - tank at capacity', 'success');
                    loadFuelStatus();
                }
            } catch (e) {
                console.error('Failed to record fuel fill', e);
            }
        }

        async function loadFuelStatus() {
            try {
                const resp = await fetch('/api/fuel/status');
                if (resp.ok) {
                    const data = await resp.json();

                    // PIT-FUEL-1: Update config inputs from API (single source of truth)
                    // No hardcoded fallbacks - backend always returns configured values
                    document.getElementById('tankCapacityInput').value = data.tank_capacity_gal;
                    document.getElementById('fuelMpgInput').value = data.consumption_rate_mpg;

                    // Check if fuel is set
                    if (!data.fuel_set || data.current_fuel_gal === null) {
                        // Fuel not set - show warning
                        document.getElementById('fuelUnsetWarning').style.display = 'block';
                        document.getElementById('fuelLevelBar').style.display = 'none';
                        document.getElementById('fuelRemaining').textContent = 'Unset';
                        document.getElementById('fuelUnit').style.display = 'none';
                        document.getElementById('fuelLapsRemaining').textContent = '--';

                        // PIT-1R: Still show trip miles and MPG even when fuel not set
                        document.getElementById('rangeMpgAvg').textContent =
                            data.consumption_rate_mpg ? data.consumption_rate_mpg.toFixed(1) : '--';
                        document.getElementById('rangeFuelRemaining').textContent = '--';
                        document.getElementById('rangeEstRemaining').textContent = '--';
                        document.getElementById('tripMilesValue').textContent =
                            data.trip_miles !== undefined ? data.trip_miles.toFixed(1) : '--';
                        if (data.trip_start_at && data.trip_start_at > 0) {
                            const tripDate = new Date(data.trip_start_at);
                            document.getElementById('tripStartTime').textContent = tripDate.toLocaleString();
                        } else {
                            document.getElementById('tripStartTime').textContent = '--';
                        }
                        return;
                    }

                    // Fuel is set - show values
                    document.getElementById('fuelUnsetWarning').style.display = 'none';
                    document.getElementById('fuelLevelBar').style.display = 'block';
                    document.getElementById('fuelUnit').style.display = 'inline';
                    document.getElementById('fuelRemaining').textContent = data.current_fuel_gal.toFixed(1);

                    // Use miles for point-to-point, laps for lap-based races
                    if (raceType === 'point_to_point') {
                        document.getElementById('fuelLapsRemaining').textContent =
                            data.estimated_miles_remaining !== null ? data.estimated_miles_remaining.toFixed(0) : '--';
                        document.getElementById('fuelRemainingLabel').textContent = 'Est. Miles Left';
                    } else {
                        // For lap-based, calculate laps from miles
                        const courseMiles = courseTotalDistance || 0;
                        const estimatedLaps = courseMiles > 0 && data.estimated_miles_remaining
                            ? Math.floor(data.estimated_miles_remaining / courseMiles)
                            : '--';
                        document.getElementById('fuelLapsRemaining').textContent = estimatedLaps;
                        document.getElementById('fuelRemainingLabel').textContent = 'Est. Laps Left';
                    }

                    // Update fuel level bar
                    const fuelPercent = data.fuel_percent || 0;
                    document.getElementById('fuelLevelFill').style.width = fuelPercent + '%';

                    // Color code the fuel level
                    const fill = document.getElementById('fuelLevelFill');
                    fill.classList.remove('fuel-critical', 'fuel-warning');
                    if (fuelPercent < 15) {
                        fill.classList.add('fuel-critical');
                    } else if (fuelPercent < 30) {
                        fill.classList.add('fuel-warning');
                    }

                    // PIT-1R: Update range & trip panel
                    document.getElementById('rangeMpgAvg').textContent =
                        data.consumption_rate_mpg ? data.consumption_rate_mpg.toFixed(1) : '--';
                    document.getElementById('rangeFuelRemaining').textContent =
                        data.current_fuel_gal !== null ? data.current_fuel_gal.toFixed(1) : '--';
                    document.getElementById('rangeEstRemaining').textContent =
                        data.range_miles_remaining !== null ? data.range_miles_remaining.toFixed(0) : '--';
                    document.getElementById('tripMilesValue').textContent =
                        data.trip_miles !== undefined ? data.trip_miles.toFixed(1) : '--';
                    if (data.trip_start_at && data.trip_start_at > 0) {
                        const tripDate = new Date(data.trip_start_at);
                        document.getElementById('tripStartTime').textContent = tripDate.toLocaleString();
                    } else {
                        document.getElementById('tripStartTime').textContent = '--';
                    }
                }
            } catch (e) {
                console.error('Failed to load fuel status', e);
            }
        }

        // ============ PIT-1R: Trip Reset ============
        async function resetTripMiles() {
            if (!confirm('Reset trip miles to 0?')) return;
            try {
                const resp = await fetch('/api/fuel/trip-reset', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({})
                });
                if (resp.ok) {
                    showAlert('Trip miles reset', 'success');
                    loadFuelStatus();
                }
            } catch (e) {
                console.error('Failed to reset trip', e);
                showAlert('Failed to reset trip miles', 'error');
            }
        }

        // ============ PIT-5R: Per-Axle Tire Tracking ============
        async function updateTireBrand(brand) {
            try {
                const resp = await fetch('/api/tires/update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ brand: brand })
                });
                if (resp.ok) {
                    showAlert(brand + ' selected', 'success');
                    loadTireStatus();
                }
            } catch (e) {
                console.error('Failed to update tire brand', e);
            }
        }

        async function resetTireAxle(axle) {
            try {
                const payload = {};
                if (axle === 'front') payload.reset_front = true;
                if (axle === 'rear') payload.reset_rear = true;
                const resp = await fetch('/api/tires/update', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                if (resp.ok) {
                    showAlert(axle.charAt(0).toUpperCase() + axle.slice(1) + ' tires reset', 'success');
                    loadTireStatus();
                }
            } catch (e) {
                console.error('Failed to reset ' + axle + ' tires', e);
            }
        }

        async function loadTireStatus() {
            try {
                const resp = await fetch('/api/tires/status');
                if (resp.ok) {
                    const data = await resp.json();
                    const brand = data.brand || 'Toyo';

                    // Update brand displays
                    document.getElementById('tireFrontBrand').textContent = brand;
                    document.getElementById('tireRearBrand').textContent = brand;

                    // Sync brand dropdown
                    const sel = document.getElementById('tireBrandSelect');
                    if (sel) sel.value = brand;

                    // Front miles
                    document.getElementById('tireFrontMiles').textContent =
                        (data.front_miles != null) ? data.front_miles.toFixed(1) : '0.0';

                    // Rear miles
                    document.getElementById('tireRearMiles').textContent =
                        (data.rear_miles != null) ? data.rear_miles.toFixed(1) : '0.0';

                    // Front last changed
                    const fcEl = document.getElementById('tireFrontChanged');
                    if (data.front_last_changed_at > 0) {
                        fcEl.textContent = new Date(data.front_last_changed_at).toLocaleString();
                    } else {
                        fcEl.textContent = 'Never';
                    }

                    // Rear last changed
                    const rcEl = document.getElementById('tireRearChanged');
                    if (data.rear_last_changed_at > 0) {
                        rcEl.textContent = new Date(data.rear_last_changed_at).toLocaleString();
                    } else {
                        rcEl.textContent = 'Never';
                    }
                }
            } catch (e) {
                console.error('Failed to load tire status', e);
            }
        }

        // ============ P1: Update Race Position ============
        function updateRacePosition(data) {
            // Update position display
            const pos = data.race_position || '--';
            const total = data.total_vehicles || '--';
            document.getElementById('racePosition').textContent = pos;
            document.getElementById('totalVehicles').textContent = total;

            // Update delta to leader
            const delta = data.delta_to_leader_ms || 0;
            if (delta > 0) {
                const secs = (delta / 1000).toFixed(1);
                document.getElementById('deltaValue').textContent = '+' + secs + 's';
            } else if (pos === 1) {
                document.getElementById('deltaValue').textContent = 'LEADING';
                document.getElementById('positionDisplay').classList.add('leading');
            } else {
                document.getElementById('deltaValue').textContent = '--';
                document.getElementById('positionDisplay').classList.remove('leading');
            }

            // PROGRESS-3: Miles remaining display
            const milesEl = document.getElementById('milesRemainingValue');
            if (data.miles_remaining != null) {
                milesEl.textContent = data.miles_remaining.toFixed(1) + ' mi remaining';
            } else {
                milesEl.textContent = '\u2014';
            }

            // Update lap number
            document.getElementById('lapNumber').textContent = data.lap_number || 0;
            document.getElementById('lastCheckpoint').textContent = data.last_checkpoint || '--';

            // PROGRESS-3: Update competitor tracking with real data
            updateCompetitors(data);
        }

        function showAlert(message, type) {
            const banner = document.getElementById('alertsBanner');
            const text = document.getElementById('alertText');
            text.textContent = message;
            if (type === 'success') {
                banner.style.background = 'var(--success)';
            } else if (type === 'warning') {
                banner.style.background = 'var(--warning)';
            } else {
                banner.style.background = 'var(--danger)';
            }
            banner.classList.add('visible');
            setTimeout(() => {
                banner.classList.remove('visible');
                banner.style.background = '';
            }, 3000);
        }

        // Load fuel and tire status periodically
        setInterval(() => {
            loadFuelStatus();
            loadTireStatus();
        }, 10000);

        // ============ P2: Pit Stop Timer ============
        let pitTimerRunning = false;
        let pitTimerStart = 0;
        let pitTimerInterval = null;
        let pitStopHistory = [];

        function startPitTimer() {
            pitTimerStart = Date.now();
            pitTimerRunning = true;
            document.getElementById('pitTimerDisplay').classList.add('running');
            document.getElementById('pitTimerStart').disabled = true;
            document.getElementById('pitTimerStop').disabled = false;

            pitTimerInterval = setInterval(() => {
                const elapsed = Date.now() - pitTimerStart;
                document.getElementById('pitTimerDisplay').textContent = formatPitTime(elapsed);
            }, 100);

            // Send pit note
            sendQuickNote('PIT STOP STARTED');
        }

        function stopPitTimer() {
            if (!pitTimerRunning) return;

            clearInterval(pitTimerInterval);
            pitTimerRunning = false;

            const elapsed = Date.now() - pitTimerStart;
            document.getElementById('pitTimerDisplay').classList.remove('running');
            document.getElementById('pitTimerStart').disabled = false;
            document.getElementById('pitTimerStop').disabled = true;

            // Record to history
            pitStopHistory.unshift({
                time: elapsed,
                timestamp: new Date().toLocaleTimeString()
            });
            if (pitStopHistory.length > 5) pitStopHistory.pop();
            updatePitTimerHistory();

            // Send pit note
            sendQuickNote('PIT STOP COMPLETE: ' + formatPitTime(elapsed));
        }

        function resetPitTimer() {
            clearInterval(pitTimerInterval);
            pitTimerRunning = false;
            pitTimerStart = 0;
            document.getElementById('pitTimerDisplay').textContent = '00:00.0';
            document.getElementById('pitTimerDisplay').classList.remove('running');
            document.getElementById('pitTimerStart').disabled = false;
            document.getElementById('pitTimerStop').disabled = true;
        }

        function formatPitTime(ms) {
            const mins = Math.floor(ms / 60000);
            const secs = Math.floor((ms % 60000) / 1000);
            const tenths = Math.floor((ms % 1000) / 100);
            return String(mins).padStart(2, '0') + ':' + String(secs).padStart(2, '0') + '.' + tenths;
        }

        function updatePitTimerHistory() {
            const el = document.getElementById('pitTimerHistory');
            if (pitStopHistory.length === 0) {
                el.textContent = 'No pit stops recorded';
                return;
            }
            el.innerHTML = pitStopHistory.map((entry, i) =>
                `<div class="pit-time-entry"><span>#${i+1} @ ${entry.timestamp}</span><span class="time">${formatPitTime(entry.time)}</span></div>`
            ).join('');
        }

        // ============ P2: Weather Integration (Feature 5) ============
        let lastWeatherLat = 0;
        let lastWeatherLon = 0;
        let lastWeatherUpdate = 0;
        const WEATHER_UPDATE_INTERVAL = 300000; // 5 minutes

        async function updateWeather(lat, lon) {
            // Only update if we have valid GPS and haven't updated recently
            if (!lat || !lon || lat === 0 || lon === 0) return;

            const now = Date.now();
            const distMoved = haversineDistance([lastWeatherLat, lastWeatherLon], [lat, lon]);

            // Update weather if: first time, moved >1km, or 5 min elapsed
            if (lastWeatherUpdate === 0 || distMoved > 1 || (now - lastWeatherUpdate) > WEATHER_UPDATE_INTERVAL) {
                try {
                    // Use Open-Meteo API (free, no API key required)
                    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,wind_speed_10m,weather_code&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto`;

                    const response = await fetch(url);
                    if (!response.ok) throw new Error('Weather API error');

                    const data = await response.json();
                    const current = data.current;

                    if (current) {
                        document.getElementById('weatherTemp').textContent = Math.round(current.temperature_2m);
                        document.getElementById('weatherWind').textContent = Math.round(current.wind_speed_10m);
                        document.getElementById('weatherCond').textContent = weatherCodeToText(current.weather_code);
                        document.getElementById('weatherUpdated').textContent = new Date().toLocaleTimeString();

                        lastWeatherLat = lat;
                        lastWeatherLon = lon;
                        lastWeatherUpdate = now;
                    }
                } catch (error) {
                    console.log('Weather fetch error:', error);
                    // Fall back to placeholder if API fails
                    document.getElementById('weatherCond').textContent = 'N/A';
                }
            }
        }

        function weatherCodeToText(code) {
            const codes = {
                0: 'Clear', 1: 'Mainly Clear', 2: 'Partly Cloudy', 3: 'Overcast',
                45: 'Foggy', 48: 'Rime Fog',
                51: 'Light Drizzle', 53: 'Drizzle', 55: 'Heavy Drizzle',
                61: 'Light Rain', 63: 'Rain', 65: 'Heavy Rain',
                71: 'Light Snow', 73: 'Snow', 75: 'Heavy Snow',
                77: 'Snow Grains', 80: 'Light Showers', 81: 'Showers', 82: 'Heavy Showers',
                85: 'Snow Showers', 86: 'Heavy Snow Showers',
                95: 'Thunderstorm', 96: 'Thunderstorm+Hail', 99: 'Severe Thunderstorm'
            };
            return codes[code] || 'Unknown';
        }

        // ============ PROGRESS-3: Competitor Tracking ============
        function updateCompetitors(data) {
            const panel = document.getElementById('competitorsPanel');

            if (!data.race_position || data.race_position === 0) {
                panel.innerHTML = '<div class="competitor-item loading">Waiting for race position data...</div>';
                return;
            }

            // Check if course progress is available
            if (data.progress_miles == null && data.competitor_ahead == null && data.competitor_behind == null) {
                // No course progress data — show basic position context
                let html = '';
                if (data.race_position === 1) {
                    html += '<div class="competitor-item ahead"><span class="competitor-num">P1</span><span class="competitor-name">YOU ARE LEADING</span><span class="competitor-delta">P1</span></div>';
                }
                if (data.race_position < data.total_vehicles) {
                    html += '<div class="competitor-item loading">No course progress available</div>';
                }
                panel.innerHTML = html || '<div class="competitor-item loading">No course progress available</div>';
                return;
            }

            let html = '';

            // Competitor ahead
            if (data.competitor_ahead) {
                const a = data.competitor_ahead;
                const gapText = a.gap_miles != null ? `${a.gap_miles.toFixed(1)} mi ahead` : '\u2014';
                html += `<div class="competitor-item ahead">
                    <span class="competitor-num">#${a.vehicle_number}</span>
                    <span class="competitor-name">${a.team_name || ''}</span>
                    <span class="competitor-delta ahead">${gapText}</span>
                </div>`;
            } else if (data.race_position === 1) {
                html += `<div class="competitor-item ahead">
                    <span class="competitor-num">P1</span>
                    <span class="competitor-name">YOU ARE LEADING</span>
                    <span class="competitor-delta">P1</span>
                </div>`;
            }

            // Competitor behind
            if (data.competitor_behind) {
                const b = data.competitor_behind;
                const gapText = b.gap_miles != null ? `${b.gap_miles.toFixed(1)} mi behind` : '\u2014';
                html += `<div class="competitor-item behind">
                    <span class="competitor-num">#${b.vehicle_number}</span>
                    <span class="competitor-name">${b.team_name || ''}</span>
                    <span class="competitor-delta behind">${gapText}</span>
                </div>`;
            } else if (data.race_position >= data.total_vehicles) {
                html += `<div class="competitor-item behind">
                    <span class="competitor-num">\u2014</span>
                    <span class="competitor-name">No vehicle behind</span>
                    <span class="competitor-delta">\u2014</span>
                </div>`;
            }

            panel.innerHTML = html || '<div class="competitor-item loading">No competitor data</div>';
        }

        // Initial load
        loadFuelStatus();
        loadTireStatus();
        updateWeather();

        // Periodic updates
        setInterval(updateWeather, 300000); // Update weather every 5 minutes

        // ============ Utility ============
        function logout() {
            fetch('/api/logout', { method: 'POST' }).then(() => window.location.reload());
        }

        // ============ Device Management ============
        let detectedDevices = { cameras: [], gps: null, ant: null, can: null, usb: [] };
        // CAM-CONTRACT-1B: Canonical 4-camera slot mappings
        let cameraMappings = { main: '', cockpit: '', chase: '', suspension: '' };

        async function scanDevices() {
            const btn = document.getElementById('scanDevicesBtn');
            const status = document.getElementById('deviceScanStatus');
            btn.disabled = true;
            btn.textContent = 'Scanning...';
            status.textContent = 'Scanning for connected devices...';

            try {
                const resp = await fetch('/api/devices/scan');
                if (resp.ok) {
                    const data = await resp.json();
                    detectedDevices = data;
                    updateDeviceUI(data);
                    status.textContent = 'Scan complete. Found ' + (data.usb?.length || 0) + ' USB devices.';
                    status.style.color = 'var(--success)';
                } else {
                    status.textContent = 'Scan failed: ' + resp.statusText;
                    status.style.color = 'var(--danger)';
                }
            } catch (e) {
                status.textContent = 'Scan error: ' + e.message;
                status.style.color = 'var(--danger)';
            }

            btn.disabled = false;
            btn.textContent = 'Scan Devices';
        }

        function updateDeviceUI(data) {
            // Update camera devices list
            const cameraList = document.getElementById('cameraDevicesList');
            if (data.cameras && data.cameras.length > 0) {
                cameraList.innerHTML = data.cameras.map(cam => `
                    <div class="device-item ${cam.status}">
                        <span class="device-icon">CAM</span>
                        <div class="device-info">
                            <div class="device-name">${cam.name || 'USB Camera'}</div>
                            <div class="device-path">${cam.device}</div>
                        </div>
                        <span class="device-status-badge ${cam.status}">${cam.status}</span>
                    </div>
                `).join('');

                // Populate camera mapping dropdowns
                const options = '<option value="">-- Not assigned --</option>' +
                    data.cameras.map(cam => `<option value="${cam.device}">${cam.name || cam.device}</option>`).join('');
                // CAM-CONTRACT-1B: Populate canonical 4-camera slot dropdowns
                ['Main', 'Cockpit', 'Chase', 'Suspension'].forEach(name => {
                    document.getElementById('mapping' + name).innerHTML = options;
                });

                // Restore current mappings
                if (data.mappings) {
                    cameraMappings = data.mappings;
                    Object.entries(data.mappings).forEach(([role, device]) => {
                        const el = document.getElementById('mapping' + role.charAt(0).toUpperCase() + role.slice(1));
                        if (el) el.value = device || '';
                    });
                }
            } else {
                cameraList.innerHTML = '<div class="device-item offline">No cameras detected</div>';
            }

            // Update GPS device
            if (data.gps) {
                document.getElementById('gpsDevicePath').textContent = data.gps.device || '--';
                document.getElementById('gpsDeviceType').textContent = data.gps.type || '--';
                document.getElementById('gpsDeviceBaud').textContent = data.gps.baud || '--';
                document.getElementById('gpsDeviceSats').textContent = data.gps.satellites || '--';
                setDeviceStatus('gpsDeviceStatus', data.gps.status || 'offline');

                // Populate GPS port dropdown
                if (data.serial_ports) {
                    const gpsSelect = document.getElementById('gpsPortSelect');
                    gpsSelect.innerHTML = '<option value="">-- Auto-detect --</option>' +
                        data.serial_ports.map(p => `<option value="${p.device}" ${p.device === data.gps.device ? 'selected' : ''}>${p.device} - ${p.description || 'Serial Port'}</option>`).join('');
                }
            } else {
                document.getElementById('gpsDevicePath').textContent = 'Not detected';
                setDeviceStatus('gpsDeviceStatus', 'offline');
            }

            // Update ANT+ device
            if (data.ant) {
                document.getElementById('antDevicePath').textContent = data.ant.device || '--';
                document.getElementById('antDeviceProduct').textContent = data.ant.product || '--';
                document.getElementById('antServiceStatus').textContent = data.ant.service_status || '--';
                document.getElementById('antCurrentHR').textContent = (data.ant.heart_rate || '--') + ' BPM';
                setDeviceStatus('antDeviceStatus', data.ant.status || 'offline');
            } else {
                document.getElementById('antDevicePath').textContent = 'Not detected';
                setDeviceStatus('antDeviceStatus', 'offline');
            }

            // Update CAN interface
            if (data.can) {
                document.getElementById('canInterface').textContent = data.can.interface || '--';
                document.getElementById('canBitrate').textContent = data.can.bitrate || '--';
                document.getElementById('canRxCount').textContent = data.can.rx_count || '--';
                document.getElementById('canErrors').textContent = data.can.errors || '--';
                setDeviceStatus('canDeviceStatus', data.can.status || 'offline');
            } else {
                document.getElementById('canInterface').textContent = 'Not detected';
                setDeviceStatus('canDeviceStatus', 'offline');
            }

            // Update all USB devices list
            if (data.usb && data.usb.length > 0) {
                document.getElementById('allUsbDevicesList').innerHTML = data.usb.map(dev => `
                    <div class="device-item online">
                        <span class="device-icon">USB</span>
                        <div class="device-info">
                            <div class="device-name">${dev.product || 'USB Device'}</div>
                            <div class="device-path">${dev.vendor_id}:${dev.product_id} - ${dev.manufacturer || 'Unknown'}</div>
                        </div>
                    </div>
                `).join('');
            }

            // PIT-SVC-2: Unified service status model
            // Backend returns per-service: {state, label, details}
            // state: OK | WARN | ERROR | OFF | UNKNOWN
            if (data.services) {
                // Map service key (e.g. 'gps', 'can', 'uplink') to DOM element ID suffix
                const svcIdMap = {
                    'gps': 'Gps', 'can-setup': 'CanSetup', 'can': 'Can',
                    'ant': 'Ant', 'uplink': 'Uplink', 'video': 'Video',
                    'cloudflared': 'Cloudflared'
                };
                Object.entries(data.services).forEach(([name, info]) => {
                    const idSuffix = svcIdMap[name];
                    if (!idSuffix) return;
                    const el = document.getElementById('svc' + idSuffix);
                    const detailEl = document.getElementById('svc' + idSuffix + 'Detail');
                    if (!el) return;
                    // Handle both unified model (object) and legacy (string) formats
                    if (typeof info === 'object' && info.state) {
                        el.textContent = info.label;
                        const cls = info.state === 'OK' ? 'ok'
                            : info.state === 'WARN' ? 'warn'
                            : info.state === 'ERROR' ? 'error'
                            : info.state === 'OFF' ? 'off'
                            : 'unknown';
                        el.className = 'service-status ' + cls;
                        if (detailEl) detailEl.textContent = info.details || '';
                    } else {
                        // Legacy fallback: raw systemd string
                        const status = String(info);
                        el.textContent = status;
                        const cls = status === 'running' ? 'ok'
                            : (status.includes('crashed') || status === 'failed') ? 'error'
                            : status === 'stopped' ? 'error'
                            : 'off';
                        el.className = 'service-status ' + cls;
                        if (detailEl) detailEl.textContent = '';
                    }
                });
                // Show tunnel URL as clickable link if configured
                const cfInfo = data.services && data.services.cloudflared;
                const tunnelRow = document.getElementById('tunnelUrlRow');
                const tunnelLink = document.getElementById('tunnelUrlLink');
                if (cfInfo && cfInfo.tunnel_url && tunnelRow && tunnelLink) {
                    tunnelLink.href = cfInfo.tunnel_url;
                    tunnelLink.textContent = cfInfo.tunnel_url;
                    tunnelRow.style.display = 'block';
                } else if (tunnelRow) {
                    tunnelRow.style.display = 'none';
                }
            }
        }

        function setDeviceStatus(elId, status) {
            const el = document.getElementById(elId);
            el.textContent = status.toUpperCase();
            el.className = 'device-status-badge ' + status;
        }

        function toggleUsbList() {
            const panel = document.getElementById('allUsbDevicesPanel');
            panel.style.display = panel.style.display === 'none' ? 'block' : 'none';
        }

        function updateCameraMapping(role, device) {
            cameraMappings[role] = device;
        }

        async function saveCameraMappings() {
            try {
                const resp = await fetch('/api/devices/camera-mappings', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(cameraMappings)
                });
                if (resp.ok) {
                    showAlert('Camera mappings saved!', 'success');
                } else {
                    showAlert('Failed to save mappings', 'warning');
                }
            } catch (e) {
                showAlert('Error saving mappings: ' + e.message, 'warning');
            }
        }

        async function updateGpsConfig() {
            const port = document.getElementById('gpsPortSelect').value;
            try {
                await fetch('/api/devices/gps-config', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ port: port })
                });
            } catch (e) {
                console.error('Failed to update GPS config', e);
            }
        }

        async function pairAntDevice() {
            showAlert('Starting ANT+ pairing...', 'info');
            try {
                const resp = await fetch('/api/devices/ant-pair', { method: 'POST' });
                if (resp.ok) {
                    showAlert('ANT+ pairing initiated', 'success');
                    setTimeout(scanDevices, 3000);
                } else {
                    showAlert('ANT+ pairing failed', 'warning');
                }
            } catch (e) {
                showAlert('Pairing error: ' + e.message, 'warning');
            }
        }

        async function restartAntService() {
            try {
                const resp = await fetch('/api/devices/restart-service', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ service: 'argus-ant' })
                });
                if (resp.ok) {
                    showAlert('ANT+ service restarting...', 'success');
                    setTimeout(scanDevices, 3000);
                }
            } catch (e) {
                showAlert('Failed to restart service', 'warning');
            }
        }

        async function restartAllServices() {
            showAlert('Restarting all services...', 'info');
            try {
                const resp = await fetch('/api/devices/restart-all', { method: 'POST' });
                if (resp.ok) {
                    showAlert('All services restarting...', 'success');
                    setTimeout(scanDevices, 5000);
                }
            } catch (e) {
                showAlert('Failed to restart services', 'warning');
            }
        }

        // Auto-scan devices when switching to Devices tab
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                if (btn.dataset.tab === 'devices' && detectedDevices.usb.length === 0) {
                    scanDevices();
                }
            });
        });

        // ============ EDGE-CLOUD-2: Event Delegation (CSP compliance) ============
        // Replaces all inline onclick/onchange/onerror handlers with data-attribute delegation.
        // This allows script-src without 'unsafe-inline'.

        // Helper: trigger hidden GPX file input
        function triggerGpxUpload() {
            var el = document.getElementById('gpxFileInput');
            if (el) el.click();
        }

        // data-click="fn" [data-arg="val"] → click handler
        document.addEventListener('click', function(e) {
            var el = e.target.closest('[data-click]');
            if (!el) return;
            var fn = window[el.dataset.click];
            if (!fn) return;
            var arg = el.dataset.arg;
            if (arg === 'true') fn(true);
            else if (arg === 'false') fn(false);
            else if (arg != null) fn(arg);
            else fn();
        });

        // data-click-stop → stopPropagation
        document.addEventListener('click', function(e) {
            if (e.target.closest('[data-click-stop]')) e.stopPropagation();
        });

        // data-change-val="fn" [data-arg="val"] → fn(value) or fn(arg, value)
        document.addEventListener('change', function(e) {
            var el = e.target.closest('[data-change-val]');
            if (el) {
                var fn = window[el.dataset.changeVal];
                var arg = el.dataset.arg;
                if (fn) { arg != null ? fn(arg, e.target.value) : fn(e.target.value); }
                return;
            }
            var bel = e.target.closest('[data-change-bool]');
            if (bel) {
                var fn2 = window[bel.dataset.changeBool];
                if (fn2) fn2(e.target.checked);
                return;
            }
            var cel = e.target.closest('[data-change-call]');
            if (cel) {
                var fn3 = window[cel.dataset.changeCall];
                if (fn3) fn3();
                return;
            }
            var evel = e.target.closest('[data-change-event]');
            if (evel) {
                var fn4 = window[evel.dataset.changeEvent];
                if (fn4) fn4(e);
                return;
            }
            // Template-generated: data-toggle-field + data-toggle-level
            var tfel = e.target.closest('[data-toggle-field]');
            if (tfel) {
                toggleField(tfel.dataset.toggleField, tfel.dataset.toggleLevel, e.target.checked);
            }
        });

        // data-hide-error on img → hide on error
        document.querySelectorAll('[data-hide-error]').forEach(function(img) {
            img.addEventListener('error', function() { this.style.display = 'none'; });
        });

        // Setup form submit handler (replaces onsubmit="return validateForm()")
        var setupForm = document.getElementById('setupForm');
        if (setupForm) {
            setupForm.addEventListener('submit', function(e) {
                if (!validateForm()) e.preventDefault();
            });
        }

        // ============ Init ============
        connect();
        var vehicleNumEl = document.getElementById('vehicleNum');
        if (vehicleNumEl) vehicleNumEl.textContent = '#' + (window.VEHICLE_NUMBER || '---');
    </script>
</body>
</html>
'''

LOGIN_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pit Crew - Login</title>
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #fafafa;
            margin: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .login-box {
            background: #171717;
            border-radius: 12px;
            padding: 32px;
            width: 100%;
            max-width: 400px;
            border: 1px solid #404040;
        }
        .logo {
            text-align: center;
            margin-bottom: 24px;
        }
        .logo h1 {
            font-size: 1.5rem;
            font-weight: 700;
            margin: 0;
            color: #fafafa;
        }
        .logo p {
            color: #737373;
            margin: 4px 0 0;
            font-size: 0.875rem;
        }
        .form-group {
            margin-bottom: 16px;
        }
        label {
            display: block;
            margin-bottom: 8px;
            color: #d4d4d4;
            font-size: 0.875rem;
            font-weight: 500;
        }
        input {
            width: 100%;
            padding: 12px 16px;
            background: #0a0a0a;
            border: 1px solid #525252;
            border-radius: 8px;
            color: #fafafa;
            font-size: 1rem;
        }
        input:focus {
            outline: none;
            border-color: #3b82f6;
            box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.25);
        }
        button {
            width: 100%;
            padding: 12px;
            background: #2563eb;
            border: none;
            border-radius: 8px;
            color: white;
            font-size: 0.875rem;
            font-weight: 600;
            cursor: pointer;
        }
        button:hover {
            background: #3b82f6;
        }
        .error {
            background: rgba(239, 68, 68, 0.06);
            border: 1px solid rgba(239, 68, 68, 0.2);
            color: #fca5a5;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 16px;
            font-size: 0.875rem;
        }
    </style>
</head>
<body>
    <div class="login-box">
        <div class="logo">
            <h1>Pit Crew</h1>
            <p>Dashboard</p>
        </div>

        {error}

        <form method="POST" action="/login">
            <div class="form-group">
                <label for="password">Password</label>
                <input type="password" name="password" id="password" placeholder="Enter pit crew password" autofocus required>
            </div>
            <button type="submit">Sign In</button>
        </form>
    </div>
</body>
</html>
'''

SETTINGS_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pit Crew - Settings</title>
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #fafafa;
            margin: 0;
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 24px;
        }
        .header h1 {
            font-size: 1.5rem;
            font-weight: 700;
            margin: 0;
            color: #fafafa;
        }
        .back-link {
            color: #a3a3a3;
            text-decoration: none;
            font-size: 0.875rem;
        }
        .back-link:hover { color: #fafafa; }
        .settings-box {
            background: #171717;
            border-radius: 12px;
            padding: 24px;
            border: 1px solid #404040;
        }
        .form-group {
            margin-bottom: 16px;
        }
        label {
            display: block;
            margin-bottom: 8px;
            color: #d4d4d4;
            font-size: 0.875rem;
            font-weight: 500;
        }
        input {
            width: 100%;
            padding: 12px 16px;
            background: #0a0a0a;
            border: 1px solid #525252;
            border-radius: 8px;
            color: #fafafa;
            font-size: 1rem;
        }
        input:focus {
            outline: none;
            border-color: #3b82f6;
            box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.25);
        }
        input:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        .help-text {
            font-size: 0.75rem;
            color: #737373;
            margin-top: 4px;
        }
        .section-title {
            font-size: 0.875rem;
            font-weight: 600;
            color: #d4d4d4;
            margin: 24px 0 12px 0;
            padding-bottom: 8px;
            border-bottom: 1px solid #404040;
        }
        .section-title:first-child {
            margin-top: 0;
        }
        button {
            width: 100%;
            padding: 12px;
            background: #2563eb;
            border: none;
            border-radius: 8px;
            color: white;
            font-size: 0.875rem;
            font-weight: 600;
            cursor: pointer;
            margin-top: 8px;
        }
        button:hover { background: #3b82f6; }
        .success {
            background: rgba(34, 197, 94, 0.06);
            border: 1px solid rgba(34, 197, 94, 0.2);
            color: #86efac;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 16px;
            font-size: 0.875rem;
        }
        .error {
            background: rgba(239, 68, 68, 0.06);
            border: 1px solid rgba(239, 68, 68, 0.2);
            color: #fca5a5;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 16px;
            font-size: 0.875rem;
        }
        .current-value {
            font-size: 0.75rem;
            color: #22c55e;
            margin-top: 3px;
        }
        .sync-status {
            background: #262626;
            border-radius: 8px;
            padding: 15px;
            margin-top: 20px;
            font-size: 0.875rem;
        }
        .sync-status h4 {
            margin: 0 0 10px 0;
            color: #a3a3a3;
        }
        .sync-btn {
            background: #404040;
            margin-top: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Settings</h1>
            <a href="/" class="back-link">&larr; Back to Dashboard</a>
        </div>

        <div class="settings-box">
            {message}

            <form method="POST" action="/settings">
                <div class="section-title">Vehicle Info</div>

                <div class="form-group">
                    <label for="vehicle_number">Vehicle Number</label>
                    <input type="text" name="vehicle_number" id="vehicle_number" value="{vehicle_number}" placeholder="e.g., 123" maxlength="10">
                </div>

                <div class="section-title">Cloud Connection</div>

                <div class="form-group">
                    <label for="cloud_url">Cloud API URL</label>
                    <input type="url" name="cloud_url" id="cloud_url" value="{cloud_url}" placeholder="https://your-argus-cloud.com">
                </div>

                <div class="form-group">
                    <label for="truck_token">Truck Authentication Token</label>
                    <input type="text" name="truck_token" id="truck_token" value="{truck_token}" placeholder="trk_xxxxxxxx">
                </div>

                <div class="form-group">
                    <label for="event_id">Event ID</label>
                    <input type="text" name="event_id" id="event_id" value="{event_id}" placeholder="evt_xxxxxxxx">
                </div>

                <div class="section-title">Cloudflare Tunnel</div>

                <div class="form-group">
                    <label for="cloudflare_tunnel_token">Tunnel Token</label>
                    <input type="password" name="cloudflare_tunnel_token" id="cloudflare_tunnel_token" value="{cloudflare_tunnel_token}" placeholder="eyJhIjoi...">
                    <div class="help-text">From Cloudflare Zero Trust &gt; Networks &gt; Tunnels.</div>
                </div>

                <div class="form-group">
                    <label for="cloudflare_tunnel_url">Public Tunnel URL</label>
                    <input type="url" name="cloudflare_tunnel_url" id="cloudflare_tunnel_url" value="{cloudflare_tunnel_url}" placeholder="https://pit-truck42.your-domain.com">
                    <div class="help-text">The public HTTPS URL for CGNAT-proof external access.</div>
                </div>

                <div class="section-title">YouTube Live Streaming</div>

                <div class="form-group">
                    <label for="youtube_stream_key">YouTube Stream Key</label>
                    <input type="password" name="youtube_stream_key" id="youtube_stream_key" value="{youtube_stream_key}" placeholder="xxxx-xxxx-xxxx-xxxx-xxxx">
                    <div class="help-text">Found in YouTube Studio &gt; Go Live &gt; Stream Settings. Keep this secret!</div>
                </div>

                <div class="form-group">
                    <label for="youtube_live_url">YouTube Live Stream URL</label>
                    <input type="url" name="youtube_live_url" id="youtube_live_url" value="{youtube_live_url}" placeholder="https://youtube.com/watch?v=xxxxx">
                    <div class="help-text">The public URL where fans can watch your stream. This will be synced to the cloud.</div>
                </div>

                <div class="sync-status">
                    <h4>Cloud Sync Status</h4>
                    <div id="syncStatus">Save settings to sync YouTube URL with the cloud server.</div>
                    <button type="button" class="sync-btn" data-click="syncToCloud">Sync to Cloud Now</button>
                </div>

                <button type="submit">Save Settings</button>
            </form>
        </div>
    </div>

    <script nonce="__CSP_NONCE__">
        // PIT-VIS-0: Added nonce — this block was silently blocked by CSP,
        // causing setFanVisibility "not defined" and all Team tab JS to fail.
        async function syncToCloud() {
            const statusEl = document.getElementById('syncStatus');
            statusEl.textContent = 'Syncing...';
            try {
                const res = await fetch('/api/sync-youtube', { method: 'POST' });
                const data = await res.json();
                if (data.success) {
                    statusEl.textContent = 'Synced successfully at ' + new Date().toLocaleTimeString();
                    statusEl.style.color = '#22c55e';
                } else {
                    statusEl.textContent = 'Sync failed: ' + (data.error || 'Unknown error');
                    statusEl.style.color = '#ef4444';
                }
            } catch (e) {
                statusEl.textContent = 'Sync failed: ' + e.message;
                statusEl.style.color = '#ef4444';
            }
        }

        // ============ TEAM-3: Fan Visibility & Telemetry Sharing ============

        const FIELD_GROUPS = {
            gps: ['lat', 'lon', 'speed_mps', 'heading_deg', 'altitude_m'],
            engine_basic: ['rpm', 'gear', 'speed_mph'],
            engine_advanced: ['throttle_pct', 'coolant_temp_c', 'oil_pressure_psi', 'fuel_pressure_psi'],
            biometrics: ['heart_rate', 'heart_rate_zone'],
        };

        const FIELD_LABELS = {
            lat: 'Latitude', lon: 'Longitude', speed_mps: 'Speed', heading_deg: 'Heading',
            altitude_m: 'Altitude', rpm: 'RPM', gear: 'Gear', speed_mph: 'Speed (mph)',
            throttle_pct: 'Throttle %', coolant_temp_c: 'Coolant', oil_pressure_psi: 'Oil Press',
            fuel_pressure_psi: 'Fuel Press', heart_rate: 'Heart Rate', heart_rate_zone: 'HR Zone',
        };

        let sharingState = { allow_production: [], allow_fans: [] };

        async function loadTeamState() {
            try {
                const [visRes, polRes] = await Promise.all([
                    fetch('/api/team/visibility'),
                    fetch('/api/team/sharing-policy'),
                ]);
                if (visRes.ok) {
                    const vis = await visRes.json();
                    updateVisibilityUI(vis.visible);
                }
                if (polRes.ok) {
                    const pol = await polRes.json();
                    sharingState = pol;
                    renderSharingFields();
                }
            } catch (e) { console.warn('Failed to load team state:', e); }
        }

        // PIT-VIS-0: Use CSS classes for reliable styling (--accent-green was undefined)
        function updateVisibilityUI(visible) {
            const badge = document.getElementById('visibilityBadge');
            const btnOn = document.getElementById('btnVisibilityOn');
            const btnOff = document.getElementById('btnVisibilityOff');
            if (visible) {
                badge.textContent = 'Visible';
                badge.style.background = 'var(--success)';
                badge.style.color = '#000';
                btnOn.classList.add('vis-on');
                btnOn.classList.remove('vis-off');
                btnOff.classList.remove('vis-off', 'vis-on');
            } else {
                badge.textContent = 'Hidden';
                badge.style.background = 'var(--danger)';
                badge.style.color = '#fff';
                btnOff.classList.add('vis-off');
                btnOff.classList.remove('vis-on');
                btnOn.classList.remove('vis-on', 'vis-off');
            }
        }

        async function setFanVisibility(visible) {
            const statusEl = document.getElementById('visibilitySyncStatus');
            statusEl.textContent = 'Saving...';
            statusEl.style.color = 'var(--text-muted)';
            try {
                const res = await fetch('/api/team/visibility', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ visible }),
                });
                const data = await res.json();
                if (data.success) {
                    updateVisibilityUI(visible);
                    statusEl.textContent = data.synced
                        ? 'Saved & synced to cloud'
                        : 'Saved locally (cloud sync unavailable)';
                    statusEl.style.color = data.synced ? '#22c55e' : '#f59e0b';
                } else {
                    statusEl.textContent = 'Error: ' + (data.error || 'Unknown');
                    statusEl.style.color = '#ef4444';
                }
            } catch (e) {
                statusEl.textContent = 'Error: ' + e.message;
                statusEl.style.color = '#ef4444';
            }
        }

        function renderSharingFields() {
            for (const [group, fields] of Object.entries(FIELD_GROUPS)) {
                const container = document.getElementById('sharing-' + group);
                if (!container) continue;
                container.innerHTML = '';
                for (const field of fields) {
                    const inProd = sharingState.allow_production.includes(field);
                    const inFan = sharingState.allow_fans.includes(field);
                    const label = FIELD_LABELS[field] || field;
                    const el = document.createElement('div');
                    el.style.cssText = 'display:flex; align-items:center; gap:4px; font-size:0.8rem; padding:4px 8px; border-radius:6px; background:var(--bg-tertiary);';
                    el.innerHTML = `
                        <span style="min-width:60px;">${label}</span>
                        <label style="font-size:0.7rem; color:var(--text-muted); display:flex; align-items:center; gap:2px; cursor:pointer;">
                            <input type="checkbox" data-field="${field}" data-level="prod" ${inProd ? 'checked' : ''} data-toggle-field="${field}" data-toggle-level="prod"> Prod
                        </label>
                        <label style="font-size:0.7rem; color:var(--text-muted); display:flex; align-items:center; gap:2px; cursor:pointer;">
                            <input type="checkbox" data-field="${field}" data-level="fan" ${inFan ? 'checked' : ''} data-toggle-field="${field}" data-toggle-level="fan"> Fan
                        </label>
                    `;
                    container.appendChild(el);
                }
            }
        }

        function toggleField(field, level, checked) {
            const arr = level === 'prod' ? sharingState.allow_production : sharingState.allow_fans;
            if (checked && !arr.includes(field)) arr.push(field);
            if (!checked) {
                const idx = arr.indexOf(field);
                if (idx >= 0) arr.splice(idx, 1);
                // If removing from prod, also remove from fans
                if (level === 'prod') {
                    const fanIdx = sharingState.allow_fans.indexOf(field);
                    if (fanIdx >= 0) sharingState.allow_fans.splice(fanIdx, 1);
                }
            }
            renderSharingFields();
        }

        function applyPreset(preset) {
            const GPS = ['lat', 'lon', 'speed_mps', 'heading_deg'];
            const BASIC = [...GPS, 'rpm', 'gear', 'speed_mph'];
            const FULL = Object.values(FIELD_GROUPS).flat();
            switch (preset) {
                case 'none':
                    sharingState.allow_production = [];
                    sharingState.allow_fans = [];
                    break;
                case 'gps':
                    sharingState.allow_production = [...GPS];
                    sharingState.allow_fans = [];
                    break;
                case 'basic':
                    sharingState.allow_production = [...BASIC];
                    sharingState.allow_fans = [...GPS];
                    break;
                case 'full':
                    sharingState.allow_production = [...FULL];
                    sharingState.allow_fans = [...BASIC];
                    break;
            }
            renderSharingFields();
        }

        async function saveSharingPolicy() {
            const statusEl = document.getElementById('sharingSyncStatus');
            statusEl.textContent = 'Saving...';
            statusEl.style.color = 'var(--text-muted)';
            try {
                const res = await fetch('/api/team/sharing-policy', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        allow_production: sharingState.allow_production,
                        allow_fans: sharingState.allow_fans,
                    }),
                });
                const data = await res.json();
                if (data.success) {
                    statusEl.textContent = data.synced
                        ? 'Saved & synced to cloud'
                        : 'Saved locally (cloud sync unavailable)';
                    statusEl.style.color = data.synced ? '#22c55e' : '#f59e0b';
                } else {
                    statusEl.textContent = 'Error: ' + (data.error || 'Unknown');
                    statusEl.style.color = '#ef4444';
                }
            } catch (e) {
                statusEl.textContent = 'Error: ' + e.message;
                statusEl.style.color = '#ef4444';
            }
        }

        // PIT-VIS-0: Load team state on page load (deferred) + on tab click
        loadTeamState();
        document.querySelector('[data-tab="team"]')?.addEventListener('click', () => {
            loadTeamState();
        });
    </script>
</body>
</html>
'''

SETUP_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pit Crew - Setup</title>
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #fafafa;
            margin: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .setup-box {
            background: #171717;
            border-radius: 16px;
            padding: 40px;
            width: 100%;
            max-width: 500px;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
            border: 1px solid #404040;
        }
        .logo {
            text-align: center;
            margin-bottom: 30px;
        }
        .logo h1 {
            font-size: 1.75rem;
            margin: 0;
            color: #2563eb;
        }
        .logo p {
            color: #737373;
            margin: 5px 0 0;
        }
        .welcome {
            background: rgba(59, 130, 246, 0.1);
            border: 1px solid #3b82f6;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 25px;
            font-size: 0.9rem;
            color: #93c5fd;
        }
        .form-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 8px;
            color: #a3a3a3;
            font-size: 0.875rem;
        }
        input {
            width: 100%;
            padding: 12px 16px;
            background: #262626;
            border: 2px solid #404040;
            border-radius: 8px;
            color: #fafafa;
            font-size: 1rem;
        }
        input:focus {
            outline: none;
            border-color: #3b82f6;
        }
        input.error {
            border-color: #ef4444;
        }
        .help-text {
            font-size: 0.75rem;
            color: #737373;
            margin-top: 5px;
        }
        .error-text {
            font-size: 0.75rem;
            color: #ef4444;
            margin-top: 5px;
            display: none;
        }
        button {
            width: 100%;
            padding: 14px;
            background: #2563eb;
            border: none;
            border-radius: 8px;
            color: white;
            font-size: 1rem;
            font-weight: 600;
            cursor: pointer;
            margin-top: 10px;
        }
        button:hover {
            opacity: 0.9;
        }
        button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        .section-title {
            font-size: 0.9rem;
            font-weight: 600;
            color: #fafafa;
            margin: 25px 0 15px 0;
            padding-bottom: 8px;
            border-bottom: 1px solid #404040;
        }
        .server-error {
            background: rgba(239, 68, 68, 0.1);
            border: 1px solid #ef4444;
            color: #fca5a5;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 20px;
            font-size: 0.875rem;
        }
    </style>
</head>
<body>
    <div class="setup-box">
        <div class="logo">
            <h1>Pit Crew</h1>
            <p>Dashboard Setup</p>
        </div>

        <div class="welcome">
            Welcome! This is the first-time setup for your pit crew dashboard.
            Create a password to protect access to telemetry data.
            <br><br>
            <strong>Starlink / CGNAT users:</strong> Cloudflare Tunnel is required for remote access.
            Without it, the dashboard is only reachable on the local network.
        </div>

        {error}

        <form method="POST" action="/setup" id="setupForm">
            <div class="section-title">Security</div>

            <div class="form-group">
                <label for="password">Dashboard Password *</label>
                <input type="password" name="password" id="password" placeholder="Create a password" required minlength="4">
                <div class="help-text">At least 4 characters. Share this with your pit crew.</div>
            </div>

            <div class="form-group">
                <label for="password_confirm">Confirm Password *</label>
                <input type="password" name="password_confirm" id="password_confirm" placeholder="Confirm password" required>
                <div class="error-text" id="passwordError">Passwords do not match</div>
            </div>

            <div class="section-title">Vehicle Info (Optional)</div>

            <div class="form-group">
                <label for="vehicle_number">Vehicle Number</label>
                <input type="text" name="vehicle_number" id="vehicle_number" placeholder="e.g., 123" maxlength="10">
                <div class="help-text">Your racing number - displayed on the dashboard header.</div>
            </div>

            <div class="section-title">Cloud Connection (Optional)</div>

            <div class="form-group">
                <label for="cloud_url">Cloud API URL</label>
                <input type="url" name="cloud_url" id="cloud_url" placeholder="https://your-argus-cloud.com">
                <div class="help-text">For production camera status. Leave blank if not using cloud.</div>
            </div>

            <div class="form-group">
                <label for="truck_token">Truck Authentication Token</label>
                <input type="text" name="truck_token" id="truck_token" placeholder="trk_xxxxxxxx">
                <div class="help-text">Token from cloud registration.</div>
            </div>

            <div class="form-group">
                <label for="event_id">Event ID</label>
                <input type="text" name="event_id" id="event_id" placeholder="evt_xxxxxxxx">
                <div class="help-text">Current race event ID.</div>
            </div>

            <div class="section-title">Cloudflare Tunnel (Required)</div>
            <div style="background: rgba(245, 158, 11, 0.1); border: 1px solid rgba(245, 158, 11, 0.3); border-radius: 8px; padding: 10px 14px; margin-bottom: 15px; font-size: 0.8rem; color: #fcd34d;">
                Starlink and cellular connections use CGNAT, which blocks inbound connections.
                A Cloudflare Tunnel creates a secure outbound-only link so the cloud and pit crew
                can reach this dashboard from anywhere.
            </div>

            <div class="form-group">
                <label for="cloudflare_tunnel_token">Tunnel Token *</label>
                <input type="password" name="cloudflare_tunnel_token" id="cloudflare_tunnel_token" placeholder="eyJhIjoi..." required>
                <div class="help-text">From Cloudflare Zero Trust &gt; Networks &gt; Tunnels. Run <code>cloudflared tunnel create</code> or copy from the Zero Trust dashboard.</div>
            </div>

            <div class="form-group">
                <label for="cloudflare_tunnel_url">Public Tunnel URL *</label>
                <input type="url" name="cloudflare_tunnel_url" id="cloudflare_tunnel_url" placeholder="https://pit-truck42.your-domain.com" required>
                <div class="help-text">The public HTTPS hostname configured in your tunnel. This is how the cloud server and remote pit crew will reach this device.</div>
                <div class="error-text" id="cfUrlError">Must be a valid https:// URL</div>
            </div>

            <div class="section-title">YouTube Live Streaming (Optional)</div>

            <div class="form-group">
                <label for="youtube_stream_key">YouTube Stream Key</label>
                <input type="password" name="youtube_stream_key" id="youtube_stream_key" placeholder="xxxx-xxxx-xxxx-xxxx-xxxx">
                <div class="help-text">Found in YouTube Studio &gt; Go Live &gt; Stream Settings. Keep this secret!</div>
            </div>

            <div class="form-group">
                <label for="youtube_live_url">YouTube Live Stream URL</label>
                <input type="url" name="youtube_live_url" id="youtube_live_url" placeholder="https://youtube.com/watch?v=xxxxx">
                <div class="help-text">The public URL where fans can watch your stream.</div>
            </div>

            <button type="submit" id="submitBtn">Complete Setup</button>
        </form>
    </div>

    <script>
        function validateForm() {
            const password = document.getElementById('password').value;
            const confirm = document.getElementById('password_confirm').value;
            const errorEl = document.getElementById('passwordError');
            const confirmInput = document.getElementById('password_confirm');

            if (password !== confirm) {
                errorEl.style.display = 'block';
                confirmInput.classList.add('error');
                confirmInput.focus();
                return false;
            }
            errorEl.style.display = 'none';
            confirmInput.classList.remove('error');

            // Validate Cloudflare Tunnel fields
            const cfToken = document.getElementById('cloudflare_tunnel_token').value.trim();
            const cfUrl = document.getElementById('cloudflare_tunnel_url').value.trim();
            const cfUrlError = document.getElementById('cfUrlError');
            const cfUrlInput = document.getElementById('cloudflare_tunnel_url');

            if (!cfToken) {
                document.getElementById('cloudflare_tunnel_token').classList.add('error');
                document.getElementById('cloudflare_tunnel_token').focus();
                return false;
            }
            document.getElementById('cloudflare_tunnel_token').classList.remove('error');

            if (!cfUrl || !cfUrl.startsWith('https://')) {
                cfUrlError.style.display = 'block';
                cfUrlInput.classList.add('error');
                cfUrlInput.focus();
                return false;
            }
            cfUrlError.style.display = 'none';
            cfUrlInput.classList.remove('error');

            return true;
        }

        // Clear error on input
        document.getElementById('password_confirm').addEventListener('input', function() {
            this.classList.remove('error');
            document.getElementById('passwordError').style.display = 'none';
        });
        document.getElementById('cloudflare_tunnel_url').addEventListener('input', function() {
            this.classList.remove('error');
            document.getElementById('cfUrlError').style.display = 'none';
        });
        document.getElementById('cloudflare_tunnel_token').addEventListener('input', function() {
            this.classList.remove('error');
        });
    </script>
</body>
</html>
'''


# ============ Web Application ============

class PitCrewDashboard:
    """Pit crew dashboard web application."""

    def __init__(self, config: DashboardConfig):
        self.config = config
        self.sessions = SessionManager(config.session_secret)
        self.telemetry = TelemetryState()
        # EDGE-STATUS-1: Record boot time so JS can distinguish "still booting" (yellow) from "broken" (red)
        self.telemetry.boot_ts_ms = int(time.time() * 1000)
        self.sse_clients: Set[web.StreamResponse] = set()
        self._running = False
        self._zmq_context = None
        self._zmq_socket_can = None
        self._zmq_socket_gps = None
        self._zmq_socket_ant = None  # ADDED: ANT+ heart rate subscriber

        # CAM-CONTRACT-1B: Canonical 4-camera slots for status tracking
        self._camera_status: Dict[str, str] = {
            "main": "offline",
            "cockpit": "offline",
            "chase": "offline",
            "suspension": "offline"
        }
        self._camera_devices = {
            "main": "/dev/video0",
            "cockpit": "/dev/video2",
            "chase": "/dev/video4",
            "suspension": "/dev/video6"
        }
        # CAM-CONTRACT-1B: Backward compatibility aliases for legacy edge devices
        self._camera_aliases = {
            "pov": "cockpit",
            "roof": "chase",
            "front": "suspension",
            "rear": "suspension",
        }

        # ADDED: Audio monitoring
        self._audio_level: float = -60.0  # dB
        self._last_audio_activity: int = 0

        # LINK-1: Cloud status loop task handle for restart after settings change
        self._cloud_status_task: Optional[asyncio.Task] = None

        # ADDED: Pit notes queue
        # PIT-COMMS-1: Notes queue with background sync retry
        self._pit_notes: list = []
        self._pit_notes_sync_task: Optional[asyncio.Task] = None
        self._pit_notes_last_sync_attempt: int = 0
        self._load_pit_notes()  # Load persisted notes on startup

        # P1: Fuel strategy tracking
        # PIT-FUEL-1: Uses constants for tank capacity (single source of truth)
        # NOTE: fuel_set=False until crew explicitly sets it - no fake values!
        self._fuel_strategy: Dict[str, Any] = {
            'tank_capacity_gal': DEFAULT_TANK_CAPACITY_GAL,  # PIT-FUEL-1: Use constant
            'current_fuel_gal': None,   # None until set by crew (or MOTEC)
            'fuel_set': False,          # False until crew or ECU sets fuel level
            'consumption_rate_mpg': 2.0,  # Miles per gallon (default for off-road trucks)
            'last_fill_lap': 0,
            'last_fill_timestamp': 0,
            'updated_at': 0,            # Timestamp of last update
            'updated_by': None,         # Operator identity (if available)
            'source': None,             # 'manual' or 'ecu' (MOTEC)
        }
        # Load persisted fuel state (if exists)
        self._load_fuel_state()

        # PIT-1R: GPS-based trip miles tracking (independent of tire miles)
        self._trip_state: Dict[str, Any] = {
            'trip_miles': 0.0,          # Accumulated GPS distance since reset
            'trip_start_at': int(time.time() * 1000),  # When trip started/was reset
            'prev_lat': None,           # Previous GPS fix lat
            'prev_lon': None,           # Previous GPS fix lon
        }
        self._load_trip_state()

        # PIT-5R: Per-axle tire tracking (front/rear independent)
        self._tire_state: Dict[str, Any] = {
            'brand': 'Toyo',  # Shared brand: Toyo / BFG / Maxxis / Other
            'front_trip_baseline': 0.0,  # trip_miles at last front reset
            'front_last_changed_at': 0,  # timestamp ms
            'front_change_count': 0,
            'rear_trip_baseline': 0.0,   # trip_miles at last rear reset
            'rear_last_changed_at': 0,
            'rear_change_count': 0,
        }
        self._load_tire_state()

        # ADDED: Screenshot capture system for stream control
        self._screenshot_cache_dir = '/opt/argus/cache/screenshots'
        self._screenshot_interval = 30  # PIT-CAM-PREVIEW-B: Capture every 30 seconds
        self._screenshot_timestamps: Dict[str, int] = {}  # Last capture time per camera
        self._screenshot_resolutions: Dict[str, str] = {}  # Resolution info per camera
        self._screenshot_capture_in_progress = False
        # Create cache directory
        try:
            os.makedirs(self._screenshot_cache_dir, exist_ok=True)
        except Exception as e:
            logger.warning(f"Could not create screenshot cache dir: {e}")
            self._screenshot_cache_dir = '/tmp/argus_screenshots'
            os.makedirs(self._screenshot_cache_dir, exist_ok=True)

        # ADDED: Streaming state management
        self._streaming_state: Dict[str, Any] = {
            'status': 'idle',  # 'idle', 'starting', 'live', 'error', 'stopping'
            'camera': 'main',  # Active camera
            'started_at': None,  # Timestamp when streaming started
            'error': None,  # Last error message
            'pid': None,  # FFmpeg process ID
            'youtube_status': 'unknown',  # 'unknown', 'live', 'offline'
        }
        self._ffmpeg_process: Optional[subprocess.Popen] = None
        self._streaming_monitor_task: Optional[asyncio.Task] = None

        # STREAM-1: Load persisted stream profile
        from stream_profiles import load_profile_state
        _profile_state = load_profile_state()
        self._stream_profile: str = _profile_state["profile"]
        self._stream_auto_mode: bool = _profile_state["auto_mode"]

        # STREAM-4: Auto-downshift health tracking
        self._stream_health: Dict[str, Any] = {
            "speed_samples": [],       # List of (timestamp, speed_float) tuples
            "restart_timestamps": [],  # List of timestamps when stream restarted
            "last_error_summary": None,
            "current_speed": None,     # Latest parsed speed value
            "healthy_since": None,     # Timestamp when health became consistently good
            "last_downshift_at": None, # Timestamp of last auto downshift
            "last_upshift_at": None,   # Timestamp of last auto upshift
            "auto_profile_ceiling": self._stream_profile,  # Manual ceiling
        }
        self._ffmpeg_progress_reader_task: Optional[asyncio.Task] = None

        # PROD-3: Load persisted camera mappings and desired camera for reboot recovery
        self._load_camera_mappings()
        self._load_desired_camera()
        # PROD-3: Rate limiting for camera switch commands
        self._last_camera_switch_at: float = 0.0
        self._camera_switch_cooldown_s: float = 2.0  # Minimum seconds between switches

        # EDGE-PROG-3: Program State - single authoritative source for Pit Crew UI & Cloud sync
        self._program_state: Dict[str, Any] = {
            'active_camera': 'main',          # Currently active camera feed
            'streaming': False,                # Is stream currently live?
            'stream_destination': None,        # YouTube live URL or None
            'last_switch_at': None,            # Timestamp (ms) of last camera switch
            'last_stream_start_at': None,      # Timestamp (ms) of last stream start
            'last_error': None,                # Last error message
            'updated_at': None,                # Timestamp (ms) of last state update
        }
        self._load_program_state()

        # TEAM-3: Fan visibility state (migrated from cloud TeamDashboard)
        self._fan_visibility: bool = True  # True = visible to fans, False = hidden
        self._load_fan_visibility()

        # TEAM-3: Telemetry sharing policy (migrated from cloud TeamDashboard)
        self._sharing_policy: Dict[str, Any] = {
            'allow_production': ['lat', 'lon', 'speed_mps', 'heading_deg'],  # GPS only default
            'allow_fans': [],  # Nothing by default
            'updated_at': None,
        }
        self._load_sharing_policy()

    # ============ Fuel State Persistence ============

    def _get_fuel_state_path(self) -> str:
        """Get the path to the fuel state file."""
        config_dir = os.path.dirname(get_config_path())
        return os.path.join(config_dir, 'fuel_state.json')

    def _load_fuel_state(self) -> None:
        """Load persisted fuel state from disk.

        PIT-FUEL-1: Enhanced logging to debug "reverting to 35" issues.
        """
        fuel_file = self._get_fuel_state_path()
        try:
            if os.path.exists(fuel_file):
                logger.info(f"PIT-FUEL-1: Loading fuel state from: {fuel_file}")
                with open(fuel_file, 'r') as f:
                    saved_state = json.load(f)
                # Merge saved state into current state (preserving defaults for missing fields)
                for key in ['tank_capacity_gal', 'current_fuel_gal', 'fuel_set',
                           'consumption_rate_mpg', 'last_fill_lap', 'last_fill_timestamp',
                           'updated_at', 'updated_by', 'source']:
                    if key in saved_state:
                        self._fuel_strategy[key] = saved_state[key]
                # PIT-FUEL-1: Log tank capacity specifically to debug reversion issues
                logger.info(f"PIT-FUEL-1: Loaded fuel state - tank_capacity={self._fuel_strategy['tank_capacity_gal']} gal, "
                           f"current={self._fuel_strategy['current_fuel_gal']} gal, set={self._fuel_strategy['fuel_set']}")
            else:
                # PIT-FUEL-1: Explicitly log when using defaults (helps debug reversion)
                logger.warning(f"PIT-FUEL-1: Fuel state file not found: {fuel_file} - using defaults "
                              f"(tank_capacity={DEFAULT_TANK_CAPACITY_GAL} gal)")
        except Exception as e:
            logger.error(f"PIT-FUEL-1: Failed to load fuel state from {fuel_file}: {e} - using defaults")

    def _save_fuel_state(self) -> bool:
        """Save fuel state to disk. Returns True on success.

        PIT-FUEL-1: Enhanced logging to debug persistence issues.
        """
        fuel_file = self._get_fuel_state_path()
        try:
            config_dir = os.path.dirname(fuel_file)
            os.makedirs(config_dir, exist_ok=True)
            with open(fuel_file, 'w') as f:
                json.dump(self._fuel_strategy, f, indent=2)
            # PIT-FUEL-1: Log tank capacity specifically to verify persistence
            logger.info(f"PIT-FUEL-1: Saved fuel state to {fuel_file} - tank_capacity={self._fuel_strategy['tank_capacity_gal']} gal, "
                       f"current={self._fuel_strategy['current_fuel_gal']} gal")
            return True
        except Exception as e:
            logger.error(f"PIT-FUEL-1: Failed to save fuel state to {fuel_file}: {e}")
            return False

    # ============ Trip State Persistence (PIT-1R) ============

    def _get_trip_state_path(self) -> str:
        """Get the path to the trip state file."""
        config_dir = os.path.dirname(get_config_path())
        return os.path.join(config_dir, 'trip_state.json')

    def _load_trip_state(self) -> None:
        """Load persisted trip state from disk."""
        try:
            trip_file = self._get_trip_state_path()
            if os.path.exists(trip_file):
                with open(trip_file, 'r') as f:
                    saved = json.load(f)
                for key in ['trip_miles', 'trip_start_at']:
                    if key in saved:
                        self._trip_state[key] = saved[key]
                logger.info(f"Loaded trip state: {self._trip_state['trip_miles']:.1f} mi")
        except Exception as e:
            logger.warning(f"Could not load trip state: {e}")

    def _save_trip_state(self) -> bool:
        """Save trip state to disk. Returns True on success."""
        try:
            trip_file = self._get_trip_state_path()
            config_dir = os.path.dirname(trip_file)
            os.makedirs(config_dir, exist_ok=True)
            save_data = {
                'trip_miles': self._trip_state['trip_miles'],
                'trip_start_at': self._trip_state['trip_start_at'],
            }
            with open(trip_file, 'w') as f:
                json.dump(save_data, f, indent=2)
            return True
        except Exception as e:
            logger.error(f"Failed to save trip state: {e}")
            return False

    # ============ Tire State Persistence (PIT-5R) ============

    def _get_tire_state_path(self) -> str:
        """Get the path to the tire state file."""
        config_dir = os.path.dirname(get_config_path())
        return os.path.join(config_dir, 'tire_state.json')

    def _load_tire_state(self) -> None:
        """Load persisted tire state from disk."""
        try:
            tire_file = self._get_tire_state_path()
            if os.path.exists(tire_file):
                with open(tire_file, 'r') as f:
                    saved = json.load(f)
                for key in self._tire_state:
                    if key in saved:
                        self._tire_state[key] = saved[key]
                logger.info(f"Loaded tire state: brand={self._tire_state['brand']}")
            else:
                # First run: set baselines to current trip_miles so miles start at 0
                trip_miles = self._trip_state.get('trip_miles', 0.0)
                self._tire_state['front_trip_baseline'] = trip_miles
                self._tire_state['rear_trip_baseline'] = trip_miles
                self._save_tire_state()
                logger.info(f"Initialized tire state with baseline={trip_miles:.1f}")
        except Exception as e:
            logger.warning(f"Could not load tire state: {e}")

    def _save_tire_state(self) -> bool:
        """Save tire state to disk. Returns True on success."""
        try:
            tire_file = self._get_tire_state_path()
            config_dir = os.path.dirname(tire_file)
            os.makedirs(config_dir, exist_ok=True)
            with open(tire_file, 'w') as f:
                json.dump(self._tire_state, f, indent=2)
            return True
        except Exception as e:
            logger.error(f"Failed to save tire state: {e}")
            return False

    # ============ Camera Slot Normalization (CAM-CONTRACT-0) ============

    def _normalize_camera_slot(self, slot_id: str) -> str:
        """CAM-CONTRACT-1B: Normalize camera slot to canonical name.

        Accepts both canonical (main, cockpit, chase, suspension) and
        legacy names (pov, roof, front, rear) for backward compatibility.
        """
        if slot_id in {'main', 'cockpit', 'chase', 'suspension'}:
            return slot_id
        return self._camera_aliases.get(slot_id, slot_id)

    # ============ Desired Camera Persistence (PROD-3) ============

    def _get_desired_camera_path(self) -> str:
        """Get the path to the desired camera state file."""
        config_dir = os.path.dirname(get_config_path())
        return os.path.join(config_dir, 'desired_camera_state.json')

    def _load_desired_camera(self) -> None:
        """Load persisted desired camera from disk (reboot recovery)."""
        try:
            cam_file = self._get_desired_camera_path()
            if os.path.exists(cam_file):
                with open(cam_file, 'r') as f:
                    saved = json.load(f)
                camera = saved.get('desired_camera')
                # CAM-CONTRACT-1B: Accept both canonical and legacy names
                valid_cameras = {'main', 'cockpit', 'chase', 'suspension', 'pov', 'roof', 'front', 'rear'}
                if camera in valid_cameras:
                    # Normalize legacy names to canonical
                    camera = self._normalize_camera_slot(camera)
                    self._streaming_state['camera'] = camera
                    logger.info(f"Restored desired camera from disk: {camera}")
        except Exception as e:
            logger.warning(f"Could not load desired camera state: {e}")

    def _save_desired_camera(self, camera: str) -> bool:
        """Save desired camera to disk for reboot recovery. Returns True on success."""
        try:
            cam_file = self._get_desired_camera_path()
            config_dir = os.path.dirname(cam_file)
            os.makedirs(config_dir, exist_ok=True)
            with open(cam_file, 'w') as f:
                json.dump({
                    'desired_camera': camera,
                    'updated_at': int(time.time() * 1000),
                }, f, indent=2)
            return True
        except Exception as e:
            logger.error(f"Failed to save desired camera state: {e}")
            return False

    # ============ Program State Persistence (EDGE-PROG-3) ============

    def _get_program_state_path(self) -> str:
        """Get the path to the program state file."""
        # Use /opt/argus/state/ for consistency with stream_status.json
        return '/opt/argus/state/program_state.json'

    def _load_program_state(self) -> None:
        """Load persisted program state from disk (reboot recovery)."""
        try:
            state_file = self._get_program_state_path()
            if os.path.exists(state_file):
                with open(state_file, 'r') as f:
                    saved = json.load(f)
                # Merge saved state, but streaming is always False on startup
                for key in ['active_camera', 'stream_destination', 'last_switch_at',
                            'last_stream_start_at', 'last_error', 'updated_at']:
                    if key in saved and saved[key] is not None:
                        self._program_state[key] = saved[key]
                # Always start with streaming=False (FFmpeg not running yet)
                self._program_state['streaming'] = False
                logger.info(f"Loaded program state: camera={self._program_state['active_camera']}")
        except Exception as e:
            logger.warning(f"Could not load program state: {e}")

    def _save_program_state(self) -> bool:
        """Save program state to disk. Returns True on success."""
        try:
            state_file = self._get_program_state_path()
            os.makedirs(os.path.dirname(state_file), exist_ok=True)
            self._program_state['updated_at'] = int(time.time() * 1000)
            with open(state_file, 'w') as f:
                json.dump(self._program_state, f, indent=2)
            return True
        except Exception as e:
            logger.error(f"Failed to save program state: {e}")
            return False

    def _update_program_state(self, **kwargs) -> None:
        """Update program state fields and persist to disk."""
        for key, value in kwargs.items():
            if key in self._program_state:
                self._program_state[key] = value
        self._save_program_state()

    def _load_camera_mappings(self) -> None:
        """Load persisted camera device mappings from disk."""
        try:
            config_path = os.path.join(os.path.dirname(get_config_path()), 'camera_mappings.json')
            if os.path.exists(config_path):
                with open(config_path, 'r') as f:
                    saved = json.load(f)
                # CAM-CONTRACT-1B: Load canonical camera slots
                legacy_to_canonical = {'pov': 'cockpit', 'roof': 'chase', 'front': 'suspension', 'rear': 'suspension'}
                for role in ('main', 'cockpit', 'chase', 'suspension'):
                    if role in saved:
                        self._camera_devices[role] = saved[role]
                # Migrate legacy names if present in saved config
                for legacy, canonical in legacy_to_canonical.items():
                    if legacy in saved and canonical not in saved:
                        self._camera_devices[canonical] = saved[legacy]
                logger.info(f"Loaded camera mappings from disk")
        except Exception as e:
            logger.warning(f"Could not load camera mappings: {e}")

    # ============ TEAM-3: Fan Visibility Persistence ============

    def _get_fan_visibility_path(self) -> str:
        config_dir = os.path.dirname(get_config_path())
        return os.path.join(config_dir, 'fan_visibility.json')

    def _load_fan_visibility(self) -> None:
        try:
            path = self._get_fan_visibility_path()
            if os.path.exists(path):
                with open(path, 'r') as f:
                    data = json.load(f)
                self._fan_visibility = data.get('visible', True)
                logger.info(f"Loaded fan visibility: {self._fan_visibility}")
        except Exception as e:
            logger.warning(f"Could not load fan visibility: {e}")

    def _save_fan_visibility(self) -> bool:
        try:
            path = self._get_fan_visibility_path()
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w') as f:
                json.dump({'visible': self._fan_visibility}, f, indent=2)
            return True
        except Exception as e:
            logger.error(f"Failed to save fan visibility: {e}")
            return False

    # ============ TEAM-3: Telemetry Sharing Policy Persistence ============

    def _get_sharing_policy_path(self) -> str:
        config_dir = os.path.dirname(get_config_path())
        return os.path.join(config_dir, 'sharing_policy.json')

    def _load_sharing_policy(self) -> None:
        try:
            path = self._get_sharing_policy_path()
            if os.path.exists(path):
                with open(path, 'r') as f:
                    data = json.load(f)
                for key in ['allow_production', 'allow_fans', 'updated_at']:
                    if key in data:
                        self._sharing_policy[key] = data[key]
                logger.info(f"Loaded sharing policy: prod={len(self._sharing_policy['allow_production'])} fields, fans={len(self._sharing_policy['allow_fans'])} fields")
        except Exception as e:
            logger.warning(f"Could not load sharing policy: {e}")

    def _save_sharing_policy(self) -> bool:
        try:
            path = self._get_sharing_policy_path()
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w') as f:
                json.dump(self._sharing_policy, f, indent=2)
            return True
        except Exception as e:
            logger.error(f"Failed to save sharing policy: {e}")
            return False

    # ============ Pit Notes Persistence ============

    def _get_pit_notes_path(self) -> str:
        """Get the path to the pit notes file."""
        config_dir = os.path.dirname(get_config_path())
        return os.path.join(config_dir, 'pit_notes.json')

    def _load_pit_notes(self) -> None:
        """Load persisted pit notes from disk."""
        try:
            notes_file = self._get_pit_notes_path()
            if os.path.exists(notes_file):
                with open(notes_file, 'r') as f:
                    saved_notes = json.load(f)
                if isinstance(saved_notes, list):
                    self._pit_notes = saved_notes[:100]  # Keep max 100
                    logger.info(f"Loaded {len(self._pit_notes)} pit notes from disk")
        except Exception as e:
            logger.warning(f"Could not load pit notes: {e}")

    def _save_pit_notes(self) -> bool:
        """Save pit notes to disk. Returns True on success."""
        try:
            notes_file = self._get_pit_notes_path()
            config_dir = os.path.dirname(notes_file)
            os.makedirs(config_dir, exist_ok=True)
            with open(notes_file, 'w') as f:
                json.dump(self._pit_notes, f, indent=2)
            logger.debug(f"Saved {len(self._pit_notes)} pit notes to disk")
            return True
        except Exception as e:
            logger.error(f"Failed to save pit notes: {e}")
            return False

    # ============ PIT-COMMS-1: Background Pit Notes Sync ============

    async def _pit_notes_sync_loop(self) -> None:
        """Background task to sync unsynced pit notes to cloud.

        PIT-COMMS-1: Retries syncing notes every 30 seconds when cloud is connected.
        This ensures notes sent while offline get delivered when connectivity returns.

        LINK-2: Guards against missing event_id — notes stay queued until
        event_id becomes available (via heartbeat auto-discovery or settings).
        """
        logger.info("PIT-COMMS-1: Starting pit notes background sync loop")
        _event_id_warned = False
        while True:
            try:
                await asyncio.sleep(30)  # Check every 30 seconds

                # Only attempt sync if cloud is configured and connected
                if not (self.telemetry.cloud_connected and self.config.cloud_url and self.config.truck_token):
                    continue

                # LINK-2: Guard against missing event_id — cannot construct URL without it
                if not self.config.event_id:
                    if not _event_id_warned:
                        logger.warning("LINK-2: Cannot sync pit notes — no event_id yet (waiting for heartbeat auto-discovery)")
                        _event_id_warned = True
                    continue
                _event_id_warned = False

                # Find unsynced notes
                unsynced = [n for n in self._pit_notes if not n.get('synced', False)]
                if not unsynced:
                    continue

                logger.info(f"PIT-COMMS-1: Attempting to sync {len(unsynced)} unsynced notes")
                self._pit_notes_last_sync_attempt = int(time.time() * 1000)

                synced_count = 0
                async with httpx.AsyncClient() as client:
                    for note in unsynced:
                        try:
                            response = await client.post(
                                f"{self.config.cloud_url}/api/v1/events/{self.config.event_id}/pit-notes",
                                json={
                                    'vehicle_id': self.config.vehicle_id,
                                    'note': note.get('text', ''),
                                    'timestamp_ms': note.get('timestamp', int(time.time() * 1000))
                                },
                                headers={'X-Truck-Token': self.config.truck_token},
                                timeout=10.0
                            )
                            if response.status_code in (200, 201):
                                note['synced'] = True
                                synced_count += 1
                            else:
                                logger.warning(f"PIT-COMMS-1: Cloud rejected note: {response.status_code}")
                        except Exception as e:
                            logger.warning(f"PIT-COMMS-1: Failed to sync note: {e}")
                            break  # Stop on first failure, retry next cycle

                if synced_count > 0:
                    self._save_pit_notes()
                    logger.info(f"PIT-COMMS-1: Synced {synced_count} notes to cloud")

            except asyncio.CancelledError:
                logger.info("PIT-COMMS-1: Pit notes sync loop cancelled")
                break
            except Exception as e:
                logger.error(f"PIT-COMMS-1: Error in pit notes sync loop: {e}")
                await asyncio.sleep(30)  # Wait before retrying on error

    def get_pit_notes_sync_status(self) -> dict:
        """Get current pit notes sync status for UI display.

        PIT-COMMS-1: Returns sync statistics for the Comms tab.
        LINK-2: Added event_id and waiting_for_event fields.
        """
        unsynced = len([n for n in self._pit_notes if not n.get('synced', False)])
        synced = len([n for n in self._pit_notes if n.get('synced', False)])
        has_event_id = bool(self.config.event_id)
        return {
            'total': len(self._pit_notes),
            'synced': synced,
            'queued': unsynced,
            'cloud_connected': self.telemetry.cloud_connected,
            'cloud_configured': bool(self.config.cloud_url and self.config.truck_token),
            'event_id': self.config.event_id or None,
            'waiting_for_event': not has_event_id and bool(self.config.cloud_url and self.config.truck_token),
            'last_sync_attempt': self._pit_notes_last_sync_attempt,
        }

    # ============ Streaming Management ============

    def _get_camera_device(self, camera_name: str) -> Optional[str]:
        """Get the video device path for a camera name.

        PIT-CAM-PREVIEW-B: Uses canonical names for fallback probing.
        Accepts both canonical (main/cockpit/chase/suspension) and
        legacy (pov/roof/front) names via _normalize_camera_slot.
        """
        canonical = self._normalize_camera_slot(camera_name)
        device = self._camera_devices.get(canonical)
        if device and os.path.exists(device):
            return device
        # Probe alternate device nodes (USB cameras enumerate unpredictably)
        alt_devices = {
            "main": ["/dev/video0", "/dev/video1"],
            "cockpit": ["/dev/video2", "/dev/video3"],
            "chase": ["/dev/video4", "/dev/video5"],
            "suspension": ["/dev/video6", "/dev/video7"],
        }
        for alt in alt_devices.get(canonical, []):
            if os.path.exists(alt):
                return alt
        return None

    def _build_ffmpeg_cmd(self, camera_device: str, stream_key: str) -> list:
        """Build FFmpeg command for streaming to YouTube.

        STREAM-1: Uses shared stream_profiles module for preset-driven
        encoding settings.  Camera input is always 1920x1080 MJPEG;
        downscaling happens in the FFmpeg output chain via the scale filter.
        """
        from stream_profiles import build_ffmpeg_cmd, get_profile
        profile = get_profile(self._stream_profile)
        return build_ffmpeg_cmd(camera_device, stream_key, profile)

    async def start_streaming(self, camera: str = "main") -> Dict[str, Any]:
        """Start FFmpeg streaming to YouTube.

        STREAM-2: Returns structured error responses with error_code, message,
        and a status_code hint for the handler. The 'error' field is preserved
        for backward compatibility with the JS UI.
        """
        # Check if already streaming
        if self._ffmpeg_process and self._ffmpeg_process.poll() is None:
            return {
                "success": False,
                "error_code": "ALREADY_STREAMING",
                "message": "Already streaming.",
                "error": "Already streaming",
                "status_code": 409,
            }

        # Check for YouTube stream key
        if not self.config.youtube_stream_key:
            self._streaming_state['status'] = 'error'
            self._streaming_state['error'] = 'No YouTube stream key configured'
            return {
                "success": False,
                "error_code": "MISSING_YOUTUBE_KEY",
                "message": "Configure YouTube stream key in Settings.",
                "error": "No YouTube stream key configured. Set it in Settings.",
                "status_code": 400,
            }

        # Get camera device
        device = self._get_camera_device(camera)
        if not device:
            self._streaming_state['status'] = 'error'
            self._streaming_state['error'] = f'Camera {camera} not found'
            device_path = self._camera_devices.get(camera, 'unknown')
            return {
                "success": False,
                "error_code": "CAMERA_NOT_FOUND",
                "message": f"Camera '{camera}' not found at {device_path}",
                "error": f"Camera '{camera}' not found at {device_path}",
                "status_code": 400,
            }

        # Update state
        self._streaming_state['status'] = 'starting'
        self._streaming_state['camera'] = camera
        self._streaming_state['error'] = None

        try:
            cmd = self._build_ffmpeg_cmd(device, self.config.youtube_stream_key)
            # STREAM-4: Add -progress pipe:1 for health monitoring
            cmd = cmd[:1] + ["-progress", "pipe:1"] + cmd[1:]
            logger.info(f"Starting FFmpeg: camera={camera}, device={device}")

            self._ffmpeg_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL,
            )

            # Wait a moment to check if it started
            await asyncio.sleep(2)

            if self._ffmpeg_process.poll() is None:
                # Process is running
                self._streaming_state['status'] = 'live'
                self._streaming_state['started_at'] = int(time.time() * 1000)
                self._streaming_state['pid'] = self._ffmpeg_process.pid
                logger.info(f"Streaming started (PID: {self._ffmpeg_process.pid})")

                # STREAM-4: Start progress reader for health monitoring
                self._start_ffmpeg_progress_reader()
                # Record restart for health tracking
                self._stream_health["restart_timestamps"].append(time.time())
                # Trim old restart timestamps (keep last 10 minutes)
                cutoff = time.time() - 600
                self._stream_health["restart_timestamps"] = [
                    t for t in self._stream_health["restart_timestamps"] if t > cutoff
                ]

                return {"success": True, "status": "live", "camera": camera, "pid": self._ffmpeg_process.pid}
            else:
                # Process exited immediately
                stderr_text = self._ffmpeg_process.stderr.read().decode() if self._ffmpeg_process.stderr else ""
                err_msg = stderr_text[-500:] if stderr_text else "FFmpeg exited immediately"
                self._streaming_state['status'] = 'error'
                self._streaming_state['error'] = err_msg
                logger.error(f"FFmpeg failed to start: {err_msg}")
                return {
                    "success": False,
                    "error_code": "FFMPEG_EXITED",
                    "message": "FFmpeg exited immediately",
                    "error": err_msg,
                    "stderr": err_msg,
                    "status_code": 500,
                }

        except FileNotFoundError:
            self._streaming_state['status'] = 'error'
            self._streaming_state['error'] = 'FFmpeg not installed'
            return {
                "success": False,
                "error_code": "FFMPEG_MISSING",
                "message": "FFmpeg not installed",
                "error": "FFmpeg not installed. Run: sudo apt install ffmpeg",
                "fix": "sudo apt install -y ffmpeg",
                "status_code": 500,
            }
        except Exception as e:
            self._streaming_state['status'] = 'error'
            self._streaming_state['error'] = str(e)
            logger.error(f"Failed to start streaming: {e}")
            return {
                "success": False,
                "error_code": "EXCEPTION",
                "message": str(e),
                "error": str(e),
                "status_code": 500,
            }

    async def stop_streaming(self) -> Dict[str, Any]:
        """Stop FFmpeg streaming."""
        # STREAM-4: Cancel progress reader
        if self._ffmpeg_progress_reader_task and not self._ffmpeg_progress_reader_task.done():
            self._ffmpeg_progress_reader_task.cancel()
            self._ffmpeg_progress_reader_task = None

        if not self._ffmpeg_process:
            self._streaming_state['status'] = 'idle'
            return {"success": True, "status": "idle"}

        self._streaming_state['status'] = 'stopping'

        try:
            self._ffmpeg_process.terminate()
            try:
                self._ffmpeg_process.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                logger.warning("FFmpeg didn't terminate, killing...")
                self._ffmpeg_process.kill()
                self._ffmpeg_process.wait(timeout=2.0)

            self._ffmpeg_process = None
            self._streaming_state['status'] = 'idle'
            self._streaming_state['started_at'] = None
            self._streaming_state['pid'] = None
            logger.info("Streaming stopped")
            return {"success": True, "status": "idle"}

        except Exception as e:
            logger.error(f"Error stopping streaming: {e}")
            self._streaming_state['status'] = 'error'
            self._streaming_state['error'] = str(e)
            return {"success": False, "error": str(e)}

    def get_streaming_status(self) -> Dict[str, Any]:
        """Get current streaming status."""
        # Check if FFmpeg is still running (dashboard-managed process)
        if self._ffmpeg_process:
            poll_result = self._ffmpeg_process.poll()
            if poll_result is not None:
                # Process exited
                self._streaming_state['status'] = 'error' if poll_result != 0 else 'idle'
                error_msg = f"FFmpeg exited with code {poll_result}" if poll_result != 0 else None
                self._streaming_state['error'] = error_msg
                self._ffmpeg_process = None
                self._streaming_state['pid'] = None
                # STREAM-4: Track error for health summary
                if error_msg:
                    self._stream_health["last_error_summary"] = error_msg

        result = {
            "status": self._streaming_state['status'],
            "camera": self._streaming_state['camera'],
            "started_at": self._streaming_state['started_at'],
            "error": self._streaming_state['error'],
            "pid": self._streaming_state['pid'],
            "youtube_configured": bool(self.config.youtube_stream_key),
            "youtube_url": self.config.youtube_live_url or None,
            "stream_profile": self._stream_profile,
        }

        # EDGE-6: Also read supervisor status from argus-video service if available
        stream_status_file = '/opt/argus/state/stream_status.json'
        try:
            if os.path.exists(stream_status_file):
                with open(stream_status_file, 'r') as f:
                    supervisor = json.load(f)
                # Only use supervisor data if it's recent (< 30s old)
                if time.time() - supervisor.get('updated_at', 0) < 30:
                    result['supervisor'] = {
                        'state': supervisor.get('state', 'unknown'),
                        'restart_count': supervisor.get('restart_count', 0),
                        'total_restarts': supervisor.get('total_restarts', 0),
                        'last_error': supervisor.get('last_error', ''),
                        'next_retry_time': supervisor.get('next_retry_time'),
                        'backoff_delay_s': supervisor.get('backoff_delay_s', 0),
                        'auth_failure_count': supervisor.get('auth_failure_count', 0),
                    }
        except (json.JSONDecodeError, OSError):
            pass

        return result

    async def switch_camera(self, camera: str) -> Dict[str, Any]:
        """Switch to a different camera (restarts stream)."""
        if camera == self._streaming_state['camera'] and self._streaming_state['status'] == 'live':
            return {"success": True, "message": "Already on this camera"}

        was_streaming = self._streaming_state['status'] == 'live'

        if was_streaming:
            await self.stop_streaming()
            await asyncio.sleep(1)  # Brief pause between stop and start

        return await self.start_streaming(camera)

    # ============ STREAM-1: Stream Profile Management ============

    async def set_stream_profile(self, profile_name: str) -> Dict[str, Any]:
        """Switch to a new stream profile, restarting ffmpeg if live."""
        from stream_profiles import STREAM_PROFILES, save_profile_state, get_profile

        if profile_name not in STREAM_PROFILES:
            return {
                "success": False,
                "error": f"Unknown profile '{profile_name}'. "
                         f"Valid: {', '.join(STREAM_PROFILES.keys())}",
            }

        old_profile = self._stream_profile
        self._stream_profile = profile_name
        self._stream_auto_mode = False  # Manual override disables auto
        save_profile_state(profile_name, auto_mode=False)

        # STREAM-4: Manual change sets the auto ceiling and resets health
        self._stream_health["auto_profile_ceiling"] = profile_name
        self._stream_health["healthy_since"] = None

        result: Dict[str, Any] = {
            "success": True,
            "profile": profile_name,
            "previous": old_profile,
            "applied_at": int(time.time() * 1000),
        }

        # If currently streaming, restart with new profile
        if self._streaming_state['status'] == 'live':
            camera = self._streaming_state['camera']
            await self.stop_streaming()
            await asyncio.sleep(1)
            start_result = await self.start_streaming(camera)
            result["restarted"] = True
            result["stream_status"] = start_result.get("status", "unknown")
        else:
            result["restarted"] = False

        logger.info(f"Stream profile changed: {old_profile} -> {profile_name}")
        return result

    # ============ STREAM-4: Auto-Downshift Health Monitor ============

    # Profile ordering for step-down / step-up
    PROFILE_ORDER = ["1080p30", "720p30", "480p30", "360p30"]

    # Thresholds
    AUTO_SPEED_THRESHOLD = 0.90        # speed < 0.90x means unhealthy
    AUTO_UNHEALTHY_DURATION_S = 20     # Must be unhealthy for 20s before downshift
    AUTO_HEALTHY_DURATION_S = 120      # Must be healthy for 120s before upshift
    AUTO_RESTART_THRESHOLD = 3         # > 3 restarts in 5 min = unhealthy
    AUTO_RESTART_WINDOW_S = 300        # 5 minute window for restart counting
    AUTO_CHECK_INTERVAL_S = 5          # Check every 5 seconds
    AUTO_SPEED_WINDOW_S = 30           # Rolling window for speed samples

    def _start_ffmpeg_progress_reader(self):
        """Start a background task to read ffmpeg -progress pipe:1 output."""
        if self._ffmpeg_progress_reader_task and not self._ffmpeg_progress_reader_task.done():
            self._ffmpeg_progress_reader_task.cancel()
        self._ffmpeg_progress_reader_task = asyncio.create_task(self._read_ffmpeg_progress())

    async def _read_ffmpeg_progress(self):
        """Read ffmpeg progress output from stdout and extract speed values."""
        try:
            proc = self._ffmpeg_process
            if not proc or not proc.stdout:
                return

            loop = asyncio.get_event_loop()
            while self._running and proc and proc.poll() is None:
                try:
                    # Read line in executor to avoid blocking
                    line = await asyncio.wait_for(
                        loop.run_in_executor(None, proc.stdout.readline),
                        timeout=10.0,
                    )
                    if not line:
                        break
                    decoded = line.decode("utf-8", errors="replace").strip()

                    # Parse speed= from progress output (e.g. "speed=0.98x")
                    if decoded.startswith("speed="):
                        speed_str = decoded[6:].rstrip("x").strip()
                        if speed_str and speed_str != "N/A":
                            try:
                                speed_val = float(speed_str)
                                now = time.time()
                                self._stream_health["current_speed"] = speed_val
                                self._stream_health["speed_samples"].append((now, speed_val))
                                # Trim old samples
                                cutoff = now - self.AUTO_SPEED_WINDOW_S
                                self._stream_health["speed_samples"] = [
                                    (t, s) for t, s in self._stream_health["speed_samples"] if t > cutoff
                                ]
                            except ValueError:
                                pass

                except asyncio.TimeoutError:
                    continue
                except Exception:
                    break

        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.debug(f"[stream-health] Progress reader error: {e}")

    def _get_recent_restart_count(self) -> int:
        """Count stream restarts within the restart window."""
        cutoff = time.time() - self.AUTO_RESTART_WINDOW_S
        return sum(1 for t in self._stream_health["restart_timestamps"] if t > cutoff)

    def _get_avg_speed(self) -> Optional[float]:
        """Get average speed from recent samples."""
        samples = self._stream_health["speed_samples"]
        if not samples:
            return None
        cutoff = time.time() - self.AUTO_SPEED_WINDOW_S
        recent = [s for t, s in samples if t > cutoff]
        if not recent:
            return None
        return sum(recent) / len(recent)

    def _is_stream_unhealthy(self) -> bool:
        """
        Determine if the stream is unhealthy based on:
        1. FFmpeg speed < 0.90x sustained over the window
        2. Too many restarts in 5 minutes
        """
        # Check restart count
        if self._get_recent_restart_count() > self.AUTO_RESTART_THRESHOLD:
            return True

        # Check speed
        avg_speed = self._get_avg_speed()
        if avg_speed is not None and avg_speed < self.AUTO_SPEED_THRESHOLD:
            return True

        return False

    def _profile_index(self, profile: str) -> int:
        """Get index in PROFILE_ORDER (0=highest, 3=lowest)."""
        try:
            return self.PROFILE_ORDER.index(profile)
        except ValueError:
            return 0

    def _step_down_profile(self, current: str) -> Optional[str]:
        """Return the next lower profile, or None if already at lowest."""
        idx = self._profile_index(current)
        if idx < len(self.PROFILE_ORDER) - 1:
            return self.PROFILE_ORDER[idx + 1]
        return None

    def _step_up_profile(self, current: str, ceiling: str) -> Optional[str]:
        """Return the next higher profile (up to ceiling), or None if at ceiling."""
        idx = self._profile_index(current)
        ceiling_idx = self._profile_index(ceiling)
        if idx > ceiling_idx:
            return self.PROFILE_ORDER[idx - 1]
        return None

    async def _auto_downshift_loop(self):
        """
        STREAM-4: Background loop that monitors stream health and auto-adjusts profile.

        Rules:
        - Only active when auto_mode is True and streaming is live.
        - Downshift: if unhealthy for AUTO_UNHEALTHY_DURATION_S, step down one level.
        - Upshift: if healthy for AUTO_HEALTHY_DURATION_S, step up one level.
        - Never step up above the manual ceiling (auto_profile_ceiling).
        - Hysteresis: down fast (20s), up slow (120s).
        """
        unhealthy_since: Optional[float] = None

        while self._running:
            try:
                await asyncio.sleep(self.AUTO_CHECK_INTERVAL_S)

                # Skip if auto mode disabled or not streaming
                if not self._stream_auto_mode:
                    unhealthy_since = None
                    self._stream_health["healthy_since"] = None
                    continue

                if self._streaming_state.get("status") != "live":
                    unhealthy_since = None
                    self._stream_health["healthy_since"] = None
                    continue

                now = time.time()
                is_unhealthy = self._is_stream_unhealthy()

                if is_unhealthy:
                    # Reset healthy counter
                    self._stream_health["healthy_since"] = None

                    if unhealthy_since is None:
                        unhealthy_since = now
                        logger.info(
                            "[auto-downshift] Stream unhealthy detected: "
                            f"speed={self._stream_health.get('current_speed')}, "
                            f"restarts={self._get_recent_restart_count()}"
                        )

                    elapsed_unhealthy = now - unhealthy_since

                    if elapsed_unhealthy >= self.AUTO_UNHEALTHY_DURATION_S:
                        # Step down
                        next_profile = self._step_down_profile(self._stream_profile)
                        if next_profile:
                            old = self._stream_profile
                            logger.info(
                                f"[auto-downshift] Stepping down: {old} -> {next_profile} "
                                f"(unhealthy for {elapsed_unhealthy:.0f}s, "
                                f"speed={self._get_avg_speed():.2f})" if self._get_avg_speed() is not None else
                                f"[auto-downshift] Stepping down: {old} -> {next_profile} "
                                f"(unhealthy for {elapsed_unhealthy:.0f}s, restarts={self._get_recent_restart_count()})"
                            )
                            await self._auto_apply_profile(next_profile)
                            self._stream_health["last_downshift_at"] = now
                            unhealthy_since = None  # Reset after action
                        else:
                            logger.info("[auto-downshift] Already at lowest profile (360p30)")
                else:
                    # Healthy
                    unhealthy_since = None

                    if self._stream_health["healthy_since"] is None:
                        self._stream_health["healthy_since"] = now

                    healthy_duration = now - self._stream_health["healthy_since"]

                    if healthy_duration >= self.AUTO_HEALTHY_DURATION_S:
                        # Try stepping up (but not above ceiling)
                        ceiling = self._stream_health.get("auto_profile_ceiling", "1080p30")
                        next_profile = self._step_up_profile(self._stream_profile, ceiling)
                        if next_profile:
                            old = self._stream_profile
                            logger.info(
                                f"[auto-downshift] Stepping up: {old} -> {next_profile} "
                                f"(healthy for {healthy_duration:.0f}s, ceiling={ceiling})"
                            )
                            await self._auto_apply_profile(next_profile)
                            self._stream_health["last_upshift_at"] = now
                            self._stream_health["healthy_since"] = now  # Reset timer
                        # else: already at ceiling, nothing to do

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"[auto-downshift] Loop error: {e}")
                await asyncio.sleep(10)

    async def _auto_apply_profile(self, profile_name: str):
        """Apply a profile change from auto-downshift (does NOT change ceiling or disable auto)."""
        from stream_profiles import STREAM_PROFILES, save_profile_state

        if profile_name not in STREAM_PROFILES:
            return

        old_profile = self._stream_profile
        self._stream_profile = profile_name
        # Persist but keep auto_mode on
        save_profile_state(profile_name, auto_mode=True)

        # Clear speed samples since we're changing quality
        self._stream_health["speed_samples"] = []
        self._stream_health["current_speed"] = None

        # Restart stream if live
        if self._streaming_state.get("status") == "live":
            camera = self._streaming_state.get("camera", "main")
            await self.stop_streaming()
            await asyncio.sleep(1)
            await self.start_streaming(camera)

        logger.info(f"[auto-downshift] Profile applied: {old_profile} -> {profile_name}")

    def get_stream_health_summary(self) -> Dict[str, Any]:
        """Return non-sensitive health summary for API responses."""
        return {
            "current_speed": round(self._stream_health.get("current_speed") or 0, 2) if self._stream_health.get("current_speed") is not None else None,
            "avg_speed": round(self._get_avg_speed(), 2) if self._get_avg_speed() is not None else None,
            "recent_restarts": self._get_recent_restart_count(),
            "last_error_summary": self._stream_health.get("last_error_summary"),
            "healthy_since": int(self._stream_health["healthy_since"] * 1000) if self._stream_health.get("healthy_since") else None,
            "last_downshift_at": int(self._stream_health["last_downshift_at"] * 1000) if self._stream_health.get("last_downshift_at") else None,
            "last_upshift_at": int(self._stream_health["last_upshift_at"] * 1000) if self._stream_health.get("last_upshift_at") else None,
            "auto_profile_ceiling": self._stream_health.get("auto_profile_ceiling"),
        }

    def create_app(self) -> web.Application:
        """Create the web application."""
        app = web.Application()

        # Routes
        # EDGE-SETUP-1: Health endpoint for install script health check (no auth required)
        app.router.add_get('/health', self.handle_health)
        app.router.add_get('/', self.handle_index)
        app.router.add_get('/setup', self.handle_setup_page)
        app.router.add_post('/setup', self.handle_setup)
        app.router.add_get('/login', self.handle_login_page)
        app.router.add_post('/login', self.handle_login)
        app.router.add_get('/settings', self.handle_settings_page)
        app.router.add_post('/settings', self.handle_settings)
        app.router.add_post('/api/logout', self.handle_logout)
        app.router.add_post('/api/sync-youtube', self.handle_sync_youtube)
        app.router.add_get('/api/telemetry/stream', self.handle_sse)
        app.router.add_get('/api/telemetry/current', self.handle_current)

        # ADDED: New API endpoints for enhanced dashboard
        app.router.add_get('/api/cameras/status', self.handle_camera_status)
        app.router.add_get('/api/audio/level', self.handle_audio_level)
        app.router.add_post('/api/pit-note', self.handle_pit_note)
        app.router.add_get('/api/pit-notes', self.handle_get_pit_notes)
        app.router.add_get('/api/pit-notes/sync-status', self.handle_pit_notes_sync_status)  # PIT-COMMS-1

        # P1: Fuel and tire strategy endpoints
        app.router.add_get('/api/fuel/status', self.handle_fuel_status)
        app.router.add_post('/api/fuel/update', self.handle_fuel_update)
        app.router.add_post('/api/fuel/trip-reset', self.handle_trip_reset)
        app.router.add_get('/api/tires/status', self.handle_tires_status)
        app.router.add_post('/api/tires/update', self.handle_tires_update)

        # Device management endpoints
        app.router.add_get('/api/devices/scan', self.handle_device_scan)
        app.router.add_post('/api/devices/camera-mappings', self.handle_camera_mappings)
        app.router.add_post('/api/devices/gps-config', self.handle_gps_config)
        app.router.add_post('/api/devices/ant-pair', self.handle_ant_pair)
        app.router.add_post('/api/devices/restart-service', self.handle_restart_service)
        app.router.add_post('/api/devices/restart-all', self.handle_restart_all_services)

        # ADDED: Screenshot capture endpoints for stream control
        app.router.add_get('/api/cameras/screenshot/{camera}', self.handle_camera_screenshot)
        app.router.add_get('/api/cameras/screenshots/status', self.handle_screenshots_status)
        app.router.add_post('/api/cameras/screenshot/{camera}/capture', self.handle_capture_screenshot)

        # PIT-CAM-PREVIEW-B: Stable preview endpoints (canonical names)
        app.router.add_get('/api/cameras/preview/{camera}.jpg', self.handle_camera_screenshot)
        app.router.add_post('/api/cameras/preview/{camera}/capture', self.handle_capture_screenshot)

        # ADDED: Streaming control endpoints
        app.router.add_get('/api/streaming/status', self.handle_streaming_status)
        app.router.add_post('/api/streaming/start', self.handle_streaming_start)
        app.router.add_post('/api/streaming/stop', self.handle_streaming_stop)
        app.router.add_post('/api/streaming/switch-camera', self.handle_streaming_switch_camera)

        # EDGE-PROG-3: Program State endpoints (authoritative source of truth)
        app.router.add_get('/api/program/status', self.handle_program_status)
        app.router.add_post('/api/program/switch', self.handle_program_switch)

        # STREAM-1: Stream profile endpoints
        app.router.add_get('/api/stream/profile', self.handle_get_stream_profile)
        app.router.add_post('/api/stream/profile', self.handle_set_stream_profile)
        app.router.add_post('/api/stream/auto', self.handle_stream_auto)

        # ADDED: Course/GPX endpoints (Feature 4)
        app.router.add_get('/api/course', self.handle_get_course)
        app.router.add_post('/api/course/upload', self.handle_course_upload)
        app.router.add_post('/api/course/clear', self.handle_course_clear)

        # TEAM-3: Fan visibility & telemetry sharing (migrated from cloud)
        app.router.add_get('/api/team/visibility', self.handle_get_visibility)
        app.router.add_post('/api/team/visibility', self.handle_set_visibility)
        app.router.add_get('/api/team/sharing-policy', self.handle_get_sharing_policy)
        app.router.add_post('/api/team/sharing-policy', self.handle_set_sharing_policy)

        # EDGE-4: Readiness aggregation endpoint
        app.router.add_get('/api/edge/status', self.handle_edge_status)

        return app

    def _get_session(self, request: web.Request) -> Optional[str]:
        """Get session token from cookie."""
        return request.cookies.get('pit_session')

    def _is_authenticated(self, request: web.Request) -> bool:
        """Check if request is authenticated."""
        token = self._get_session(request)
        return self.sessions.validate_session(token) if token else False

    async def handle_health(self, request: web.Request) -> web.Response:
        """EDGE-SETUP-1: Health check endpoint for install script (no auth required).

        Returns 200 OK with basic status info.
        Used by install.sh to verify dashboard is running.
        """
        return web.json_response({
            'status': 'ok',
            'configured': self.config.is_configured,
            'vehicle_number': self.config.vehicle_number if self.config.is_configured else None,
        })

    async def handle_index(self, request: web.Request) -> web.Response:
        """Serve the dashboard, or redirect to setup/login."""
        # If not configured, redirect to setup wizard
        if not self.config.is_configured:
            raise web.HTTPFound('/setup')

        # If not authenticated, redirect to login
        if not self._is_authenticated(request):
            raise web.HTTPFound('/login')

        # EDGE-CLOUD-2: Generate CSP nonce for this request
        nonce = secrets.token_urlsafe(16)

        # Inject vehicle number into page
        html = DASHBOARD_HTML.replace(
            "window.VEHICLE_NUMBER || '---'",
            f"'{self.config.vehicle_number}'"
        )
        # Inject nonce into all script tags
        html = html.replace('__CSP_NONCE__', nonce)

        # Show/hide tunnel warning banner based on config
        tunnel_display = 'none' if self.config.cloudflare_tunnel_url else 'block'
        html = html.replace('__TUNNEL_BANNER_DISPLAY__', tunnel_display)

        # EDGE-CLOUD-2: Set Content-Security-Policy header
        # EDGE-MAP-0: Added tile provider domains to img-src and connect-src
        csp = (
            f"default-src 'self'; "
            f"script-src 'nonce-{nonce}' https://cdn.jsdelivr.net https://unpkg.com; "
            f"style-src 'self' 'unsafe-inline' https://unpkg.com; "
            f"img-src 'self' data: https://*.tile.opentopomap.org https://*.basemaps.cartocdn.com https://*.tile.openstreetmap.org; "
            f"connect-src 'self' https://*.tile.opentopomap.org https://*.basemaps.cartocdn.com https://*.tile.openstreetmap.org; "
            f"font-src 'self'; "
            f"frame-src https://www.youtube.com https://www.youtube-nocookie.com; "
            f"object-src 'none'"
        )
        response = web.Response(text=html, content_type='text/html')
        response.headers['Content-Security-Policy'] = csp
        return response

    async def handle_setup_page(self, request: web.Request) -> web.Response:
        """Serve the setup wizard page."""
        # If already configured, redirect to login
        if self.config.is_configured:
            raise web.HTTPFound('/login')

        html = SETUP_HTML.replace('{error}', '')
        return web.Response(text=html, content_type='text/html')

    async def handle_setup(self, request: web.Request) -> web.Response:
        """Handle setup form submission."""
        # If already configured, reject
        if self.config.is_configured:
            raise web.HTTPFound('/login')

        data = await request.post()
        password = data.get('password', '')
        password_confirm = data.get('password_confirm', '')

        # Validate passwords match
        if password != password_confirm:
            html = SETUP_HTML.replace(
                '{error}',
                '<div class="server-error">Passwords do not match. Please try again.</div>'
            )
            return web.Response(text=html, content_type='text/html', status=400)

        # Validate password length
        if len(password) < 4:
            html = SETUP_HTML.replace(
                '{error}',
                '<div class="server-error">Password must be at least 4 characters.</div>'
            )
            return web.Response(text=html, content_type='text/html', status=400)

        # Validate Cloudflare Tunnel fields (required for CGNAT-proof access)
        cf_token = data.get('cloudflare_tunnel_token', '').strip()
        cf_url = data.get('cloudflare_tunnel_url', '').strip()

        if not cf_token:
            html = SETUP_HTML.replace(
                '{error}',
                '<div class="server-error">Cloudflare Tunnel Token is required. '
                'Create a tunnel at Cloudflare Zero Trust &gt; Networks &gt; Tunnels.</div>'
            )
            return web.Response(text=html, content_type='text/html', status=400)

        if not cf_url or not cf_url.startswith('https://'):
            html = SETUP_HTML.replace(
                '{error}',
                '<div class="server-error">Cloudflare Tunnel URL is required and must start with https://.</div>'
            )
            return web.Response(text=html, content_type='text/html', status=400)

        # Save configuration
        self.config.set_password(password)
        self.config.vehicle_number = data.get('vehicle_number', '').strip() or '000'
        # EDGE-CLOUD-1: Validate cloud_url — add http:// if no scheme present
        cloud_url = data.get('cloud_url', '').strip()
        if cloud_url and not cloud_url.startswith(('http://', 'https://')):
            cloud_url = f"http://{cloud_url}"
        self.config.cloud_url = cloud_url.rstrip('/')
        self.config.truck_token = data.get('truck_token', '').strip()
        self.config.event_id = data.get('event_id', '').strip()
        self.config.youtube_stream_key = data.get('youtube_stream_key', '').strip()
        self.config.youtube_live_url = data.get('youtube_live_url', '').strip()
        self.config.cloudflare_tunnel_token = cf_token
        self.config.cloudflare_tunnel_url = cf_url.rstrip('/')

        try:
            self.config.save()
            logger.info("Setup completed successfully")
            # Sync credentials to /etc/argus/config.env for systemd services
            self._write_systemd_env()
            # Write /etc/cloudflared/config.yml and start tunnel if token is set
            self._activate_cloudflare_tunnel()
            # LINK-1: Restart cloud status loop to pick up new cloud_url/truck_token
            self._restart_cloud_status_loop()
        except Exception as e:
            logger.error(f"Failed to save config: {e}")
            html = SETUP_HTML.replace(
                '{error}',
                f'<div class="server-error">Failed to save configuration: {e}</div>'
            )
            return web.Response(text=html, content_type='text/html', status=500)

        # Create session and redirect to dashboard
        token = self.sessions.create_session()
        response = web.HTTPFound('/')
        response.set_cookie('pit_session', token, max_age=86400, httponly=True)
        return response

    async def handle_login_page(self, request: web.Request) -> web.Response:
        """Serve the login page."""
        # If not configured, redirect to setup
        if not self.config.is_configured:
            raise web.HTTPFound('/setup')

        if self._is_authenticated(request):
            raise web.HTTPFound('/')

        html = LOGIN_HTML.replace('{error}', '')
        return web.Response(text=html, content_type='text/html')

    async def handle_login(self, request: web.Request) -> web.Response:
        """Handle login form submission."""
        # If not configured, redirect to setup
        if not self.config.is_configured:
            raise web.HTTPFound('/setup')

        data = await request.post()
        password = data.get('password', '')

        if self.config.check_password(password):
            # Create session
            token = self.sessions.create_session()
            response = web.HTTPFound('/')
            response.set_cookie('pit_session', token, max_age=86400, httponly=True)
            return response

        # Invalid password
        html = LOGIN_HTML.replace(
            '{error}',
            '<div class="error">Invalid password. Please try again.</div>'
        )
        return web.Response(text=html, content_type='text/html', status=401)

    async def handle_settings_page(self, request: web.Request) -> web.Response:
        """Serve the settings page."""
        if not self.config.is_configured:
            raise web.HTTPFound('/setup')
        if not self._is_authenticated(request):
            raise web.HTTPFound('/login')

        html = SETTINGS_HTML.replace('{message}', '')
        html = html.replace('{vehicle_number}', self.config.vehicle_number or '')
        html = html.replace('{cloud_url}', self.config.cloud_url or '')
        html = html.replace('{truck_token}', self.config.truck_token or '')
        html = html.replace('{event_id}', self.config.event_id or '')
        html = html.replace('{youtube_stream_key}', self.config.youtube_stream_key or '')
        html = html.replace('{youtube_live_url}', self.config.youtube_live_url or '')
        html = html.replace('{cloudflare_tunnel_token}', self.config.cloudflare_tunnel_token or '')
        html = html.replace('{cloudflare_tunnel_url}', self.config.cloudflare_tunnel_url or '')
        return web.Response(text=html, content_type='text/html')

    async def handle_settings(self, request: web.Request) -> web.Response:
        """Handle settings form submission."""
        if not self.config.is_configured:
            raise web.HTTPFound('/setup')
        if not self._is_authenticated(request):
            raise web.HTTPFound('/login')

        data = await request.post()

        # Update configuration
        self.config.vehicle_number = data.get('vehicle_number', '').strip() or '000'
        # EDGE-CLOUD-1: Validate cloud_url — add http:// if no scheme present
        cloud_url = data.get('cloud_url', '').strip()
        if cloud_url and not cloud_url.startswith(('http://', 'https://')):
            cloud_url = f"http://{cloud_url}"
        self.config.cloud_url = cloud_url.rstrip('/')
        self.config.truck_token = data.get('truck_token', '').strip()
        self.config.event_id = data.get('event_id', '').strip()
        self.config.youtube_stream_key = data.get('youtube_stream_key', '').strip()
        self.config.youtube_live_url = data.get('youtube_live_url', '').strip()
        self.config.cloudflare_tunnel_token = data.get('cloudflare_tunnel_token', '').strip()
        cf_url = data.get('cloudflare_tunnel_url', '').strip()
        self.config.cloudflare_tunnel_url = cf_url.rstrip('/')

        try:
            self.config.save()
            logger.info("Settings updated successfully")
            # Sync credentials to /etc/argus/config.env for systemd services
            self._write_systemd_env()
            # Write /etc/cloudflared/config.yml and restart tunnel if token changed
            self._activate_cloudflare_tunnel()
            # LINK-1: Restart cloud status loop to pick up new cloud_url/truck_token
            self._restart_cloud_status_loop()
            message = '<div class="success">Settings saved successfully!</div>'
        except Exception as e:
            logger.error(f"Failed to save settings: {e}")
            message = f'<div class="error">Failed to save settings: {e}</div>'

        html = SETTINGS_HTML.replace('{message}', message)
        html = html.replace('{vehicle_number}', self.config.vehicle_number or '')
        html = html.replace('{cloud_url}', self.config.cloud_url or '')
        html = html.replace('{truck_token}', self.config.truck_token or '')
        html = html.replace('{event_id}', self.config.event_id or '')
        html = html.replace('{youtube_stream_key}', self.config.youtube_stream_key or '')
        html = html.replace('{youtube_live_url}', self.config.youtube_live_url or '')
        html = html.replace('{cloudflare_tunnel_token}', self.config.cloudflare_tunnel_token or '')
        html = html.replace('{cloudflare_tunnel_url}', self.config.cloudflare_tunnel_url or '')
        return web.Response(text=html, content_type='text/html')

    # ============ TEAM-3: Fan Visibility & Telemetry Sharing Handlers ============

    async def handle_get_visibility(self, request: web.Request) -> web.Response:
        """Get current fan visibility state."""
        if not self._is_authenticated(request):
            return web.json_response({'error': 'Unauthorized'}, status=401)
        return web.json_response({'visible': self._fan_visibility})

    async def handle_set_visibility(self, request: web.Request) -> web.Response:
        """Set fan visibility and sync to cloud."""
        if not self._is_authenticated(request):
            return web.json_response({'success': False, 'error': 'Unauthorized'}, status=401)

        data = await request.json()
        visible = bool(data.get('visible', True))
        self._fan_visibility = visible
        self._save_fan_visibility()
        logger.info(f"Fan visibility set to: {visible}")

        # Try to sync to cloud
        synced = False
        if self.config.cloud_url and self.config.truck_token and HTTPX_AVAILABLE:
            try:
                async with httpx.AsyncClient(timeout=10.0) as client:
                    login_resp = await client.post(
                        f"{self.config.cloud_url}/api/v1/team/login",
                        json={
                            "vehicle_number": self.config.vehicle_number,
                            "team_token": self.config.truck_token,
                        }
                    )
                    if login_resp.status_code == 200:
                        token = login_resp.json().get('access_token')
                        resp = await client.put(
                            f"{self.config.cloud_url}/api/v1/team/visibility",
                            params={"visible": str(visible).lower()},
                            headers={"Authorization": f"Bearer {token}"},
                        )
                        synced = resp.status_code == 200
                        if synced:
                            logger.info(f"Visibility synced to cloud: {visible}")
                        else:
                            logger.warning(f"Cloud visibility sync failed: {resp.status_code}")
            except Exception as e:
                logger.warning(f"Could not sync visibility to cloud: {e}")

        return web.json_response({'success': True, 'visible': visible, 'synced': synced})

    async def handle_get_sharing_policy(self, request: web.Request) -> web.Response:
        """Get current telemetry sharing policy."""
        if not self._is_authenticated(request):
            return web.json_response({'error': 'Unauthorized'}, status=401)
        return web.json_response({
            'allow_production': self._sharing_policy['allow_production'],
            'allow_fans': self._sharing_policy['allow_fans'],
            'updated_at': self._sharing_policy.get('updated_at'),
        })

    async def handle_set_sharing_policy(self, request: web.Request) -> web.Response:
        """Update telemetry sharing policy and sync to cloud."""
        if not self._is_authenticated(request):
            return web.json_response({'success': False, 'error': 'Unauthorized'}, status=401)

        data = await request.json()
        allow_production = data.get('allow_production', [])
        allow_fans = data.get('allow_fans', [])

        # Enforce constraint: fans is subset of production
        allow_fans = [f for f in allow_fans if f in allow_production]

        self._sharing_policy['allow_production'] = allow_production
        self._sharing_policy['allow_fans'] = allow_fans
        self._sharing_policy['updated_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        self._save_sharing_policy()
        logger.info(f"Sharing policy updated: prod={len(allow_production)}, fans={len(allow_fans)}")

        # Try to sync to cloud
        synced = False
        if self.config.cloud_url and self.config.truck_token and HTTPX_AVAILABLE:
            try:
                async with httpx.AsyncClient(timeout=10.0) as client:
                    login_resp = await client.post(
                        f"{self.config.cloud_url}/api/v1/team/login",
                        json={
                            "vehicle_number": self.config.vehicle_number,
                            "team_token": self.config.truck_token,
                        }
                    )
                    if login_resp.status_code == 200:
                        token = login_resp.json().get('access_token')
                        resp = await client.put(
                            f"{self.config.cloud_url}/api/v1/team/sharing-policy",
                            headers={
                                "Authorization": f"Bearer {token}",
                                "Content-Type": "application/json",
                            },
                            json={
                                "allow_production": allow_production,
                                "allow_fans": allow_fans,
                            }
                        )
                        synced = resp.status_code == 200
                        if synced:
                            logger.info("Sharing policy synced to cloud")
                        else:
                            logger.warning(f"Cloud sharing policy sync failed: {resp.status_code}")
            except Exception as e:
                logger.warning(f"Could not sync sharing policy to cloud: {e}")

        return web.json_response({
            'success': True,
            'allow_production': allow_production,
            'allow_fans': allow_fans,
            'synced': synced,
        })

    async def handle_sync_youtube(self, request: web.Request) -> web.Response:
        """Sync YouTube URL to cloud server."""
        if not self._is_authenticated(request):
            return web.json_response({'success': False, 'error': 'Unauthorized'}, status=401)

        # Check if we have the required config
        if not self.config.cloud_url or not self.config.truck_token:
            return web.json_response({
                'success': False,
                'error': 'Cloud URL and truck token required for sync'
            })

        if not self.config.youtube_live_url:
            return web.json_response({
                'success': False,
                'error': 'YouTube live URL not configured'
            })

        if not HTTPX_AVAILABLE:
            return web.json_response({
                'success': False,
                'error': 'httpx not installed - cannot sync to cloud'
            })

        try:
            # Sync video feed to cloud using team API
            async with httpx.AsyncClient(timeout=10.0) as client:
                # First, we need to login to get a team token
                login_resp = await client.post(
                    f"{self.config.cloud_url}/api/v1/team/login",
                    json={
                        "vehicle_number": self.config.vehicle_number,
                        "team_token": self.config.truck_token,
                    }
                )

                if login_resp.status_code != 200:
                    return web.json_response({
                        'success': False,
                        'error': f'Cloud login failed: {login_resp.text}'
                    })

                auth_data = login_resp.json()
                access_token = auth_data.get('access_token')

                # Now update the video feed
                video_resp = await client.put(
                    f"{self.config.cloud_url}/api/v1/team/video",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={
                        "camera_name": "main",  # Default camera
                        "youtube_url": self.config.youtube_live_url,
                        "permission_level": "public",
                    }
                )

                if video_resp.status_code != 200:
                    return web.json_response({
                        'success': False,
                        'error': f'Failed to update video: {video_resp.text}'
                    })

                logger.info(f"YouTube URL synced to cloud: {self.config.youtube_live_url}")
                return web.json_response({'success': True})

        except Exception as e:
            logger.error(f"Failed to sync YouTube URL: {e}")
            return web.json_response({
                'success': False,
                'error': str(e)
            })

    async def handle_logout(self, request: web.Request) -> web.Response:
        """Handle logout."""
        token = self._get_session(request)
        if token:
            self.sessions.invalidate_session(token)

        response = web.Response(text='OK')
        response.del_cookie('pit_session')
        return response

    async def handle_sse(self, request: web.Request) -> web.StreamResponse:
        """Handle SSE connection for real-time telemetry."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        response = web.StreamResponse()
        response.headers['Content-Type'] = 'text/event-stream'
        response.headers['Cache-Control'] = 'no-cache'
        response.headers['Connection'] = 'keep-alive'
        await response.prepare(request)

        self.sse_clients.add(response)
        logger.info(f"SSE client connected ({len(self.sse_clients)} total)")

        try:
            while True:
                # Send current telemetry
                data = json.dumps(self.telemetry.to_dict())
                await response.write(f"data: {data}\n\n".encode())
                await asyncio.sleep(0.1)  # 10 Hz update rate
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.debug(f"SSE client disconnected: {e}")
        finally:
            self.sse_clients.discard(response)
            logger.info(f"SSE client disconnected ({len(self.sse_clients)} remaining)")

        return response

    async def handle_current(self, request: web.Request) -> web.Response:
        """Return current telemetry as JSON."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        return web.json_response(self.telemetry.to_dict())

    # ============ EDGE-4: Readiness Aggregation ============

    async def handle_edge_status(self, request: web.Request) -> web.Response:
        """Return edge readiness status from aggregator JSON file.

        Reads /opt/argus/state/edge_status.json written by edge_status.sh.
        Falls back to running edge_status.sh --json if file is stale or missing.

        EDGE-4: Readiness Aggregation — Boot Timing
        """
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        status_file = '/opt/argus/state/edge_status.json'
        boot_timing_file = '/opt/argus/state/boot_timing.json'
        stale_threshold_sec = 30  # Consider file stale after 30s

        result = {
            'status': 'UNKNOWN',
            'tier1': {},
            'tier2': {},
            'boot_timing': None,
            'source': 'none',
            'timestamp_ms': int(time.time() * 1000),
        }

        # Try reading cached status file first
        status_data = None
        try:
            if os.path.exists(status_file):
                with open(status_file, 'r') as f:
                    status_data = json.load(f)
                # Check staleness
                file_age = time.time() - os.path.getmtime(status_file)
                if file_age > stale_threshold_sec:
                    status_data = None  # Stale, re-run
                else:
                    result['source'] = 'cached'
        except (json.JSONDecodeError, OSError):
            status_data = None

        # If no cached data, try running edge_status.sh --json
        if status_data is None:
            try:
                script_path = os.path.join(
                    os.path.dirname(os.path.abspath(__file__)),
                    'scripts', 'edge_status.sh'
                )
                if os.path.exists(script_path):
                    proc = await asyncio.create_subprocess_exec(
                        script_path, '--json',
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE,
                    )
                    stdout, _ = await asyncio.wait_for(
                        proc.communicate(), timeout=10.0
                    )
                    # Read the JSON file it wrote
                    if os.path.exists(status_file):
                        with open(status_file, 'r') as f:
                            status_data = json.load(f)
                        result['source'] = 'live'
            except (asyncio.TimeoutError, OSError, json.JSONDecodeError) as e:
                logger.warning(f"edge_status.sh failed: {e}")

        # Populate result from status data
        if status_data:
            result['status'] = status_data.get('status', 'UNKNOWN')
            result['tier1'] = status_data.get('tier1', {})
            result['tier2'] = status_data.get('tier2', {})
            if 'checked_at' in status_data:
                result['checked_at'] = status_data['checked_at']
            # EDGE-5: Disk and queue metrics
            if 'disk_pct' in status_data:
                result['disk_pct'] = status_data['disk_pct']
            if 'queue_depth' in status_data:
                result['queue_depth'] = status_data['queue_depth']
            if 'queue_mb' in status_data:
                result['queue_mb'] = status_data['queue_mb']

        # Read boot timing separately
        try:
            if os.path.exists(boot_timing_file):
                with open(boot_timing_file, 'r') as f:
                    result['boot_timing'] = json.load(f)
        except (json.JSONDecodeError, OSError):
            pass

        return web.json_response(result)

    async def handle_camera_status(self, request: web.Request) -> web.Response:
        """Return camera status from V4L2 device detection."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        # Refresh camera status
        await self._detect_cameras()

        return web.json_response({
            'cameras': self._camera_status,
            'timestamp': int(time.time() * 1000)
        })

    # ============ Streaming API Handlers ============

    async def handle_streaming_status(self, request: web.Request) -> web.Response:
        """Return current streaming status."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        status = self.get_streaming_status()
        return web.json_response(status)

    async def handle_streaming_start(self, request: web.Request) -> web.Response:
        """Start streaming to YouTube."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            camera = data.get('camera', 'main')
        except Exception:
            camera = 'main'

        result = await self.start_streaming(camera)
        # STREAM-2: Use structured status_code from result, default to 200/400
        if result.get('success'):
            status_code = 200
        else:
            status_code = result.pop('status_code', 400)
        # STREAM-2: Log every request with outcome
        logger.info(f"POST /api/streaming/start camera={camera} status={status_code} error_code={result.get('error_code', 'none')}")
        return web.json_response(result, status=status_code)

    async def handle_streaming_stop(self, request: web.Request) -> web.Response:
        """Stop streaming."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        result = await self.stop_streaming()
        return web.json_response(result)

    async def handle_streaming_switch_camera(self, request: web.Request) -> web.Response:
        """Switch active streaming camera."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            camera = data.get('camera')
            if not camera:
                return web.json_response({'error': 'camera field required'}, status=400)
        except:
            return web.json_response({'error': 'Invalid JSON'}, status=400)

        result = await self.switch_camera(camera)
        status_code = 200 if result.get('success') else 400
        return web.json_response(result, status=status_code)

    # ============ EDGE-PROG-3: Program State API Handlers ============

    async def handle_program_status(self, request: web.Request) -> web.Response:
        """GET /api/program/status — single authoritative program state.

        EDGE-PROG-3: Returns the unified program state that both Pit Crew UI
        and Cloud camera switching should use as source of truth.
        """
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        # Sync streaming state from FFmpeg process check
        if self._ffmpeg_process:
            poll_result = self._ffmpeg_process.poll()
            if poll_result is not None:
                # FFmpeg exited - update program state
                self._update_program_state(
                    streaming=False,
                    last_error=f"FFmpeg exited with code {poll_result}" if poll_result != 0 else None
                )
                self._ffmpeg_process = None
            else:
                # FFmpeg still running
                if not self._program_state['streaming']:
                    self._update_program_state(streaming=True)
        else:
            if self._program_state['streaming']:
                self._update_program_state(streaming=False)

        # Read supervisor status for additional context
        supervisor_state = None
        stream_status_file = '/opt/argus/state/stream_status.json'
        try:
            if os.path.exists(stream_status_file):
                with open(stream_status_file, 'r') as f:
                    supervisor = json.load(f)
                if time.time() - supervisor.get('updated_at', 0) < 30:
                    supervisor_state = supervisor.get('state', 'unknown')
        except (json.JSONDecodeError, OSError):
            pass

        response = {
            **self._program_state,
            'supervisor_state': supervisor_state,
            'youtube_configured': bool(self.config.youtube_stream_key),
            'youtube_url': self.config.youtube_live_url or None,
            'stream_profile': self._stream_profile,
        }
        return web.json_response(response)

    async def handle_program_switch(self, request: web.Request) -> web.Response:
        """POST /api/program/switch — switch active camera in program feed.

        EDGE-PROG-3: This is the authoritative camera switch endpoint.
        Updates program state only AFTER the streaming pipeline truly switches.
        """
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            camera = data.get('camera')
            if not camera:
                return web.json_response({'error': 'camera field required'}, status=400)
            # CAM-CONTRACT-1B: Accept both canonical and legacy camera names
            all_valid = {'main', 'cockpit', 'chase', 'suspension', 'pov', 'roof', 'front', 'rear'}
            if camera not in all_valid:
                return web.json_response({'error': f'Invalid camera: {camera}. Valid: main, cockpit, chase, suspension'}, status=400)
            camera = self._normalize_camera_slot(camera)
        except Exception:
            return web.json_response({'error': 'Invalid JSON'}, status=400)

        # Check if already on this camera
        if camera == self._program_state['active_camera'] and self._program_state['streaming']:
            return web.json_response({
                'success': True,
                'message': 'Already on this camera',
                'program_state': self._program_state,
            })

        # Rate limit camera switches
        now = time.time()
        if now - self._last_camera_switch_at < self._camera_switch_cooldown_s:
            return web.json_response({
                'success': False,
                'error': 'Camera switch rate limited. Please wait.',
            }, status=429)
        self._last_camera_switch_at = now

        # Perform the actual switch
        result = await self.switch_camera(camera)

        if result.get('success'):
            # Update program state AFTER successful switch
            switch_time = int(time.time() * 1000)
            self._update_program_state(
                active_camera=camera,
                streaming=True,
                last_switch_at=switch_time,
                last_stream_start_at=switch_time,
                last_error=None,
            )
            # Also persist desired camera for reboot recovery
            self._save_desired_camera(camera)

            return web.json_response({
                'success': True,
                'message': f'Switched to {camera}',
                'program_state': self._program_state,
            })
        else:
            # Update program state with error
            self._update_program_state(
                last_error=result.get('error', 'Switch failed'),
            )
            return web.json_response({
                'success': False,
                'error': result.get('error', 'Switch failed'),
                'program_state': self._program_state,
            }, status=400)

    # ============ STREAM-1: Stream Profile API Handlers ============

    async def handle_get_stream_profile(self, request: web.Request) -> web.Response:
        """GET /api/stream/profile — current profile + available profiles."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        from stream_profiles import list_profiles, get_profile
        current = get_profile(self._stream_profile)
        response = {
            "current": self._stream_profile,
            "current_detail": current.to_dict(),
            "auto_mode": self._stream_auto_mode,
            "available": list_profiles(),
            # STREAM-4: Health monitoring data
            "health": self.get_stream_health_summary(),
        }
        return web.json_response(response)

    async def handle_set_stream_profile(self, request: web.Request) -> web.Response:
        """POST /api/stream/profile — set profile (manual override)."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            profile_name = data.get('profile')
            if not profile_name:
                return web.json_response({'error': 'profile field required'}, status=400)
        except Exception:
            return web.json_response({'error': 'Invalid JSON'}, status=400)

        result = await self.set_stream_profile(profile_name)
        status_code = 200 if result.get('success') else 400
        return web.json_response(result, status=status_code)

    async def handle_stream_auto(self, request: web.Request) -> web.Response:
        """POST /api/stream/auto — enable/disable auto mode (stub)."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            enabled = bool(data.get('enabled', False))
        except Exception:
            return web.json_response({'error': 'Invalid JSON'}, status=400)

        from stream_profiles import save_profile_state
        self._stream_auto_mode = enabled
        save_profile_state(self._stream_profile, auto_mode=enabled)

        # STREAM-4: When enabling auto, set current profile as the ceiling
        if enabled:
            self._stream_health["auto_profile_ceiling"] = self._stream_profile
            self._stream_health["healthy_since"] = None
            logger.info(f"[auto-downshift] Auto mode enabled, ceiling={self._stream_profile}")
        else:
            logger.info("[auto-downshift] Auto mode disabled")

        return web.json_response({
            "success": True,
            "auto_mode": enabled,
            "profile": self._stream_profile,
            "auto_profile_ceiling": self._stream_health.get("auto_profile_ceiling"),
        })

    async def handle_audio_level(self, request: web.Request) -> web.Response:
        """Return current audio level from ALSA monitoring."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        return web.json_response({
            'level_db': round(self._audio_level, 1),
            'last_activity_ms': self._last_audio_activity,
            'is_active': (time.time() * 1000 - self._last_audio_activity) < 5000,
            'timestamp': int(time.time() * 1000)
        })

    async def handle_pit_note(self, request: web.Request) -> web.Response:
        """Handle pit note submission."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            note_text = data.get('note', '').strip()

            if not note_text:
                return web.json_response({'error': 'Note text required'}, status=400)

            # Create note with timestamp and metadata
            note = {
                'id': f"note_{int(time.time() * 1000)}",
                'text': note_text,
                'timestamp': int(time.time() * 1000),
                'vehicle_id': self.config.vehicle_id,
                'event_id': self.config.event_id,
                'synced': False
            }

            # Add to local notes (keep last 100)
            self._pit_notes.insert(0, note)
            self._pit_notes = self._pit_notes[:100]

            # Persist to disk
            self._save_pit_notes()

            # Try to sync to cloud if connected
            # LINK-2: Also require event_id — without it the URL is malformed
            if (self.telemetry.cloud_connected and self.config.cloud_url
                    and self.config.truck_token and self.config.event_id):
                try:
                    async with httpx.AsyncClient() as client:
                        response = await client.post(
                            f"{self.config.cloud_url}/api/v1/events/{self.config.event_id}/pit-notes",
                            json={
                                'vehicle_id': self.config.vehicle_id,
                                'note': note_text,
                                'timestamp_ms': note['timestamp']
                            },
                            headers={'X-Truck-Token': self.config.truck_token},
                            timeout=5.0
                        )
                        if response.status_code in (200, 201):
                            note['synced'] = True
                            # Update synced status in stored notes
                            if self._pit_notes and self._pit_notes[0]['id'] == note['id']:
                                self._pit_notes[0]['synced'] = True
                                self._save_pit_notes()
                            logger.info(f"Pit note synced to cloud: {note_text[:50]}")
                except Exception as e:
                    logger.warning(f"Failed to sync pit note to cloud: {e}")
            elif not self.config.event_id:
                logger.debug("LINK-2: Note saved locally — no event_id yet, background sync will retry")

            return web.json_response({
                'success': True,
                'note': note
            })

        except Exception as e:
            logger.error(f"Error handling pit note: {e}")
            return web.json_response({'error': str(e)}, status=500)

    async def handle_get_pit_notes(self, request: web.Request) -> web.Response:
        """Return pit notes history."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            # Get optional limit parameter (default 20, max 100)
            limit = min(int(request.query.get('limit', 20)), 100)
            notes = self._pit_notes[:limit]

            return web.json_response({
                'notes': notes,
                'total': len(self._pit_notes),
                'vehicle_id': self.config.vehicle_id,
                'event_id': self.config.event_id
            })
        except Exception as e:
            logger.error(f"Error getting pit notes: {e}")
            return web.json_response({'error': str(e)}, status=500)

    async def handle_pit_notes_sync_status(self, request: web.Request) -> web.Response:
        """Return pit notes sync status for UI display.

        PIT-COMMS-1: Shows cloud connection status and queue counts.
        """
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            return web.json_response(self.get_pit_notes_sync_status())
        except Exception as e:
            logger.error(f"Error getting pit notes sync status: {e}")
            return web.json_response({'error': str(e)}, status=500)

    async def handle_fuel_status(self, request: web.Request) -> web.Response:
        """Return current fuel strategy status."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        fuel_set = self._fuel_strategy.get('fuel_set', False)
        current_fuel = self._fuel_strategy.get('current_fuel_gal')
        # TEL-DEFAULTS: Return None when unset (not a hardcoded default)
        tank_capacity = self._fuel_strategy.get('tank_capacity_gal')
        consumption_rate = self._fuel_strategy.get('consumption_rate_mpg')

        # Calculate estimated miles remaining (only if fuel AND both config values are set)
        estimated_miles = None
        fuel_percent = None
        if fuel_set and current_fuel is not None and consumption_rate is not None and consumption_rate > 0:
            estimated_miles = round(current_fuel * consumption_rate, 1)
        if fuel_set and current_fuel is not None and tank_capacity is not None and tank_capacity > 0:
            fuel_percent = round((current_fuel / tank_capacity) * 100, 1)

        # PIT-FUEL-2: Trip miles and range (remaining_range subtracts miles traveled)
        trip_miles = round(self._trip_state.get('trip_miles', 0.0), 1)
        trip_start_at = self._trip_state.get('trip_start_at', 0)
        range_miles_remaining = None
        if fuel_set and current_fuel is not None and consumption_rate is not None and consumption_rate > 0:
            estimated_range = current_fuel * consumption_rate
            range_miles_remaining = round(max(0, estimated_range - trip_miles), 1)

        return web.json_response({
            'fuel_set': fuel_set,
            'tank_capacity_gal': tank_capacity,
            'current_fuel_gal': round(current_fuel, 1) if current_fuel is not None else None,
            'fuel_percent': fuel_percent,
            'consumption_rate_mpg': consumption_rate,
            'estimated_miles_remaining': estimated_miles,
            'range_miles_remaining': range_miles_remaining,
            'trip_miles': trip_miles,
            'trip_start_at': trip_start_at,
            'last_fill_lap': self._fuel_strategy.get('last_fill_lap', 0),
            'last_fill_timestamp': self._fuel_strategy.get('last_fill_timestamp', 0),
            'updated_at': self._fuel_strategy.get('updated_at', 0),
            'updated_by': self._fuel_strategy.get('updated_by'),
            'source': self._fuel_strategy.get('source'),
            'timestamp': int(time.time() * 1000)
        })

    async def handle_fuel_update(self, request: web.Request) -> web.Response:
        """Update fuel strategy parameters.

        Accepts:
            - tank_capacity_gal: Max fuel cell capacity (gallons)
            - current_fuel_gal: Current fuel level (gallons, 0 to tank_capacity)
            - consumption_rate_mpg: Estimated miles per gallon
            - filled: Boolean - if true, set current to tank capacity
            - updated_by: Optional operator identity
        """
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            now_ms = int(time.time() * 1000)
            # PIT-FUEL-1: Use constant for fallback (single source of truth)
            tank_capacity = self._fuel_strategy.get('tank_capacity_gal', DEFAULT_TANK_CAPACITY_GAL)

            # Update tank capacity (must be positive)
            # PIT-FUEL-1: Validate against constants (1-250, never clamp to 35)
            if 'tank_capacity_gal' in data:
                new_capacity = float(data['tank_capacity_gal'])
                if new_capacity <= 0:
                    return web.json_response({'error': 'Tank capacity must be positive'}, status=400)
                if new_capacity < MIN_TANK_CAPACITY_GAL or new_capacity > MAX_TANK_CAPACITY_GAL:
                    return web.json_response({'error': f'Tank capacity must be between {int(MIN_TANK_CAPACITY_GAL)} and {int(MAX_TANK_CAPACITY_GAL)} gallons'}, status=400)
                self._fuel_strategy['tank_capacity_gal'] = new_capacity
                tank_capacity = new_capacity

            # Update current fuel level (validate range)
            if 'current_fuel_gal' in data:
                new_fuel = float(data['current_fuel_gal'])
                if new_fuel < 0:
                    return web.json_response({'error': 'Fuel level cannot be negative'}, status=400)
                if new_fuel > tank_capacity:
                    return web.json_response({'error': f'Fuel level cannot exceed tank capacity ({tank_capacity} gal)'}, status=400)
                self._fuel_strategy['current_fuel_gal'] = new_fuel
                self._fuel_strategy['fuel_set'] = True
                self._fuel_strategy['source'] = 'manual'

            # Update consumption rate (optional)
            if 'consumption_rate_mpg' in data:
                new_rate = float(data['consumption_rate_mpg'])
                if new_rate < 0.1 or new_rate > 30:
                    return web.json_response({'error': 'MPG must be between 0.1 and 30'}, status=400)
                self._fuel_strategy['consumption_rate_mpg'] = new_rate

            # Handle "tank filled" shortcut
            if data.get('filled'):
                self._fuel_strategy['current_fuel_gal'] = tank_capacity
                self._fuel_strategy['fuel_set'] = True
                self._fuel_strategy['last_fill_lap'] = self.telemetry.lap_number
                self._fuel_strategy['last_fill_timestamp'] = now_ms
                self._fuel_strategy['source'] = 'manual'
                logger.info(f"Fuel fill recorded at lap {self.telemetry.lap_number}: {tank_capacity} gal")

            # Track update metadata
            self._fuel_strategy['updated_at'] = now_ms
            if 'updated_by' in data:
                self._fuel_strategy['updated_by'] = str(data['updated_by'])[:50]  # Limit length

            # Persist to disk
            saved = self._save_fuel_state()

            return web.json_response({
                'success': True,
                'saved': saved,
                'fuel_strategy': {
                    'fuel_set': self._fuel_strategy['fuel_set'],
                    'tank_capacity_gal': self._fuel_strategy['tank_capacity_gal'],
                    'current_fuel_gal': self._fuel_strategy['current_fuel_gal'],
                    'consumption_rate_mpg': self._fuel_strategy['consumption_rate_mpg'],
                    'updated_at': self._fuel_strategy['updated_at'],
                }
            })

        except ValueError as e:
            return web.json_response({'error': f'Invalid number format: {e}'}, status=400)
        except Exception as e:
            logger.error(f"Error updating fuel strategy: {e}")
            return web.json_response({'error': str(e)}, status=500)

    async def handle_trip_reset(self, request: web.Request) -> web.Response:
        """PIT-1R: Reset GPS trip miles accumulator to zero."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            now_ms = int(time.time() * 1000)
            self._trip_state['trip_miles'] = 0.0
            self._trip_state['trip_start_at'] = now_ms
            self._trip_state['prev_lat'] = None
            self._trip_state['prev_lon'] = None
            self._save_trip_state()
            logger.info("Trip miles reset to 0")
            return web.json_response({
                'success': True,
                'trip_miles': 0.0,
                'trip_start_at': now_ms,
            })
        except Exception as e:
            logger.error(f"Error resetting trip: {e}")
            return web.json_response({'error': str(e)}, status=500)

    async def handle_tires_status(self, request: web.Request) -> web.Response:
        """Return current per-axle tire status (PIT-5R)."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        trip_miles = self._trip_state.get('trip_miles', 0.0)

        # Compute miles per axle using baseline strategy (clamp >= 0)
        front_miles = max(0.0, trip_miles - self._tire_state['front_trip_baseline'])
        rear_miles = max(0.0, trip_miles - self._tire_state['rear_trip_baseline'])

        return web.json_response({
            'brand': self._tire_state['brand'],
            'front_miles': round(front_miles, 1),
            'front_last_changed_at': self._tire_state['front_last_changed_at'],
            'front_change_count': self._tire_state['front_change_count'],
            'rear_miles': round(rear_miles, 1),
            'rear_last_changed_at': self._tire_state['rear_last_changed_at'],
            'rear_change_count': self._tire_state['rear_change_count'],
            'timestamp': int(time.time() * 1000)
        })

    async def handle_tires_update(self, request: web.Request) -> web.Response:
        """Update tire brand or reset per-axle mileage (PIT-5R)."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            trip_miles = self._trip_state.get('trip_miles', 0.0)
            now_ms = int(time.time() * 1000)

            # Update brand (shared for front and rear)
            if 'brand' in data:
                brand = str(data['brand'])
                if brand in ('Toyo', 'BFG', 'Maxxis', 'Other'):
                    self._tire_state['brand'] = brand

            # Reset front axle
            if data.get('reset_front'):
                self._tire_state['front_trip_baseline'] = trip_miles
                self._tire_state['front_last_changed_at'] = now_ms
                self._tire_state['front_change_count'] += 1
                logger.info(f"Front tires reset at {trip_miles:.1f} trip mi")

            # Reset rear axle
            if data.get('reset_rear'):
                self._tire_state['rear_trip_baseline'] = trip_miles
                self._tire_state['rear_last_changed_at'] = now_ms
                self._tire_state['rear_change_count'] += 1
                logger.info(f"Rear tires reset at {trip_miles:.1f} trip mi")

            self._save_tire_state()
            return web.json_response({'success': True})

        except Exception as e:
            logger.error(f"Error updating tire state: {e}")
            return web.json_response({'error': str(e)}, status=500)

    # ============ Device Management Handlers ============

    async def handle_device_scan(self, request: web.Request) -> web.Response:
        """Scan for connected devices (cameras, GPS, ANT+, CAN, USB)."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        import subprocess
        result = {
            'cameras': [],
            'gps': None,
            'ant': None,
            'can': None,
            'usb': [],
            'serial_ports': [],
            'services': {},
            'mappings': self._camera_devices.copy()
        }

        try:
            # Detect USB video devices (cameras)
            for i in range(10):
                dev_path = f'/dev/video{i}'
                if os.path.exists(dev_path):
                    cam_info = {'device': dev_path, 'status': 'online', 'name': f'Camera {i}'}
                    try:
                        proc = subprocess.run(
                            ['v4l2-ctl', '-d', dev_path, '--info'],
                            capture_output=True, timeout=2.0, text=True
                        )
                        if proc.returncode == 0:
                            # Parse device name from v4l2-ctl output
                            for line in proc.stdout.split('\n'):
                                if 'Card type' in line:
                                    cam_info['name'] = line.split(':')[1].strip()
                                    break
                    except Exception:
                        pass
                    result['cameras'].append(cam_info)

            # Detect serial ports (for GPS)
            serial_devices = []
            for pattern in ['/dev/ttyUSB*', '/dev/ttyACM*', '/dev/serial/by-id/*']:
                import glob as glob_module
                serial_devices.extend(glob_module.glob(pattern))

            for dev in serial_devices:
                port_info = {'device': dev, 'description': ''}
                # Try to get more info
                if '/by-id/' in dev:
                    port_info['description'] = os.path.basename(dev)
                result['serial_ports'].append(port_info)

            # Check GPS status — detect common GPS serial adapters
            # Supports: u-blox, Prolific ATEN Serial Bridge, generic ttyUSB/ttyACM
            gps_device = None
            for dev in [
                '/dev/serial/by-id/*gps*',
                '/dev/serial/by-id/*u-blox*',
                '/dev/serial/by-id/*Prolific*',
                '/dev/serial/by-id/*ATEN*',
                '/dev/ttyUSB0',
                '/dev/ttyACM0',
            ]:
                import glob as glob_module
                matches = glob_module.glob(dev)
                if matches:
                    gps_device = matches[0]
                    break

            if gps_device or self.telemetry.satellites > 0:
                result['gps'] = {
                    'device': gps_device or 'Auto-detected',
                    'type': 'NMEA/GPSD',
                    'baud': '9600',
                    'satellites': self.telemetry.satellites,
                    'status': 'online' if self.telemetry.satellites > 0 else 'waiting'
                }

            # Check ANT+ USB stick (Dynastream vendor ID 0fcf)
            # Common products: ANTUSB2 (0fcf:1008), ANTUSB-m (0fcf:1009)
            try:
                proc = subprocess.run(
                    ['lsusb', '-d', '0fcf:'],  # Dynastream (ANT+) vendor ID
                    capture_output=True, timeout=5.0, text=True
                )
                if proc.stdout.strip():
                    lsusb_line = proc.stdout.strip().split('\n')[0]
                    # Parse product name from lsusb output (after "ID xxxx:xxxx")
                    parts = lsusb_line.split('ID ')
                    ant_product = parts[1].split(' ', 1)[1].strip() if len(parts) > 1 and ' ' in parts[1] else 'ANT+ USB Stick'
                    result['ant'] = {
                        'device': lsusb_line,
                        'product': ant_product,
                        'status': 'online',
                        'service_status': 'unknown',
                        'heart_rate': self.telemetry.heart_rate
                    }
            except Exception:
                pass

            # Check CAN interface
            try:
                proc = subprocess.run(['ip', 'link', 'show', 'can0'], capture_output=True, timeout=2.0, text=True)
                if proc.returncode == 0 and 'can0' in proc.stdout:
                    result['can'] = {
                        'interface': 'can0',
                        'bitrate': '500000',
                        'status': 'online' if 'UP' in proc.stdout else 'down',
                        'rx_count': '--',
                        'errors': '0'
                    }
            except Exception:
                pass

            # List all USB devices
            try:
                proc = subprocess.run(['lsusb'], capture_output=True, timeout=5.0, text=True)
                for line in proc.stdout.strip().split('\n'):
                    if line:
                        parts = line.split()
                        if len(parts) >= 6:
                            vendor_product = parts[5].split(':') if ':' in parts[5] else ['', '']
                            result['usb'].append({
                                'vendor_id': vendor_product[0] if len(vendor_product) > 0 else '',
                                'product_id': vendor_product[1] if len(vendor_product) > 1 else '',
                                'product': ' '.join(parts[6:]) if len(parts) > 6 else 'USB Device',
                                'manufacturer': ''
                            })
            except Exception:
                pass

            # PIT-SVC-2: Unified service status model
            # Returns per-service: {state, label, details}
            #   state: OK | WARN | ERROR | OFF | UNKNOWN
            #   label: human-readable status
            #   details: optional hint
            # Combines systemd state + device presence + config to give
            # actionable information instead of raw systemd strings.
            svc_names = ['argus-gps', 'argus-can-setup', 'argus-can', 'argus-ant', 'argus-uplink', 'argus-video', 'argus-cloudflared']
            systemd_states = {}
            for svc in svc_names:
                try:
                    proc = subprocess.run(
                        ['systemctl', 'is-active', svc],
                        capture_output=True, timeout=2.0, text=True
                    )
                    systemd_states[svc] = proc.stdout.strip()
                except Exception:
                    systemd_states[svc] = 'unknown'

            # Helper: check if systemd service failed due to rate limiting
            def _is_rate_limited(svc):
                try:
                    p = subprocess.run(
                        ['systemctl', 'show', svc, '--property=Result'],
                        capture_output=True, timeout=2.0, text=True
                    )
                    return 'start-limit-hit' in p.stdout
                except Exception:
                    return False

            # --- argus-gps ---
            gps_sd = systemd_states.get('argus-gps', 'unknown')
            if gps_sd == 'active':
                if self.telemetry.satellites and self.telemetry.satellites > 0:
                    result['services']['gps'] = {
                        'state': 'OK', 'label': 'Running',
                        'details': f'{self.telemetry.satellites} satellites'
                    }
                else:
                    result['services']['gps'] = {
                        'state': 'WARN', 'label': 'No fix yet',
                        'details': 'Waiting for satellite lock'
                    }
            elif gps_sd == 'inactive':
                if result.get('gps') or any(
                    os.path.exists(f'/dev/ttyUSB{i}') or os.path.exists(f'/dev/ttyACM{i}')
                    for i in range(4)
                ):
                    result['services']['gps'] = {
                        'state': 'WARN', 'label': 'Waiting for device',
                        'details': 'GPS dongle detected but service not started'
                    }
                else:
                    result['services']['gps'] = {
                        'state': 'OFF', 'label': 'No GPS dongle',
                        'details': 'Plug in a USB GPS receiver'
                    }
            elif gps_sd == 'failed':
                detail = 'Restart limit hit' if _is_rate_limited('argus-gps') else 'Service crashed'
                result['services']['gps'] = {
                    'state': 'ERROR', 'label': 'Error',
                    'details': detail
                }
            else:
                result['services']['gps'] = {
                    'state': 'UNKNOWN', 'label': gps_sd, 'details': ''
                }

            # --- argus-can-setup ---
            can_setup_sd = systemd_states.get('argus-can-setup', 'unknown')
            if can_setup_sd == 'active':
                result['services']['can-setup'] = {
                    'state': 'OK', 'label': 'Running', 'details': ''
                }
            elif can_setup_sd == 'inactive':
                result['services']['can-setup'] = {
                    'state': 'OFF', 'label': 'Not needed',
                    'details': 'No CAN interface to configure'
                }
            elif can_setup_sd == 'failed':
                result['services']['can-setup'] = {
                    'state': 'ERROR', 'label': 'Error',
                    'details': 'CAN setup failed'
                }
            else:
                result['services']['can-setup'] = {
                    'state': 'UNKNOWN', 'label': can_setup_sd, 'details': ''
                }

            # --- argus-can ---
            can_sd = systemd_states.get('argus-can', 'unknown')
            if can_sd == 'active':
                result['services']['can'] = {
                    'state': 'OK', 'label': 'Running', 'details': ''
                }
            elif can_sd == 'inactive':
                if result.get('can'):
                    result['services']['can'] = {
                        'state': 'WARN', 'label': 'Waiting for device',
                        'details': 'CAN interface detected but service not started'
                    }
                else:
                    result['services']['can'] = {
                        'state': 'OFF', 'label': 'No CAN interface',
                        'details': 'Connect a CAN bus adapter'
                    }
            elif can_sd == 'failed':
                detail = 'Restart limit hit' if _is_rate_limited('argus-can') else 'Service crashed'
                result['services']['can'] = {
                    'state': 'ERROR', 'label': 'Error', 'details': detail
                }
            else:
                result['services']['can'] = {
                    'state': 'UNKNOWN', 'label': can_sd, 'details': ''
                }

            # --- argus-ant ---
            ant_sd = systemd_states.get('argus-ant', 'unknown')
            if ant_sd == 'active':
                if self.telemetry.heart_rate and self.telemetry.heart_rate > 0:
                    result['services']['ant'] = {
                        'state': 'OK', 'label': 'Running',
                        'details': f'HR: {self.telemetry.heart_rate} BPM'
                    }
                else:
                    result['services']['ant'] = {
                        'state': 'WARN', 'label': 'Connected, no data',
                        'details': 'Waiting for heart rate signal'
                    }
            elif ant_sd == 'inactive':
                if result.get('ant'):
                    result['services']['ant'] = {
                        'state': 'WARN', 'label': 'Waiting for device',
                        'details': 'ANT+ stick detected but service not started'
                    }
                else:
                    result['services']['ant'] = {
                        'state': 'OFF', 'label': 'No ANT+ stick',
                        'details': 'Plug in an ANT+ USB stick'
                    }
            elif ant_sd == 'failed':
                detail = 'Restart limit hit' if _is_rate_limited('argus-ant') else 'Service crashed'
                result['services']['ant'] = {
                    'state': 'ERROR', 'label': 'Error', 'details': detail
                }
            else:
                result['services']['ant'] = {
                    'state': 'UNKNOWN', 'label': ant_sd, 'details': ''
                }

            # --- argus-uplink ---
            uplink_sd = systemd_states.get('argus-uplink', 'unknown')
            if uplink_sd == 'active':
                # Check if uplink is idling (not_configured) via state file
                uplink_state_detail = ''
                try:
                    sf = Path('/opt/argus/state/uplink_status.json')
                    if sf.exists():
                        us = json.loads(sf.read_text())
                        uplink_state_detail = us.get('status', '')
                except Exception:
                    pass
                if uplink_state_detail == 'not_configured':
                    result['services']['uplink'] = {
                        'state': 'WARN', 'label': 'Not configured',
                        'details': 'Set Cloud URL and Token in Settings'
                    }
                elif uplink_state_detail == 'starting':
                    result['services']['uplink'] = {
                        'state': 'WARN', 'label': 'Starting',
                        'details': 'Connecting to cloud'
                    }
                else:
                    result['services']['uplink'] = {
                        'state': 'OK', 'label': 'Running', 'details': ''
                    }
            elif uplink_sd == 'inactive':
                result['services']['uplink'] = {
                    'state': 'OFF', 'label': 'Not configured',
                    'details': 'Set Cloud URL and Token in Settings'
                }
            elif uplink_sd == 'failed':
                detail = 'Restart limit hit' if _is_rate_limited('argus-uplink') else 'Service crashed'
                result['services']['uplink'] = {
                    'state': 'ERROR', 'label': 'Error', 'details': detail
                }
            else:
                result['services']['uplink'] = {
                    'state': 'UNKNOWN', 'label': uplink_sd, 'details': ''
                }

            # --- argus-video ---
            video_sd = systemd_states.get('argus-video', 'unknown')
            if video_sd == 'active':
                result['services']['video'] = {
                    'state': 'OK', 'label': 'Ready',
                    'details': 'Camera service running'
                }
            elif video_sd == 'inactive':
                if result.get('cameras') and len(result['cameras']) > 0:
                    result['services']['video'] = {
                        'state': 'WARN', 'label': 'Waiting for device',
                        'details': 'Cameras detected but service not started'
                    }
                else:
                    result['services']['video'] = {
                        'state': 'OFF', 'label': 'No cameras',
                        'details': 'Connect USB cameras'
                    }
            elif video_sd == 'failed':
                detail = 'Restart limit hit' if _is_rate_limited('argus-video') else 'Service crashed'
                result['services']['video'] = {
                    'state': 'ERROR', 'label': 'Error', 'details': detail
                }
            else:
                result['services']['video'] = {
                    'state': 'UNKNOWN', 'label': video_sd, 'details': ''
                }

            # --- argus-cloudflared (Cloudflare Tunnel) ---
            cf_sd = systemd_states.get('argus-cloudflared', 'unknown')
            tunnel_url = self.config.cloudflare_tunnel_url or ''
            if cf_sd == 'active':
                result['services']['cloudflared'] = {
                    'state': 'OK', 'label': 'Connected',
                    'details': tunnel_url or 'Tunnel running',
                    'tunnel_url': tunnel_url,
                }
            elif cf_sd == 'inactive':
                if self.config.cloudflare_tunnel_token:
                    result['services']['cloudflared'] = {
                        'state': 'WARN', 'label': 'Not running',
                        'details': 'Token configured but service not started',
                        'tunnel_url': tunnel_url,
                    }
                else:
                    result['services']['cloudflared'] = {
                        'state': 'OFF', 'label': 'Not configured',
                        'details': 'Set Tunnel Token in Settings',
                        'tunnel_url': '',
                    }
            elif cf_sd == 'failed':
                detail = 'Restart limit hit' if _is_rate_limited('argus-cloudflared') else 'Service crashed'
                result['services']['cloudflared'] = {
                    'state': 'ERROR', 'label': 'Error',
                    'details': detail,
                    'tunnel_url': tunnel_url,
                }
            else:
                result['services']['cloudflared'] = {
                    'state': 'UNKNOWN', 'label': cf_sd, 'details': '',
                    'tunnel_url': tunnel_url,
                }

        except Exception as e:
            logger.error(f"Device scan error: {e}")

        return web.json_response(result)

    async def handle_camera_mappings(self, request: web.Request) -> web.Response:
        """Update camera-to-device mappings."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            # CAM-CONTRACT-1B: Accept canonical camera slot names
            # Also accept legacy aliases for backward compatibility
            legacy_to_canonical = {'pov': 'cockpit', 'roof': 'chase', 'front': 'suspension', 'rear': 'suspension'}
            for role in ['main', 'cockpit', 'chase', 'suspension']:
                if role in data:
                    self._camera_devices[role] = data[role]
                    logger.info(f"Camera mapping updated: {role} -> {data[role]}")
            # Handle legacy names from old clients
            for legacy, canonical in legacy_to_canonical.items():
                if legacy in data and canonical not in data:
                    self._camera_devices[canonical] = data[legacy]
                    logger.info(f"Camera mapping updated (legacy {legacy}->{canonical}): {data[legacy]}")

            # Save to config file
            config_path = os.path.join(os.path.dirname(get_config_path()), 'camera_mappings.json')
            try:
                os.makedirs(os.path.dirname(config_path), exist_ok=True)
                with open(config_path, 'w') as f:
                    json.dump(self._camera_devices, f, indent=2)
            except Exception as e:
                logger.warning(f"Could not save camera mappings: {e}")

            return web.json_response({'success': True, 'mappings': self._camera_devices})

        except Exception as e:
            logger.error(f"Error updating camera mappings: {e}")
            return web.json_response({'error': str(e)}, status=500)

    async def handle_gps_config(self, request: web.Request) -> web.Response:
        """Update GPS device configuration."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            gps_port = data.get('port', '')

            # Save GPS port configuration
            config_path = os.path.join(os.path.dirname(get_config_path()), 'gps_config.json')
            try:
                os.makedirs(os.path.dirname(config_path), exist_ok=True)
                with open(config_path, 'w') as f:
                    json.dump({'port': gps_port}, f, indent=2)
                logger.info(f"GPS config saved: port={gps_port}")
            except Exception as e:
                logger.warning(f"Could not save GPS config: {e}")

            return web.json_response({'success': True, 'port': gps_port})

        except Exception as e:
            logger.error(f"Error updating GPS config: {e}")
            return web.json_response({'error': str(e)}, status=500)

    async def handle_ant_pair(self, request: web.Request) -> web.Response:
        """Initiate ANT+ device pairing."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            import subprocess
            # Restart the ANT+ service which will trigger pairing
            subprocess.run(['sudo', 'systemctl', 'restart', 'argus-ant'], check=False)
            logger.info("ANT+ pairing initiated via service restart")
            return web.json_response({'success': True, 'message': 'ANT+ pairing initiated'})
        except Exception as e:
            logger.error(f"ANT+ pairing error: {e}")
            return web.json_response({'error': str(e)}, status=500)

    async def handle_restart_service(self, request: web.Request) -> web.Response:
        """Restart a specific Argus service."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            data = await request.json()
            service = data.get('service', '')

            # Only allow restarting argus-* services
            if not service.startswith('argus-'):
                return web.json_response({'error': 'Invalid service name'}, status=400)

            import subprocess
            subprocess.run(['sudo', 'systemctl', 'restart', service], check=False)
            logger.info(f"Service {service} restart requested")
            return web.json_response({'success': True, 'service': service})

        except Exception as e:
            logger.error(f"Service restart error: {e}")
            return web.json_response({'error': str(e)}, status=500)

    async def handle_restart_all_services(self, request: web.Request) -> web.Response:
        """Restart all Argus services."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        try:
            import subprocess
            services = ['argus-gps', 'argus-can', 'argus-ant', 'argus-uplink', 'argus-video']
            for svc in services:
                subprocess.run(['sudo', 'systemctl', 'restart', svc], check=False)
            logger.info("All Argus services restart requested")
            return web.json_response({'success': True, 'services': services})

        except Exception as e:
            logger.error(f"Services restart error: {e}")
            return web.json_response({'error': str(e)}, status=500)

    # ============ Screenshot Capture Handlers (Feature 1: Stream Control) ============

    async def handle_camera_screenshot(self, request: web.Request) -> web.Response:
        """Serve the latest screenshot for a camera."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        camera = self._normalize_camera_slot(request.match_info.get('camera', ''))
        if camera not in self._camera_devices:
            return web.Response(status=404, text='Camera not found')

        screenshot_path = os.path.join(self._screenshot_cache_dir, f'{camera}.jpg')

        if not os.path.exists(screenshot_path):
            # Return a placeholder image or trigger capture
            return web.Response(
                status=404,
                text='No screenshot available. Waiting for first capture.',
                content_type='text/plain'
            )

        try:
            with open(screenshot_path, 'rb') as f:
                content = f.read()

            response = web.Response(body=content, content_type='image/jpeg')
            # Cache for 30 seconds (less than capture interval)
            response.headers['Cache-Control'] = 'public, max-age=30'
            response.headers['X-Screenshot-Timestamp'] = str(
                self._screenshot_timestamps.get(camera, 0)
            )
            return response

        except Exception as e:
            logger.error(f"Error serving screenshot for {camera}: {e}")
            return web.Response(status=500, text=str(e))

    async def handle_screenshots_status(self, request: web.Request) -> web.Response:
        """Return status of all camera screenshots."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        status = {}
        now = int(time.time() * 1000)

        for camera in self._camera_devices:
            screenshot_path = os.path.join(self._screenshot_cache_dir, f'{camera}.jpg')
            has_screenshot = os.path.exists(screenshot_path)
            last_capture = self._screenshot_timestamps.get(camera, 0)
            age_ms = now - last_capture if last_capture > 0 else None

            status[camera] = {
                'device': self._camera_devices[camera],
                'status': self._camera_status.get(camera, 'unknown'),
                'has_screenshot': has_screenshot,
                'last_capture_ms': last_capture,
                'age_ms': age_ms,
                'resolution': self._screenshot_resolutions.get(camera, 'unknown'),
                'screenshot_url': f'/api/cameras/preview/{camera}.jpg' if has_screenshot else None,
                'is_stale': age_ms is not None and age_ms > (self._screenshot_interval * 2 * 1000)
            }

        return web.json_response({
            'cameras': status,
            'capture_interval_sec': self._screenshot_interval,
            'capture_in_progress': self._screenshot_capture_in_progress,
            'timestamp': now
        })

    async def handle_capture_screenshot(self, request: web.Request) -> web.Response:
        """Manually trigger a screenshot capture for a specific camera."""
        if not self._is_authenticated(request):
            return web.Response(status=401, text='Unauthorized')

        camera = self._normalize_camera_slot(request.match_info.get('camera', ''))
        if camera not in self._camera_devices:
            return web.Response(status=404, text='Camera not found')

        try:
            success, message = await self._capture_single_screenshot(camera)
            return web.json_response({
                'success': success,
                'message': message,
                'camera': camera,
                'timestamp': int(time.time() * 1000)
            })
        except Exception as e:
            logger.error(f"Manual capture error for {camera}: {e}")
            return web.json_response({'success': False, 'error': str(e)}, status=500)

    async def _capture_single_screenshot(self, camera: str) -> tuple:
        """Capture a single screenshot from a camera using FFmpeg.

        PIT-CAM-PREVIEW-B: Uses _get_camera_device for fallback probing
        and asyncio subprocess to avoid blocking the event loop.

        Returns (success: bool, message: str)
        """
        import re as _re

        device_path = self._get_camera_device(camera)
        if not device_path:
            self._camera_status[camera] = 'offline'
            return False, f"No device found for camera {camera}"

        # Skip if camera is currently streaming (don't compete for device)
        if (self._ffmpeg_process and self._ffmpeg_process.poll() is None
                and self._streaming_state.get('camera') == camera):
            return False, f"Camera {camera} is busy (streaming)"

        output_path = os.path.join(self._screenshot_cache_dir, f'{camera}.jpg')
        temp_path = os.path.join(self._screenshot_cache_dir, f'{camera}_temp.jpg')

        try:
            # Try MJPEG first (faster for most USB cameras)
            cmd = [
                'ffmpeg', '-y',
                '-f', 'v4l2',
                '-video_size', '640x480',
                '-input_format', 'mjpeg',
                '-i', device_path,
                '-vframes', '1',
                '-q:v', '5',
                temp_path
            ]

            proc = await asyncio.wait_for(
                asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                ),
                timeout=12.0
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=10.0)
            stderr_text = stderr.decode('utf-8', errors='replace') if stderr else ''

            if proc.returncode != 0:
                # Fallback without mjpeg format
                cmd_fallback = [
                    'ffmpeg', '-y',
                    '-f', 'v4l2',
                    '-video_size', '640x480',
                    '-i', device_path,
                    '-vframes', '1',
                    '-q:v', '5',
                    temp_path
                ]
                proc = await asyncio.wait_for(
                    asyncio.create_subprocess_exec(
                        *cmd_fallback,
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE,
                    ),
                    timeout=12.0
                )
                stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=10.0)
                stderr_text = stderr.decode('utf-8', errors='replace') if stderr else ''

            if proc.returncode == 0 and os.path.exists(temp_path):
                # Atomic rename to avoid serving partial files
                os.rename(temp_path, output_path)
                self._screenshot_timestamps[camera] = int(time.time() * 1000)
                self._camera_status[camera] = 'online'

                # Try to extract resolution from FFmpeg output
                for line in stderr_text.split('\n'):
                    if 'Video:' in line and 'x' in line:
                        match = _re.search(r'(\d{3,4}x\d{3,4})', line)
                        if match:
                            self._screenshot_resolutions[camera] = match.group(1)
                            break

                logger.debug(f"Screenshot captured for {camera}")
                return True, "Screenshot captured successfully"
            else:
                self._camera_status[camera] = 'error'
                error_msg = stderr_text[-500:] if stderr_text else "Unknown error"
                logger.warning(f"FFmpeg capture failed for {camera}: {error_msg}")
                return False, f"FFmpeg capture failed: {error_msg[:100]}"

        except asyncio.TimeoutError:
            self._camera_status[camera] = 'timeout'
            logger.warning(f"Screenshot capture timeout for {camera}")
            return False, "Capture timed out"
        except FileNotFoundError:
            logger.error("FFmpeg not installed")
            return False, "FFmpeg not installed on system"
        except Exception as e:
            self._camera_status[camera] = 'error'
            logger.error(f"Screenshot capture error for {camera}: {e}")
            return False, str(e)
        finally:
            # Clean up temp file if it exists
            if os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except Exception:
                    pass

    async def _screenshot_capture_loop(self):
        """Background task to capture preview thumbnails periodically.

        PIT-CAM-PREVIEW-B: Uses _get_camera_device for fallback probing
        so thumbnails work even when device nodes differ from defaults.
        """
        logger.info(f"Starting preview capture loop (interval: {self._screenshot_interval}s)")

        # Stagger initial captures to avoid CPU spike
        await asyncio.sleep(5)

        while self._running:
            try:
                self._screenshot_capture_in_progress = True

                for camera in list(self._camera_devices.keys()):
                    if not self._running:
                        break

                    # Use _get_camera_device which probes fallback paths
                    device_path = self._get_camera_device(camera)
                    if device_path:
                        await self._capture_single_screenshot(camera)
                        # Stagger captures by 5 seconds to reduce CPU load
                        await asyncio.sleep(5)
                    else:
                        self._camera_status[camera] = 'offline'

                self._screenshot_capture_in_progress = False

                # Wait for remaining interval time
                elapsed = len(self._camera_devices) * 5
                remaining = max(1, self._screenshot_interval - elapsed)
                await asyncio.sleep(remaining)

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Preview capture loop error: {e}")
                self._screenshot_capture_in_progress = False
                await asyncio.sleep(30)

        logger.info("Preview capture loop stopped")

    # ============ Course/GPX API Handlers (Feature 4) ============

    async def handle_get_course(self, request: web.Request) -> web.Response:
        """Get the currently loaded course GPX data.

        NOTE: No authentication required - course data is not sensitive and should
        be accessible from any device on the same network (pit crew mobile/desktop).
        """
        config_dir = os.path.dirname(get_config_path())
        course_file = os.path.join(config_dir, 'course.json')
        if os.path.exists(course_file):
            try:
                with open(course_file, 'r') as f:
                    course_data = json.load(f)
                return web.json_response(course_data)
            except Exception as e:
                logger.error(f"Error loading course: {e}")
                return web.json_response({})
        return web.json_response({})

    async def handle_course_upload(self, request: web.Request) -> web.Response:
        """Upload and save a GPX course file.

        NOTE: No authentication required - any pit crew member on the network
        should be able to upload a course. Network access is the security boundary.
        """
        try:
            data = await request.json()
            filename = data.get('filename', 'course.gpx')
            gpx_data = data.get('gpx_data', '')

            if not gpx_data:
                return web.json_response({'success': False, 'error': 'No GPX data provided'}, status=400)

            # Save course data
            config_dir = os.path.dirname(get_config_path())
            course_file = os.path.join(config_dir, 'course.json')
            with open(course_file, 'w') as f:
                json.dump({
                    'filename': filename,
                    'gpx_data': gpx_data,
                    'uploaded_at': int(time.time() * 1000)
                }, f)

            logger.info(f"Course uploaded: {filename}")
            return web.json_response({'success': True, 'filename': filename})

        except Exception as e:
            logger.error(f"Course upload error: {e}")
            return web.json_response({'success': False, 'error': str(e)}, status=500)

    async def handle_course_clear(self, request: web.Request) -> web.Response:
        """Clear the current course.

        NOTE: No authentication required - any pit crew member on the network
        can clear the course. This matches the upload behavior.
        """
        try:
            config_dir = os.path.dirname(get_config_path())
            course_file = os.path.join(config_dir, 'course.json')
            if os.path.exists(course_file):
                os.remove(course_file)
            logger.info("Course cleared")
            return web.json_response({'success': True})
        except Exception as e:
            logger.error(f"Course clear error: {e}")
            return web.json_response({'success': False, 'error': str(e)}, status=500)

    async def _detect_cameras(self):
        """Detect camera status using V4L2 device nodes."""
        import subprocess

        for cam_name, device_path in self._camera_devices.items():
            try:
                # Check if device exists
                if not os.path.exists(device_path):
                    self._camera_status[cam_name] = 'offline'
                    continue

                # Try to query device capabilities using v4l2-ctl
                result = subprocess.run(
                    ['v4l2-ctl', '-d', device_path, '--info'],
                    capture_output=True,
                    timeout=2.0
                )

                if result.returncode == 0:
                    self._camera_status[cam_name] = 'online'
                else:
                    self._camera_status[cam_name] = 'error'

            except FileNotFoundError:
                # v4l2-ctl not installed, fallback to device existence check
                self._camera_status[cam_name] = 'online' if os.path.exists(device_path) else 'offline'
            except subprocess.TimeoutExpired:
                self._camera_status[cam_name] = 'timeout'
            except Exception as e:
                logger.debug(f"Camera detection error for {cam_name}: {e}")
                self._camera_status[cam_name] = 'unknown'

    async def _monitor_audio(self):
        """Monitor audio levels using ALSA (runs in background)."""
        import subprocess

        while self._running:
            try:
                # Use arecord to capture a brief sample and analyze
                # This is a lightweight way to detect audio activity
                result = subprocess.run(
                    ['arecord', '-d', '1', '-f', 'S16_LE', '-r', '16000', '-c', '1', '-t', 'raw', '-q', '-'],
                    capture_output=True,
                    timeout=3.0
                )

                if result.returncode == 0 and result.stdout:
                    # Calculate RMS level from audio samples
                    import struct
                    samples = struct.unpack(f'{len(result.stdout)//2}h', result.stdout)
                    if samples:
                        rms = (sum(s*s for s in samples) / len(samples)) ** 0.5
                        # Convert to dB (reference: max int16 = 32768)
                        if rms > 0:
                            self._audio_level = 20 * (rms / 32768.0)
                            if self._audio_level > -40:  # Activity threshold
                                self._last_audio_activity = int(time.time() * 1000)
                        else:
                            self._audio_level = -60.0

            except FileNotFoundError:
                # ALSA tools not available - that's okay, just log once
                logger.debug("arecord not available for audio monitoring")
                break
            except subprocess.TimeoutExpired:
                pass
            except Exception as e:
                logger.debug(f"Audio monitoring error: {e}")

            await asyncio.sleep(2.0)  # Check every 2 seconds

    async def _zmq_subscriber(self):
        """Subscribe to ZMQ telemetry streams."""
        if not ZMQ_AVAILABLE:
            logger.warning("ZMQ not available, running mock data")
            await self._mock_data_loop()
            return

        self._zmq_context = zmq.asyncio.Context()

        # CAN telemetry subscriber
        self._zmq_socket_can = self._zmq_context.socket(zmq.SUB)
        self._zmq_socket_can.connect(f"tcp://localhost:{self.config.zmq_can_port}")
        self._zmq_socket_can.setsockopt_string(zmq.SUBSCRIBE, "")
        logger.info(f"Connected to CAN ZMQ on port {self.config.zmq_can_port}")

        # GPS subscriber
        self._zmq_socket_gps = self._zmq_context.socket(zmq.SUB)
        self._zmq_socket_gps.connect(f"tcp://localhost:{self.config.zmq_gps_port}")
        self._zmq_socket_gps.setsockopt_string(zmq.SUBSCRIBE, "")
        logger.info(f"Connected to GPS ZMQ on port {self.config.zmq_gps_port}")

        # ANT+ heart rate subscriber
        self._zmq_socket_ant = self._zmq_context.socket(zmq.SUB)
        self._zmq_socket_ant.connect(f"tcp://localhost:{self.config.zmq_ant_port}")
        self._zmq_socket_ant.setsockopt_string(zmq.SUBSCRIBE, "")
        logger.info(f"Connected to ANT+ ZMQ on port {self.config.zmq_ant_port}")

        # Start receiver tasks
        await asyncio.gather(
            self._receive_can(),
            self._receive_gps(),
            self._receive_ant(),
        )

    async def _receive_can(self):
        """Receive CAN telemetry."""
        while self._running:
            try:
                if await self._zmq_socket_can.poll(timeout=100):
                    msg = await self._zmq_socket_can.recv_multipart()
                    payload = json.loads(msg[-1].decode())

                    # Update telemetry state - Core engine data
                    # TEL-DEFAULTS: Reset to None when CAN key absent (no stale retention)
                    self.telemetry.rpm = payload.get('rpm', self.telemetry.rpm)
                    self.telemetry.coolant_temp = payload.get('coolant_temp')
                    self.telemetry.oil_pressure = payload.get('oil_pressure')
                    self.telemetry.oil_temp = payload.get('oil_temp')
                    self.telemetry.fuel_pressure = payload.get('fuel_pressure', self.telemetry.fuel_pressure)
                    self.telemetry.throttle_pct = payload.get('throttle_pct', self.telemetry.throttle_pct)
                    self.telemetry.engine_load = payload.get('engine_load', self.telemetry.engine_load)
                    self.telemetry.intake_air_temp = payload.get('intake_air_temp', self.telemetry.intake_air_temp)  # ADDED
                    self.telemetry.boost_pressure = payload.get('boost_pressure', self.telemetry.boost_pressure)  # ADDED
                    self.telemetry.battery_voltage = payload.get('battery_voltage', self.telemetry.battery_voltage)  # ADDED
                    self.telemetry.fuel_level_pct = payload.get('fuel_level_pct', self.telemetry.fuel_level_pct)  # ADDED

                    # Vehicle data
                    self.telemetry.speed_mps = payload.get('speed_mps', self.telemetry.speed_mps)
                    self.telemetry.gear = payload.get('gear', self.telemetry.gear)
                    self.telemetry.trans_temp = payload.get('trans_temp', self.telemetry.trans_temp)  # ADDED

                    # NOTE: Suspension data handling removed - not currently in use

                    self.telemetry.last_update_ms = payload.get('ts_ms', int(time.time() * 1000))
                    # EDGE-3: Track CAN device status
                    self.telemetry.can_device_status = payload.get('device_status', 'unknown')

            except Exception as e:
                logger.error(f"CAN receive error: {e}")
                await asyncio.sleep(0.1)

    def _haversine_distance_miles(self, lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Calculate distance between two GPS points in miles using Haversine formula."""
        import math
        R = 3959  # Earth's radius in miles

        lat1_rad = math.radians(lat1)
        lat2_rad = math.radians(lat2)
        delta_lat = math.radians(lat2 - lat1)
        delta_lon = math.radians(lon2 - lon1)

        a = math.sin(delta_lat / 2) ** 2 + \
            math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon / 2) ** 2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

        return R * c

    def _calculate_heading(self, lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Calculate bearing/heading from point 1 to point 2 in degrees (0-360)."""
        import math
        lat1_rad = math.radians(lat1)
        lat2_rad = math.radians(lat2)
        delta_lon = math.radians(lon2 - lon1)

        x = math.sin(delta_lon) * math.cos(lat2_rad)
        y = math.cos(lat1_rad) * math.sin(lat2_rad) - \
            math.sin(lat1_rad) * math.cos(lat2_rad) * math.cos(delta_lon)

        bearing = math.atan2(x, y)
        bearing = math.degrees(bearing)
        return (bearing + 360) % 360  # Normalize to 0-360

    async def _receive_gps(self):
        """Receive GPS telemetry."""
        # Track previous position for heading calculation and tire miles
        prev_lat = None
        prev_lon = None
        # PIT-1R: Periodic trip state save (every 60s of movement)
        _last_trip_save_ms = 0

        while self._running:
            try:
                if await self._zmq_socket_gps.poll(timeout=100):
                    msg = await self._zmq_socket_gps.recv_multipart()
                    payload = json.loads(msg[-1].decode())

                    new_lat = payload.get('lat', self.telemetry.lat)
                    new_lon = payload.get('lon', self.telemetry.lon)
                    now_ms = int(time.time() * 1000)

                    # Calculate heading and tire miles from position change
                    if prev_lat is not None and prev_lon is not None:
                        if new_lat is not None and new_lon is not None:
                            distance_mi = self._haversine_distance_miles(
                                prev_lat, prev_lon, new_lat, new_lon
                            )
                            # Only update heading/miles if movement is significant (filter GPS jitter)
                            if distance_mi > 0.001:  # ~5 meters minimum movement
                                # Calculate heading from previous to current position
                                self.telemetry.heading_deg = self._calculate_heading(
                                    prev_lat, prev_lon, new_lat, new_lon
                                )
                                # Track GPS distance (filter GPS jumps)
                                if distance_mi < 0.5:  # Max 0.5 miles per GPS update
                                    # PIT-1R: Accumulate trip miles (tire miles derived from baseline)
                                    self._trip_state['trip_miles'] += distance_mi
                                    # Save trip state every 60 seconds
                                    if now_ms - _last_trip_save_ms > 60000:
                                        self._save_trip_state()
                                        _last_trip_save_ms = now_ms

                    # Update previous position for next iteration
                    if new_lat is not None and new_lon is not None:
                        prev_lat = new_lat
                        prev_lon = new_lon

                    self.telemetry.lat = new_lat
                    self.telemetry.lon = new_lon
                    self.telemetry.altitude_m = payload.get('altitude_m', self.telemetry.altitude_m)
                    self.telemetry.satellites = payload.get('satellites', self.telemetry.satellites)
                    self.telemetry.hdop = payload.get('hdop', self.telemetry.hdop)
                    self.telemetry.gps_ts_ms = now_ms  # Track when we got this GPS fix
                    # EDGE-3: Track GPS device status
                    self.telemetry.gps_device_status = payload.get('device_status', 'unknown')

            except Exception as e:
                logger.error(f"GPS receive error: {e}")
                await asyncio.sleep(0.1)

    async def _receive_ant(self):
        """Receive ANT+ heart rate telemetry."""
        while self._running:
            try:
                if await self._zmq_socket_ant.poll(timeout=100):
                    msg = await self._zmq_socket_ant.recv_multipart()
                    payload = json.loads(msg[-1].decode())

                    # Heart rate from ANT+ monitor
                    hr = payload.get('heart_rate', 0)
                    if hr > 0:
                        self.telemetry.heart_rate = hr
                    # EDGE-3: Track ANT+ device status
                    self.telemetry.ant_device_status = payload.get('device_status', 'unknown')

            except Exception as e:
                logger.debug(f"ANT+ receive error: {e}")
                await asyncio.sleep(0.5)

    async def _mock_data_loop(self):
        """Generate mock data for testing."""
        import math
        import random
        t = 0
        # TEL-DEFAULTS: Only simulate CAN-like telemetry when explicitly opted in
        simulate_telemetry = os.environ.get('ARGUS_SIMULATE_TELEMETRY', '').lower() in ('1', 'true', 'yes')

        while self._running:
            await asyncio.sleep(0.05)
            t += 0.05

            # Engine telemetry
            self.telemetry.rpm = 3500 + math.sin(t * 0.5) * 1500 + random.gauss(0, 50)
            self.telemetry.throttle_pct = 50 + math.sin(t * 0.7) * 40
            if simulate_telemetry:
                self.telemetry.coolant_temp = 90 + math.sin(t * 0.1) * 10
                self.telemetry.oil_pressure = 45 + math.sin(t * 0.2) * 10
                self.telemetry.oil_temp = 95 + math.sin(t * 0.08) * 8
            self.telemetry.fuel_pressure = 350 + random.gauss(0, 10)
            self.telemetry.engine_load = 50 + math.sin(t * 0.6) * 30 + random.gauss(0, 5)
            self.telemetry.intake_air_temp = 35 + math.sin(t * 0.15) * 10  # IAT in °C
            self.telemetry.boost_pressure = max(0, 8 + math.sin(t * 0.5) * 6)  # Boost PSI
            self.telemetry.battery_voltage = 13.8 + math.sin(t * 0.3) * 0.5
            self.telemetry.fuel_level_pct = max(10, 75 - t * 0.1)  # Slowly decreasing

            # Vehicle telemetry
            self.telemetry.speed_mps = (80 + math.sin(t * 0.3) * 30) / 3.6
            self.telemetry.gear = max(1, min(6, int(3 + math.sin(t * 0.4) * 2)))
            self.telemetry.trans_temp = 85 + math.sin(t * 0.12) * 15  # ADDED

            # NOTE: Suspension mock data removed - not currently in use

            # GPS telemetry (simulate circular path)
            self.telemetry.lat = 34.0522 + math.sin(t * 0.01) * 0.001
            self.telemetry.lon = -118.2437 + math.cos(t * 0.01) * 0.001
            self.telemetry.satellites = 12
            self.telemetry.hdop = 1.2 + random.gauss(0, 0.2)
            # Heading: direction of travel (perpendicular to radius in circular motion)
            self.telemetry.heading_deg = (math.degrees(t * 0.01) + 90) % 360
            self.telemetry.gps_ts_ms = int(time.time() * 1000)

            # Driver vitals
            self.telemetry.heart_rate = int(120 + math.sin(t * 0.3) * 30 + random.gauss(0, 5))

            # Status
            self.telemetry.current_camera = "chase"
            self.telemetry.cloud_connected = True
            self.telemetry.last_update_ms = int(time.time() * 1000)

    async def _cloud_status_loop(self):
        """Check cloud connection, get production status, and send heartbeats.

        LINK-1: This loop never permanently exits. When cloud_url or truck_token
        is not configured, it idles (sleeps) and re-checks each iteration. This
        allows settings changes via the web UI to take effect without restarting.

        EDGE-CLOUD-1: Sets cloud_detail for granular banner display:
        - "not_configured": no cloud_url or truck_token
        - "healthy": cloud reachable AND event is in_progress
        - "event_not_live": cloud reachable, token valid, but event not in_progress
        - "unreachable": cloud /health endpoint not responding
        - "auth_rejected": cloud reachable but truck token invalid (401)
        """
        if not HTTPX_AVAILABLE:
            logger.warning("LINK-1: httpx not available; cloud status loop disabled")
            return

        logger.info("LINK-1: Cloud status loop started")

        poll_interval = self.config.leaderboard_poll_seconds
        heartbeat_interval = 10  # seconds
        last_heartbeat = 0.0

        async with httpx.AsyncClient() as client:
            while self._running:
                try:
                    # LINK-1: Re-check config every iteration instead of exiting
                    if not self.config.cloud_url or not self.config.truck_token:
                        self.telemetry.cloud_connected = False
                        self.telemetry.cloud_detail = "not_configured"
                        logger.debug("LINK-1: Cloud not configured; idling")
                        await asyncio.sleep(poll_interval)
                        continue

                    # Check cloud health
                    response = await client.get(
                        f"{self.config.cloud_url}/health",
                        timeout=5.0
                    )
                    cloud_reachable = response.status_code == 200

                    if not cloud_reachable:
                        self.telemetry.cloud_connected = False
                        self.telemetry.cloud_detail = "unreachable"
                        logger.debug("LINK-1: Cloud unreachable; buffering")
                        await asyncio.sleep(poll_interval)
                        continue

                    # EDGE-CLOUD-1: Send heartbeat every heartbeat_interval,
                    # regardless of whether event_id is known.
                    # Heartbeat response tells us event_status for banner.
                    now = time.time()
                    if (now - last_heartbeat) >= heartbeat_interval and self.config.truck_token:
                        last_heartbeat = now
                        logger.debug("LINK-1: Cloud configured; attempting heartbeat")
                        hb_detail = await self._send_cloud_heartbeat(client)
                        # hb_detail is "healthy", "event_not_live", or "auth_rejected"
                        if hb_detail:
                            prev_detail = self.telemetry.cloud_detail
                            self.telemetry.cloud_detail = hb_detail
                            self.telemetry.cloud_connected = (hb_detail == "healthy")
                            if hb_detail == "healthy" and prev_detail != "healthy":
                                logger.info("LINK-1: Cloud connected")
                        else:
                            # Heartbeat failed but /health was OK
                            self.telemetry.cloud_connected = False
                            self.telemetry.cloud_detail = "unreachable"
                            logger.debug("LINK-1: Heartbeat failed; cloud unreachable")

                    # Get production status and leaderboard if available
                    if self.config.event_id:
                        # Production status
                        try:
                            response = await client.get(
                                f"{self.config.cloud_url}/api/v1/events/{self.config.event_id}/production/status",
                                headers={"X-Truck-Token": self.config.truck_token},
                                timeout=5.0
                            )
                            if response.status_code == 200:
                                data = response.json()
                                self.telemetry.current_camera = data.get('current_camera', 'unknown')
                        except Exception:
                            pass

                        # PROGRESS-3: Leaderboard for race position + competitor tracking
                        try:
                            response = await client.get(
                                f"{self.config.cloud_url}/api/v1/events/{self.config.event_id}/leaderboard",
                                headers={"X-Truck-Token": self.config.truck_token},
                                timeout=5.0
                            )
                            if response.status_code == 200:
                                data = response.json()
                                entries = data.get('entries', [])
                                self.telemetry.total_vehicles = len(entries)
                                self.telemetry.course_length_miles = data.get('course_length_miles')

                                # Find our vehicle and extract progress + competitors
                                my_idx = None
                                for i, entry in enumerate(entries):
                                    if entry.get('vehicle_id') == self.config.vehicle_id:
                                        my_idx = i
                                        self.telemetry.race_position = entry.get('position', 0)
                                        self.telemetry.last_checkpoint = entry.get('last_checkpoint', 0)
                                        self.telemetry.delta_to_leader_ms = entry.get('delta_to_leader_ms', 0)
                                        self.telemetry.progress_miles = entry.get('progress_miles')
                                        self.telemetry.miles_remaining = entry.get('miles_remaining')
                                        break

                                # PROGRESS-3: Compute competitor ahead/behind
                                if my_idx is not None:
                                    self._compute_competitors(entries, my_idx)
                                else:
                                    self.telemetry.competitor_ahead = None
                                    self.telemetry.competitor_behind = None
                        except Exception as e:
                            logger.debug(f"Leaderboard fetch failed: {e}")

                except asyncio.CancelledError:
                    logger.info("LINK-1: Cloud status loop cancelled")
                    raise
                except Exception as e:
                    self.telemetry.cloud_connected = False
                    self.telemetry.cloud_detail = "unreachable"
                    logger.debug(f"Cloud status check failed: {e}")

                await asyncio.sleep(poll_interval)

    def _restart_cloud_status_loop(self):
        """LINK-1: Cancel and restart the cloud status loop.

        Called after settings save to pick up new cloud_url / truck_token
        without requiring a full process restart. Safe to call multiple times;
        cancels any existing task before creating a new one.
        """
        # Cancel existing task if running
        if self._cloud_status_task and not self._cloud_status_task.done():
            self._cloud_status_task.cancel()
            logger.info("LINK-1: Cancelled existing cloud status loop for restart")

        # Launch fresh loop
        self._cloud_status_task = asyncio.ensure_future(self._cloud_status_loop())
        logger.info("LINK-1: Cloud status loop restarted after settings change")

    def _write_systemd_env(self):
        """Write /etc/argus/config.env so systemd services (uplink, GPS, CAN, etc.) can start.

        The pit crew dashboard saves its own config to pit_dashboard.json,
        but systemd services read credentials from /etc/argus/config.env via
        EnvironmentFile=. This method syncs the two after setup or settings save.

        Only writes if cloud_url and truck_token are non-empty.
        Failures are logged but do not block the UI.
        """
        env_path = "/etc/argus/config.env"
        if not self.config.cloud_url or not self.config.truck_token:
            logger.info("Skipping config.env write — cloud_url or truck_token empty")
            return

        vehicle_number = self.config.vehicle_number or "000"
        content = (
            "# Argus Edge Configuration\n"
            "# Auto-generated by pit crew dashboard\n"
            "\n"
            "# Vehicle Identity\n"
            f"ARGUS_VEHICLE_NUMBER={vehicle_number}\n"
            f"ARGUS_VEHICLE_ID=truck_{vehicle_number}\n"
            "\n"
            "# Cloud Server\n"
            f"ARGUS_CLOUD_URL={self.config.cloud_url}\n"
            f"ARGUS_TRUCK_TOKEN={self.config.truck_token}\n"
            "\n"
            "# Hardware (auto-detected)\n"
            "ARGUS_GPS_DEVICE=/dev/argus_gps\n"
            "ARGUS_CAN_INTERFACE=can0\n"
            "ARGUS_CAN_BITRATE=500000\n"
            "\n"
            "# Performance\n"
            "ARGUS_GPS_HZ=10\n"
            "ARGUS_TELEMETRY_HZ=10\n"
            "ARGUS_UPLOAD_BATCH_SIZE=50\n"
            "\n"
            "# Logging\n"
            "ARGUS_LOG_LEVEL=INFO\n"
        )

        try:
            os.makedirs(os.path.dirname(env_path), exist_ok=True)
            with open(env_path, 'w') as f:
                f.write(content)
            os.chmod(env_path, 0o600)
            logger.info(f"Systemd env written to {env_path}")
        except Exception as e:
            logger.error(f"Failed to write {env_path}: {e}")

    def _activate_cloudflare_tunnel(self):
        """Write /etc/cloudflared/config.yml and start argus-cloudflared service.

        Called after setup or settings save when cloudflare_tunnel_token is set.
        Uses sudo to write the config file and manage the systemd service.
        Failures are logged but do not block the UI.

        The config.yml stores the token so the systemd service can read it.
        cloudflared reads `tunnel: <token>` from config.yml when using
        `cloudflared --config /etc/cloudflared/config.yml tunnel run`.
        """
        token = self.config.cloudflare_tunnel_token
        if not token:
            logger.info("Skipping cloudflared activation — no tunnel token configured")
            return

        # cloudflared config.yml — `tunnel` key holds the JWT token for
        # token-based tunnel auth (cloudflared tunnel run reads this)
        config_yml = (
            "# Auto-generated by Argus Pit Crew Dashboard\n"
            "# Do not edit — changes will be overwritten on next setup save.\n"
            f"tunnel: {token}\n"
            "no-autoupdate: true\n"
        )

        try:
            # Create config directory
            subprocess.run(
                ['sudo', '-n', 'mkdir', '-p', '/etc/cloudflared'],
                capture_output=True, timeout=5
            )
            # Write config file via sudo tee
            result = subprocess.run(
                ['sudo', '-n', 'tee', '/etc/cloudflared/config.yml'],
                input=config_yml, capture_output=True, text=True, timeout=5
            )
            if result.returncode != 0:
                logger.error(f"Failed to write cloudflared config: {result.stderr}")
                return

            logger.info("Cloudflare Tunnel config written to /etc/cloudflared/config.yml")

            # Reload systemd and enable+start the tunnel service
            subprocess.run(
                ['sudo', '-n', 'systemctl', 'daemon-reload'],
                capture_output=True, timeout=10
            )
            subprocess.run(
                ['sudo', '-n', 'systemctl', 'enable', 'argus-cloudflared'],
                capture_output=True, timeout=10
            )
            start_result = subprocess.run(
                ['sudo', '-n', 'systemctl', 'restart', 'argus-cloudflared'],
                capture_output=True, text=True, timeout=30
            )
            if start_result.returncode != 0:
                logger.error(f"cloudflared service failed to start: {start_result.stderr}")
                # Check journal for details
                journal = subprocess.run(
                    ['sudo', '-n', 'journalctl', '-u', 'argus-cloudflared', '-n', '20', '--no-pager'],
                    capture_output=True, text=True, timeout=10
                )
                logger.error(f"cloudflared journal:\n{journal.stdout}")
            else:
                logger.info("argus-cloudflared service started successfully")
        except subprocess.TimeoutExpired:
            logger.error("Cloudflare Tunnel activation timed out")
        except Exception as e:
            logger.error(f"Failed to activate Cloudflare Tunnel: {e}")

    def _compute_competitors(self, entries: list, my_idx: int):
        """PROGRESS-3: Compute closest competitor ahead and behind from leaderboard entries."""
        my_entry = entries[my_idx]
        my_progress = my_entry.get('progress_miles')

        # Competitor ahead (lower index = higher position)
        if my_idx > 0:
            ahead = entries[my_idx - 1]
            ahead_progress = ahead.get('progress_miles')
            gap_miles = None
            if my_progress is not None and ahead_progress is not None:
                gap_miles = round(ahead_progress - my_progress, 1)
            self.telemetry.competitor_ahead = {
                "vehicle_number": ahead.get('vehicle_number', '?'),
                "team_name": ahead.get('team_name', ''),
                "progress_miles": ahead_progress,
                "miles_remaining": ahead.get('miles_remaining'),
                "gap_miles": gap_miles,
            }
        else:
            self.telemetry.competitor_ahead = None  # We are leading

        # Competitor behind (higher index = lower position)
        if my_idx < len(entries) - 1:
            behind = entries[my_idx + 1]
            behind_progress = behind.get('progress_miles')
            gap_miles = None
            if my_progress is not None and behind_progress is not None:
                gap_miles = round(my_progress - behind_progress, 1)
            self.telemetry.competitor_behind = {
                "vehicle_number": behind.get('vehicle_number', '?'),
                "team_name": behind.get('team_name', ''),
                "progress_miles": behind_progress,
                "miles_remaining": behind.get('miles_remaining'),
                "gap_miles": gap_miles,
            }
        else:
            self.telemetry.competitor_behind = None  # We are last

    async def _send_cloud_heartbeat(self, client: httpx.AsyncClient) -> Optional[str]:
        """Send heartbeat to cloud with streaming and device status.

        CLOUD-EDGE-STATUS-1: Uses two-tier approach:
        1. Simple presence heartbeat (always works with just truck_token)
        2. Detailed production heartbeat (requires event_id for streaming status)

        EDGE-CLOUD-1: Returns cloud_detail string for banner display:
        - "healthy": connected and event is in_progress
        - "event_not_live": connected but event is draft/scheduled/completed
        - "auth_rejected": truck token invalid (401)
        - None: heartbeat failed (caller sets "unreachable")
        """
        try:
            # ── 1. Simple presence heartbeat (always send if truck_token is set) ──
            # This updates last_seen for online/offline detection even without event_id
            simple_ok = False
            cloud_detail = None
            try:
                # CLOUD-MANAGE-0: Include edge_url in simple heartbeat body
                # so Team Dashboard can auto-discover edge before event_id is known
                # Prefer Cloudflare Tunnel URL (CGNAT-proof) over LAN IP
                lan_ip = _detect_lan_ip()
                if self.config.cloudflare_tunnel_url:
                    edge_url_simple = self.config.cloudflare_tunnel_url
                else:
                    edge_url_simple = f"http://{lan_ip}:{self.config.port}"
                simple_payload = {
                    "edge_url": edge_url_simple,
                    "capabilities": ["pit_crew_dashboard", "telemetry", "cameras"],
                }
                response = await client.post(
                    f"{self.config.cloud_url}/api/v1/telemetry/heartbeat",
                    json=simple_payload,
                    headers={"X-Truck-Token": self.config.truck_token},
                    timeout=5.0
                )
                if response.status_code == 200:
                    simple_ok = True
                    data = response.json()
                    # EDGE-CLOUD-1: Determine cloud_detail from event_status
                    event_status = data.get("event_status", "")
                    if event_status == "in_progress":
                        cloud_detail = "healthy"
                    else:
                        cloud_detail = "event_not_live"
                    # Auto-discover event_id if we don't have it
                    # LINK-2: Persist to disk so it survives restarts and unblocks pit notes sync
                    if not self.config.event_id and data.get("event_id"):
                        self.config.event_id = data["event_id"]
                        self.config.save()
                        logger.info(f"LINK-2: Auto-discovered and saved event_id: {self.config.event_id}")
                elif response.status_code == 401:
                    cloud_detail = "auth_rejected"
                    logger.warning("Simple heartbeat rejected: invalid truck token")
                elif response.status_code == 400:
                    # Vehicle not registered for any event
                    cloud_detail = "event_not_live"
                    logger.info("Simple heartbeat: vehicle not registered for any event")
            except Exception as e:
                logger.debug(f"Simple heartbeat failed: {e}")

            # ── 2. Detailed production heartbeat (if event_id is available) ──
            # This sends streaming/camera status for production dashboard
            if self.config.event_id:
                # Build camera info from current status
                cameras = []
                for cam_name, device in self._camera_devices.items():
                    status = self._camera_status.get(cam_name, "unknown")
                    cameras.append({
                        "name": cam_name,
                        "device": device if os.path.exists(device) else None,
                        "status": status if os.path.exists(device) else "offline",
                    })

                # Get streaming status
                streaming = self.get_streaming_status()

                # EDGE-URL-1: Prefer Cloudflare Tunnel URL (CGNAT-proof), fall back to LAN
                if self.config.cloudflare_tunnel_url:
                    edge_url = self.config.cloudflare_tunnel_url
                else:
                    lan_ip = _detect_lan_ip()
                    edge_url = f"http://{lan_ip}:{self.config.port}"

                # Build detailed payload
                payload = {
                    "streaming_status": streaming.get("status", "idle"),
                    "streaming_camera": streaming.get("camera"),
                    "streaming_started_at": streaming.get("started_at"),
                    "streaming_error": streaming.get("error"),
                    "cameras": cameras,
                    "last_can_ts": self.telemetry.last_update_ms if self.telemetry.last_update_ms > 0 else None,
                    "last_gps_ts": self.telemetry.gps_ts_ms if self.telemetry.gps_ts_ms > 0 else None,
                    "youtube_configured": bool(self.config.youtube_stream_key),
                    "youtube_url": self.config.youtube_live_url or None,
                    "edge_url": edge_url,  # EDGE-URL-1
                }

                response = await client.post(
                    f"{self.config.cloud_url}/api/v1/production/events/{self.config.event_id}/edge/heartbeat",
                    json=payload,
                    headers={"X-Truck-Token": self.config.truck_token},
                    timeout=5.0
                )

                if response.status_code == 200:
                    logger.info(f"Cloud heartbeat OK (simple={simple_ok}, detailed=True)")
                else:
                    logger.warning(f"Detailed heartbeat rejected: HTTP {response.status_code}")
            elif simple_ok:
                logger.info("Cloud heartbeat OK (simple=True, detailed=skipped - no event_id)")

            return cloud_detail

        except Exception as e:
            logger.warning(f"Cloud heartbeat error: {e}")
            return None

    async def _cloud_command_listener(self):
        """
        Listen for commands from cloud via SSE.

        Commands:
        - set_active_camera: Switch to a different camera
        - start_stream: Start streaming
        - stop_stream: Stop streaming
        - list_cameras: Return available cameras
        - get_status: Return full status
        - set_stream_profile: Change stream quality preset (STREAM-3)
        """
        if not HTTPX_AVAILABLE or not self.config.cloud_url or not self.config.event_id:
            logger.info("Cloud command listener disabled (no cloud URL or event ID)")
            return

        reconnect_delay = 5.0
        max_delay = 60.0

        while self._running:
            try:
                url = f"{self.config.cloud_url}/api/v1/events/{self.config.event_id}/stream"
                logger.info(f"Connecting to cloud command stream: {url}")

                async with httpx.AsyncClient(timeout=None) as client:
                    async with client.stream(
                        "GET",
                        url,
                        headers={
                            "X-Truck-Token": self.config.truck_token,
                            "Accept": "text/event-stream",
                        },
                    ) as response:
                        if response.status_code != 200:
                            logger.warning(f"SSE connect failed: HTTP {response.status_code}")
                            await asyncio.sleep(reconnect_delay)
                            reconnect_delay = min(reconnect_delay * 2, max_delay)
                            continue

                        logger.info("Connected to cloud command stream")
                        reconnect_delay = 5.0  # Reset delay on success

                        event_type = None
                        event_data = ""

                        async for line in response.aiter_lines():
                            if not self._running:
                                break

                            line = line.strip()

                            if line.startswith("event:"):
                                event_type = line[6:].strip()
                            elif line.startswith("data:"):
                                event_data = line[5:].strip()
                            elif line == "" and event_type and event_data:
                                # End of event
                                await self._handle_cloud_command(event_type, event_data)
                                event_type = None
                                event_data = ""

            except httpx.ConnectError:
                logger.warning("Cloud command stream connection failed")
            except httpx.ReadTimeout:
                logger.debug("Cloud command stream timeout, reconnecting...")
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.warning(f"Cloud command stream error: {e}")

            await asyncio.sleep(reconnect_delay)
            reconnect_delay = min(reconnect_delay * 2, max_delay)

    async def _handle_cloud_command(self, event_type: str, data: str):
        """Handle an incoming cloud command."""
        if event_type != "edge_command":
            return  # Ignore other events

        try:
            payload = json.loads(data)
        except json.JSONDecodeError:
            logger.warning(f"Invalid JSON in command: {data}")
            return

        # Check if command is for this vehicle
        target_vehicle = payload.get("vehicle_id")
        if target_vehicle and target_vehicle != self.config.vehicle_id:
            return  # Command is for a different vehicle

        command_id = payload.get("command_id")
        command = payload.get("command")
        params = payload.get("params", {})

        logger.info(f"[edge-cmd] Received: command={command}, command_id={command_id}, active_camera={self._streaming_state.get('camera')}")

        # Execute command
        result = await self._execute_command(command, params)

        logger.info(f"[edge-cmd] Result: command={command}, command_id={command_id}, status={result.get('status')}")

        # Send response back to cloud
        await self._send_command_response(command_id, result)

    async def _execute_command(self, command: str, params: dict) -> dict:
        """Execute a command and return the result."""
        try:
            if command == "set_active_camera":
                camera = params.get("camera")
                request_id = params.get("request_id", "unknown")

                if not camera:
                    logger.warning(f"[camera-switch] Missing camera param, request_id={request_id}")
                    return {"status": "error", "message": "Missing camera parameter"}

                # CAM-CONTRACT-1B: Accept both canonical and legacy camera names
                all_valid_cameras = {'main', 'cockpit', 'chase', 'suspension', 'pov', 'roof', 'front', 'rear'}
                if camera not in all_valid_cameras:
                    logger.warning(f"[camera-switch] Invalid camera={camera}, request_id={request_id}")
                    return {"status": "error", "message": f"Invalid camera: {camera}. Valid: main, cockpit, chase, suspension"}
                camera = self._normalize_camera_slot(camera)

                logger.info(f"[camera-switch] Received: camera={camera}, current={self._streaming_state['camera']}, streaming={self._streaming_state['status']}, request_id={request_id}")

                # PROD-3: Rate limiting — ignore repeated switches within cooldown
                now = time.time()
                elapsed = now - self._last_camera_switch_at
                if elapsed < self._camera_switch_cooldown_s:
                    logger.info(f"[camera-switch] Rate limited ({elapsed:.1f}s < {self._camera_switch_cooldown_s}s cooldown), request_id={request_id}")
                    return {
                        "status": "success",
                        "message": f"Rate limited, current camera is {self._streaming_state['camera']}",
                        "data": {"camera": self._streaming_state['camera']}
                    }

                # PROD-3: Persist desired camera for reboot recovery (before switch)
                self._save_desired_camera(camera)

                # Switch camera (this will restart stream if already streaming)
                result = await self.switch_camera(camera)
                self._last_camera_switch_at = time.time()

                if result.get("success"):
                    self._streaming_state['camera'] = camera
                    logger.info(f"[camera-switch] Success: camera={camera}, request_id={request_id}")
                    return {
                        "status": "success",
                        "message": f"Switched to {camera} camera",
                        "data": {"camera": camera}
                    }
                else:
                    error_msg = result.get("error", "Failed to switch camera")
                    logger.warning(f"[camera-switch] Failed: camera={camera}, error={error_msg}, request_id={request_id}")
                    return {
                        "status": "error",
                        "message": error_msg
                    }

            elif command == "start_stream":
                # PROD-3: Use persisted desired camera if no camera specified
                camera = params.get("camera", self._streaming_state.get("camera", "main"))
                logger.info(f"[stream-start] Starting stream on camera={camera}")
                result = await self.start_streaming(camera)
                if result.get("success"):
                    return {
                        "status": "success",
                        "message": f"Streaming started on {camera}",
                        "data": {"camera": camera, "pid": result.get("pid")}
                    }
                else:
                    return {
                        "status": "error",
                        "message": result.get("error", "Failed to start stream")
                    }

            elif command == "stop_stream":
                result = await self.stop_streaming()
                if result.get("success"):
                    return {
                        "status": "success",
                        "message": "Streaming stopped"
                    }
                else:
                    return {
                        "status": "error",
                        "message": result.get("error", "Failed to stop stream")
                    }

            elif command == "list_cameras":
                cameras = []
                for cam_name, device in self._camera_devices.items():
                    status = "available" if os.path.exists(device) else "offline"
                    if self._streaming_state.get("status") == "live" and self._streaming_state.get("camera") == cam_name:
                        status = "active"
                    cameras.append({
                        "name": cam_name,
                        "device": device,
                        "status": status,
                    })
                return {
                    "status": "success",
                    "message": f"Found {len(cameras)} cameras",
                    "data": {"cameras": cameras}
                }

            elif command == "get_status":
                streaming = self.get_streaming_status()
                return {
                    "status": "success",
                    "message": "Status retrieved",
                    "data": {
                        "streaming": streaming,
                        "youtube_configured": bool(self.config.youtube_stream_key),
                        "vehicle_number": self.config.vehicle_number,
                    }
                }

            elif command == "set_stream_profile":
                # STREAM-3: Cloud-initiated stream profile change
                profile = params.get("profile")
                source = params.get("source", "unknown")

                if not profile:
                    return {"status": "error", "message": "Missing profile parameter"}

                valid_profiles = {"1080p30", "720p30", "480p30", "360p30"}
                if profile not in valid_profiles:
                    return {"status": "error", "message": f"Invalid profile: {profile}"}

                logger.info(f"[stream-profile] Received: profile={profile}, source={source}, current={self._stream_profile}")

                result = await self.set_stream_profile(profile)
                if result.get("success"):
                    logger.info(f"[stream-profile] Success: profile={profile}, source={source}")
                    return {
                        "status": "success",
                        "message": f"Stream profile set to {profile}",
                        "data": {"profile": profile, "source": source}
                    }
                else:
                    error_msg = result.get("error", "Failed to set stream profile")
                    logger.warning(f"[stream-profile] Failed: profile={profile}, error={error_msg}")
                    return {
                        "status": "error",
                        "message": error_msg
                    }

            else:
                return {
                    "status": "error",
                    "message": f"Unknown command: {command}"
                }

        except Exception as e:
            logger.error(f"Command execution error: {e}")
            return {
                "status": "error",
                "message": str(e)
            }

    async def _send_command_response(self, command_id: str, result: dict):
        """Send command response back to cloud."""
        if not HTTPX_AVAILABLE or not command_id:
            return

        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.config.cloud_url}/api/v1/production/events/{self.config.event_id}/edge/command-response",
                    json={
                        "command_id": command_id,
                        "status": result.get("status", "error"),
                        "message": result.get("message"),
                        "data": result.get("data"),
                    },
                    headers={"X-Truck-Token": self.config.truck_token},
                    timeout=10.0
                )

                if response.status_code == 200:
                    logger.info(f"[edge-ack] ACK sent: command_id={command_id}, status={result.get('status')}")
                else:
                    logger.warning(f"[edge-ack] ACK failed: command_id={command_id}, HTTP {response.status_code}")

        except Exception as e:
            logger.error(f"Failed to send command response: {e}")

    async def start(self):
        """Start the dashboard service."""
        self._running = True

        logger.info("=" * 60)
        logger.info("Argus Pit Crew Dashboard Starting")
        logger.info("=" * 60)
        logger.info(f"Dashboard URL: http://{self.config.host}:{self.config.port}/")
        if self.config.is_configured:
            logger.info(f"Vehicle: #{self.config.vehicle_number}")
            logger.info("Status: Configured - login required")
        else:
            logger.info("Status: NOT CONFIGURED - Setup wizard will run on first visit")
        logger.info("=" * 60)

        # Start background tasks
        # LINK-1: Track cloud status task handle so _restart_cloud_status_loop can cancel it
        self._cloud_status_task = asyncio.create_task(self._cloud_status_loop())
        tasks = [
            asyncio.create_task(self._zmq_subscriber()),
            self._cloud_status_task,
            asyncio.create_task(self._cloud_command_listener()),  # ADDED: Cloud command listener
            asyncio.create_task(self._monitor_audio()),
            asyncio.create_task(self._screenshot_capture_loop()),  # ADDED: Periodic camera screenshots
            asyncio.create_task(self._auto_downshift_loop()),  # STREAM-4: Auto quality downshift
            asyncio.create_task(self._pit_notes_sync_loop()),  # PIT-COMMS-1: Background note sync
        ]

        # Start web server
        app = self.create_app()
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, self.config.host, self.config.port)
        await site.start()

        logger.info(f"Dashboard running at http://{self.config.host}:{self.config.port}/")

        try:
            await asyncio.gather(*tasks)
        except asyncio.CancelledError:
            pass
        finally:
            await runner.cleanup()

    async def stop(self):
        """Stop the dashboard service."""
        self._running = False

        if self._zmq_socket_can:
            self._zmq_socket_can.close()
        if self._zmq_socket_gps:
            self._zmq_socket_gps.close()
        if self._zmq_socket_ant:
            self._zmq_socket_ant.close()
        if self._zmq_context:
            self._zmq_context.term()

        logger.info("Pit crew dashboard stopped")


# ============ Main Entry Point ============

async def main():
    parser = argparse.ArgumentParser(
        description="Argus Pit Crew Dashboard",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Zero-Touch Install:
  The dashboard starts automatically after installation.
  On first browser visit, a setup wizard will prompt for:
    - Dashboard password (required)
    - Vehicle number (optional)
    - Cloud connection settings (optional)

  Configuration is saved to: /opt/argus/config/pit_dashboard.json

Development:
  For development, config is saved to: ./pit_dashboard_config.json
"""
    )
    parser.add_argument(
        "--port", "-p",
        type=int,
        default=None,
        help="HTTP port (default: 8080, or from config)"
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Reset configuration and run setup wizard again"
    )
    args = parser.parse_args()

    # Load configuration from file (or create empty if not exists)
    config = DashboardConfig.load()

    # Handle --reset flag
    if args.reset:
        config_path = get_config_path()
        if os.path.exists(config_path):
            os.remove(config_path)
            logger.info(f"Configuration reset - removed {config_path}")
        config = DashboardConfig()

    # Override port if specified on command line
    if args.port:
        config.port = args.port

    dashboard = PitCrewDashboard(config)

    try:
        await dashboard.start()
    except KeyboardInterrupt:
        pass
    finally:
        await dashboard.stop()


if __name__ == "__main__":
    asyncio.run(main())
