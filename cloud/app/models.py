"""
SQLAlchemy ORM models for Argus Timing System.
"""
from datetime import datetime
from sqlalchemy import (
    Column, String, Integer, Float, Boolean, DateTime,
    BigInteger, ForeignKey, UniqueConstraint, Index, Text
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, relationship
import secrets


class Base(DeclarativeBase):
    """Base class for all models."""
    pass


def generate_id(prefix: str) -> str:
    """Generate a prefixed random ID."""
    return f"{prefix}_{secrets.token_hex(6)}"


class Event(Base):
    """Racing event (e.g., King of the Hammers 2026)."""
    __tablename__ = "events"

    event_id = Column(String, primary_key=True, default=lambda: generate_id("evt"))
    name = Column(String, nullable=False)
    description = Column(Text)  # Event description
    status = Column(String, nullable=False, default="upcoming")  # upcoming, in_progress, finished
    scheduled_start = Column(DateTime(timezone=True))
    scheduled_end = Column(DateTime(timezone=True))
    location = Column(String)  # e.g., "Las Vegas, NV"
    classes = Column(JSONB, default=list)  # List of vehicle classes e.g., ["trophy_truck", "class_1"]
    max_vehicles = Column(Integer, default=50)
    total_laps = Column(Integer, default=1)
    course_geojson = Column(JSONB)  # Parsed GPX as GeoJSON
    course_distance_m = Column(Float)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    vehicles = relationship("EventVehicle", back_populates="event")
    checkpoints = relationship("Checkpoint", back_populates="event")


class Vehicle(Base):
    """Racing vehicle (truck)."""
    __tablename__ = "vehicles"

    vehicle_id = Column(String, primary_key=True, default=lambda: generate_id("veh"))
    vehicle_number = Column(String, nullable=False)
    vehicle_class = Column(String)
    team_name = Column(String, nullable=False)
    driver_name = Column(String)
    truck_token = Column(String, unique=True, nullable=False, default=lambda: secrets.token_hex(32))
    youtube_url = Column(String)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    # Relationships
    events = relationship("EventVehicle", back_populates="vehicle")


class EventVehicle(Base):
    """Many-to-many: vehicles registered for events."""
    __tablename__ = "event_vehicles"

    event_id = Column(String, ForeignKey("events.event_id", ondelete="CASCADE"), primary_key=True)
    vehicle_id = Column(String, ForeignKey("vehicles.vehicle_id", ondelete="CASCADE"), primary_key=True)
    visible = Column(Boolean, default=True)
    registered_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    # Relationships
    event = relationship("Event", back_populates="vehicles")
    vehicle = relationship("Vehicle", back_populates="events")


class Checkpoint(Base):
    """
    Race checkpoint for timing.

    PR-3 SCHEMA: Added elevation, checkpoint_type, description from GPX parsing.
    """
    __tablename__ = "checkpoints"

    checkpoint_id = Column(String, primary_key=True, default=lambda: generate_id("cp"))
    event_id = Column(String, ForeignKey("events.event_id", ondelete="CASCADE"), nullable=False)
    checkpoint_number = Column(Integer, nullable=False)
    name = Column(String)
    lat = Column(Float, nullable=False)
    lon = Column(Float, nullable=False)
    radius_m = Column(Float, default=50.0)
    # PR-3: New fields from GPX parsing
    elevation_m = Column(Float)  # Elevation in meters from GPX
    checkpoint_type = Column(String, default="timing")  # start, finish, timing, pit
    description = Column(Text)  # Optional description from GPX

    __table_args__ = (
        UniqueConstraint("event_id", "checkpoint_number", name="uq_event_checkpoint"),
    )

    # Relationships
    event = relationship("Event", back_populates="checkpoints")


class CheckpointCrossing(Base):
    """Record of vehicle crossing a checkpoint."""
    __tablename__ = "checkpoint_crossings"

    crossing_id = Column(String, primary_key=True, default=lambda: generate_id("cx"))
    event_id = Column(String, nullable=False)
    vehicle_id = Column(String, nullable=False)
    checkpoint_id = Column(String, ForeignKey("checkpoints.checkpoint_id"), nullable=False)
    checkpoint_number = Column(Integer, nullable=False)
    lap_number = Column(Integer, nullable=False, default=1)  # Multi-lap support
    ts_ms = Column(BigInteger, nullable=False)  # Unix timestamp in milliseconds
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    __table_args__ = (
        # Unique per vehicle per checkpoint per lap
        UniqueConstraint("event_id", "vehicle_id", "checkpoint_id", "lap_number", name="uq_crossing_lap"),
        Index("idx_crossings_event", "event_id", "checkpoint_number"),
        Index("idx_crossings_vehicle_lap", "event_id", "vehicle_id", "lap_number"),
    )


class VehicleLapState(Base):
    """Tracks current lap for each vehicle (for multi-lap races)."""
    __tablename__ = "vehicle_lap_state"

    event_id = Column(String, ForeignKey("events.event_id", ondelete="CASCADE"), primary_key=True)
    vehicle_id = Column(String, ForeignKey("vehicles.vehicle_id", ondelete="CASCADE"), primary_key=True)
    current_lap = Column(Integer, nullable=False, default=1)
    last_checkpoint = Column(Integer, nullable=False, default=0)
    total_time_ms = Column(BigInteger, default=0)  # Total elapsed time
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)


