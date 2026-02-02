"""
Pydantic schemas for request/response validation.
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


# ============ Events ============

class EventCreate(BaseModel):
    """Request to create a new event."""
    name: str = Field(..., min_length=1, max_length=200)
    scheduled_start: Optional[datetime] = None
    total_laps: int = Field(default=1, ge=1, le=100)


class EventResponse(BaseModel):
    """Event details response."""
    event_id: str
    name: str
    status: str
    scheduled_start: Optional[datetime]
    total_laps: int
    course_distance_m: Optional[float]
    course_geojson: Optional[dict] = None  # GeoJSON for course display on map
    vehicle_count: int = 0  # Number of registered vehicles
    created_at: datetime

    class Config:
        from_attributes = True


class CourseUploadResponse(BaseModel):
    """Response after uploading GPX course."""
    event_id: str
    total_distance_m: float
    checkpoint_count: int
    bounds: dict


# ============ Vehicles ============

class VehicleCreate(BaseModel):
    """Request to register a new vehicle."""
    vehicle_number: str = Field(..., min_length=1, max_length=10)
    vehicle_class: Optional[str] = Field(None, max_length=50)
    team_name: str = Field(..., min_length=1, max_length=100)
    driver_name: Optional[str] = Field(None, max_length=100)
    youtube_url: Optional[str] = None


class VehicleResponse(BaseModel):
    """Vehicle details response."""
    vehicle_id: str
    vehicle_number: str
    vehicle_class: Optional[str]
    team_name: str
    driver_name: Optional[str]
    youtube_url: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class VehicleWithToken(VehicleResponse):
    """Vehicle response including truck token (only on creation)."""
    truck_token: str


class EventVehicleRegister(BaseModel):
    """Request to register vehicle for an event."""
    vehicle_id: str


# ============ Telemetry Ingest ============

class PositionPoint(BaseModel):
    """Single GPS position data point."""
    ts_ms: int = Field(..., description="Unix timestamp in milliseconds")
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    speed_mps: Optional[float] = Field(None, ge=0)
    heading_deg: Optional[float] = Field(None, ge=0, le=360)
    altitude_m: Optional[float] = None
    hdop: Optional[float] = Field(None, ge=0)
    satellites: Optional[int] = Field(None, ge=0)


class TelemetryPoint(BaseModel):
    """
    Single telemetry data point (CAN bus, sensors, biometrics).

    PR-2 SCHEMA: Canonical telemetry field names aligned across Edge/Cloud/Web.
    Field aliases provided for backwards compatibility with v3 edge devices.
    """
    ts_ms: int

    # Engine telemetry
    rpm: Optional[int] = None
    gear: Optional[int] = Field(None, description="Current gear (0=neutral, -1=reverse)")
    throttle_pct: Optional[float] = Field(
        None, ge=0, le=100,
        validation_alias="throttle_position",  # Backwards compat alias
        description="Throttle position 0-100%"
    )
    coolant_temp_c: Optional[float] = Field(
        None,
        validation_alias="coolant_f",  # Backwards compat alias (note: was Fahrenheit in v3)
        description="Coolant temperature in Celsius"
    )
    oil_pressure_psi: Optional[float] = Field(
        None,
        validation_alias="oil_pressure",  # Backwards compat alias
        description="Oil pressure in PSI"
    )
    fuel_pressure_psi: Optional[float] = Field(
        None,
        validation_alias="fuel_pressure",  # Backwards compat alias
        description="Fuel pressure in PSI"
    )
    speed_mph: Optional[float] = Field(None, description="CAN-reported speed in MPH")

    # NOTE: Suspension telemetry fields removed - not currently in use

    # Biometrics (ANT+ heart rate monitor)
    heart_rate: Optional[int] = Field(None, description="Heart rate in BPM")
    heart_rate_zone: Optional[int] = Field(
        None, ge=1, le=5,
        description="Heart rate zone 1-5"
    )

    class Config:
        populate_by_name = True  # Allow both canonical and alias names


class TelemetryIngestRequest(BaseModel):
    """Batch telemetry upload from truck.

    Positions are optional (min_length=0) to support:
    - Telemetry-only uploads when GPS device is not connected
    - CAN bus data without GPS fix (e.g., in garage)
    """
    positions: list[PositionPoint] = Field(default_factory=list, max_length=100)
    telemetry: Optional[list[TelemetryPoint]] = None


class CheckpointCrossingResponse(BaseModel):
    """Checkpoint crossing notification."""
    checkpoint_number: int
    checkpoint_name: Optional[str]
    ts_ms: int


class TelemetryIngestResponse(BaseModel):
    """Response after ingesting telemetry batch."""
    accepted: int
    rejected: int = 0
    checkpoint_crossings: list[CheckpointCrossingResponse] = []


# ============ Positions (Fan Queries) ============

class VehiclePosition(BaseModel):
    """Vehicle position for map display."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    lat: float
    lon: float
    speed_mps: Optional[float]
    heading_deg: Optional[float]
    last_checkpoint: Optional[int]
    last_update_ms: int
    progress_miles: Optional[float] = None  # PROGRESS-1: distance along course
    miles_remaining: Optional[float] = None  # PROGRESS-1: distance to finish


class LatestPositionsResponse(BaseModel):
    """All vehicle positions for an event."""
    event_id: str
    ts: datetime
    vehicles: list[VehiclePosition]


# ============ Leaderboard ============

class LeaderboardEntry(BaseModel):
    """Single leaderboard entry."""
    position: int
    vehicle_id: str
    vehicle_number: str
    team_name: str
    driver_name: Optional[str]
    last_checkpoint: int
    last_checkpoint_name: Optional[str]
    delta_to_leader_ms: int
    delta_formatted: str
    lap_number: Optional[int] = None  # TEL-DEFAULTS: current lap
    progress_miles: Optional[float] = None  # PROGRESS-1: distance along course
    miles_remaining: Optional[float] = None  # PROGRESS-1: distance to finish


class LeaderboardResponse(BaseModel):
    """Full leaderboard."""
    event_id: str
    ts: datetime
    entries: list[LeaderboardEntry]
    course_length_miles: Optional[float] = None  # PROGRESS-1: total course length


# ============ Splits ============

class SplitCrossing(BaseModel):
    """Vehicle crossing at a checkpoint."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    ts_ms: int
    delta_to_leader_ms: int
    delta_formatted: str


class CheckpointSplit(BaseModel):
    """All crossings at a checkpoint."""
    checkpoint_number: int
    name: Optional[str]
    crossings: list[SplitCrossing]


class SplitsResponse(BaseModel):
    """All splits for an event."""
    event_id: str
    checkpoints: list[CheckpointSplit]


# ============ Permissions ============

class VehicleVisibility(BaseModel):
    """Toggle vehicle visibility."""
    visible: bool


# ============ SSE Events ============

class SSEPositionEvent(BaseModel):
    """SSE event for position update."""
    vehicle_id: str
    vehicle_number: str
    lat: float
    lon: float
    speed_mps: Optional[float]
    heading_deg: Optional[float]
    ts_ms: int
    progress_miles: Optional[float] = None  # PROGRESS-1
    miles_remaining: Optional[float] = None  # PROGRESS-1


class SSECheckpointEvent(BaseModel):
    """SSE event for checkpoint crossing."""
    vehicle_id: str
    vehicle_number: str
    checkpoint_number: int
    checkpoint_name: Optional[str]
    ts_ms: int


class SSEPermissionEvent(BaseModel):
    """SSE event for permission change."""
    vehicle_id: str
    visible: bool