class Position(Base):
    """GPS position data point."""
    __tablename__ = "positions"

    event_id = Column(String, primary_key=True)
    vehicle_id = Column(String, primary_key=True)
    ts_ms = Column(BigInteger, primary_key=True)
    lat = Column(Float, nullable=False)
    lon = Column(Float, nullable=False)
    speed_mps = Column(Float)
    heading_deg = Column(Float)
    altitude_m = Column(Float)
    hdop = Column(Float)
    satellites = Column(Integer)

    __table_args__ = (
        # FIXED: Composite indexes for performance (Issue #3 from audit)
        # Primary index for "Get Last Known Location" per vehicle:
        # SELECT * FROM positions WHERE event_id=? AND vehicle_id=? ORDER BY ts_ms DESC LIMIT 1
        Index("idx_positions_latest", "event_id", "vehicle_id", ts_ms.desc()),
        # Index for leaderboard queries - all latest positions in an event:
        # Used by: SELECT DISTINCT ON (vehicle_id) * FROM positions WHERE event_id=? ORDER BY vehicle_id, ts_ms DESC
        Index("idx_positions_event_ts", "event_id", ts_ms.desc()),
        # Index for vehicle history/replay queries:
        # SELECT * FROM positions WHERE vehicle_id=? AND ts_ms BETWEEN ? AND ? ORDER BY ts_ms
        Index("idx_positions_vehicle_history", "vehicle_id", "ts_ms"),
    )


class TelemetryPermission(Base):
    """Permission level for telemetry fields per vehicle."""
    __tablename__ = "telemetry_permissions"

    vehicle_id = Column(String, ForeignKey("vehicles.vehicle_id", ondelete="CASCADE"), primary_key=True)
    event_id = Column(String, ForeignKey("events.event_id", ondelete="CASCADE"), primary_key=True)
    field_name = Column(String, primary_key=True)  # 'gps', 'speed', 'rpm', etc.
    permission_level = Column(String, default="public")  # public, premium, private, hidden
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)


class VideoFeed(Base):
    """YouTube stream URL per vehicle camera."""
    __tablename__ = "video_feeds"

    vehicle_id = Column(String, ForeignKey("vehicles.vehicle_id", ondelete="CASCADE"), primary_key=True)
    event_id = Column(String, ForeignKey("events.event_id", ondelete="CASCADE"), primary_key=True)
    camera_name = Column(String, primary_key=True)  # 'chase', 'pov', 'roof', 'front'
    youtube_url = Column(String, nullable=False)
    permission_level = Column(String, default="public")


# FIXED: Added TelemetryData model to persist CAN bus telemetry (Issue #4 from audit)
# PR-2 SCHEMA: Canonical field names aligned across Edge/Cloud/Web
class TelemetryData(Base):
    """
    CAN bus telemetry data points (RPM, coolant, heart rate, etc.).

    PR-2 SCHEMA: Column names use canonical schema for new installations.
    Migration from v3 requires renaming columns (see SQL migration below).
    """
    __tablename__ = "telemetry_data"

    event_id = Column(String, primary_key=True)
    vehicle_id = Column(String, primary_key=True)
    ts_ms = Column(BigInteger, primary_key=True)

    # Engine telemetry (canonical names)
    rpm = Column(Integer)
    gear = Column(Integer)  # PR-2: New field
    throttle_pct = Column(Float)  # PR-2: Renamed from throttle_position
    coolant_temp_c = Column(Float)  # PR-2: Renamed from coolant_f (now Celsius)
    oil_pressure_psi = Column(Float)  # PR-2: Renamed from oil_pressure
    fuel_pressure_psi = Column(Float)  # PR-2: Renamed from fuel_pressure
    speed_mph = Column(Float)

    # Suspension telemetry
    suspension_fl = Column(Float)
    suspension_fr = Column(Float)
    suspension_rl = Column(Float)
    suspension_rr = Column(Float)

    # Biometrics
    heart_rate = Column(Integer)
    heart_rate_zone = Column(Integer)  # PR-2: New field

    __table_args__ = (
        Index("idx_telemetry_latest", "event_id", "vehicle_id", ts_ms.desc()),
        Index("idx_telemetry_event_ts", "event_id", ts_ms.desc()),
        Index("idx_telemetry_vehicle_history", "vehicle_id", "ts_ms"),
    )


# ============================================
# SQL Migration Script (for existing databases)
# ============================================
# Run this SQL to add indexes to an existing database:
#
# -- Position indexes for leaderboard performance
# CREATE INDEX IF NOT EXISTS idx_positions_latest
#     ON positions (event_id, vehicle_id, ts_ms DESC);
# CREATE INDEX IF NOT EXISTS idx_positions_event_ts
#     ON positions (event_id, ts_ms DESC);
# CREATE INDEX IF NOT EXISTS idx_positions_vehicle_history
#     ON positions (vehicle_id, ts_ms);
#
# -- Telemetry indexes for dashboard performance
# CREATE INDEX IF NOT EXISTS idx_telemetry_latest
#     ON telemetry_data (event_id, vehicle_id, ts_ms DESC);
# CREATE INDEX IF NOT EXISTS idx_telemetry_event_ts
#     ON telemetry_data (event_id, ts_ms DESC);
# CREATE INDEX IF NOT EXISTS idx_telemetry_vehicle_history
#     ON telemetry_data (vehicle_id, ts_ms);
#
# -- Analyze tables to update query planner statistics
# ANALYZE positions;
# ANALYZE telemetry_data;
