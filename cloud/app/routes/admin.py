"""
Argus Timing System v4.0 - Admin API Routes

Provides endpoints for race organizers/series admins:
- System health monitoring
- Event management (CRUD)
- Vehicle registration
- Statistics

PR-1 SECURITY: All endpoints require admin authentication via X-Admin-Token header.
"""
import time
from datetime import datetime
from typing import Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel, Field
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models import Event, Vehicle, Position, EventVehicle, Checkpoint
from app import redis_client
from app.services.gpx_parser import parse_gpx, parse_kml
from app.services.auth import require_admin, AuthInfo

# PR-1 SECURITY: Router-level RBAC - all endpoints require admin auth
router = APIRouter(
    prefix="/api/v1/admin",
    tags=["admin"],
    dependencies=[Depends(require_admin)],
)

import logging
admin_logger = logging.getLogger("admin")


# Debug endpoint to verify routing
@router.get("/ping")
async def ping():
    """Simple ping endpoint to verify admin router is working."""
    return {"status": "ok", "router": "admin", "message": "Admin router is accessible"}


# ============================================
# Schemas
# ============================================

class HealthStatus(BaseModel):
    """System health status."""
    database: dict
    redis: dict
    active_connections: int
    trucks_online: int
    last_telemetry_age_s: Optional[float]


class EventCreate(BaseModel):
    """Event creation request."""
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    location: Optional[str] = None
    classes: list[str] = Field(default_factory=list)
    max_vehicles: int = Field(default=50, ge=1, le=500)


class EventUpdate(BaseModel):
    """Event update request. All fields optional - only provided fields are updated."""
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    location: Optional[str] = None
    classes: Optional[list[str]] = None
    max_vehicles: Optional[int] = Field(None, ge=1, le=500)


class EventResponse(BaseModel):
    """Event response."""
    event_id: str
    name: str
    description: Optional[str]
    status: str
    scheduled_start: Optional[datetime]
    scheduled_end: Optional[datetime]
    location: Optional[str]
    classes: list[str]
    max_vehicles: int
    vehicle_count: int
    created_at: datetime
    course_geojson: Optional[dict] = None  # GeoJSON for course display on map


class EventSummary(BaseModel):
    """Event summary for list view."""
    event_id: str
    name: str
    status: str
    scheduled_start: Optional[datetime]
    vehicle_count: int
    created_at: datetime


class VehicleCreate(BaseModel):
    """Vehicle registration request."""
    vehicle_number: str = Field(..., min_length=1, max_length=20)
    team_name: str = Field(..., min_length=1, max_length=100)
    driver_name: Optional[str] = None
    codriver_name: Optional[str] = None
    vehicle_class: str


class VehicleResponse(BaseModel):
    """Vehicle response with auth token."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    driver_name: Optional[str]
    codriver_name: Optional[str]
    vehicle_class: str
    auth_token: str
    created_at: datetime


# ============================================
# Helper Functions
# ============================================

def generate_id(prefix: str = "") -> str:
    """Generate a unique ID with optional prefix."""
    short_id = uuid4().hex[:12]
    return f"{prefix}_{short_id}" if prefix else short_id


def generate_auth_token() -> str:
    """Generate a secure auth token for a truck."""
    import secrets
    return f"truck_{secrets.token_hex(16)}"


# ============================================
# Health Endpoints
# ============================================

@router.get("/health", response_model=HealthStatus)
async def get_system_health():
    """
    Get comprehensive system health status.
    Checks database, Redis, and active connections.

    NOTE: This endpoint does NOT use Depends(get_session) because if the
    database is down, we still want to return partial health info rather
    than failing entirely.
    """
    from app.database import async_session_maker

    health = {
        "database": {"status": "unknown", "latency_ms": 0},
        "redis": {"status": "unknown", "latency_ms": 0},
        "active_connections": 0,
        "trucks_online": 0,
        "last_telemetry_age_s": None,
    }

    # Check database - create session manually to handle failures gracefully
    db = None
    try:
        start = time.time()
        db = async_session_maker()
        await db.execute(select(func.count()).select_from(Event))
        latency = (time.time() - start) * 1000
        health["database"] = {"status": "healthy", "latency_ms": round(latency, 1)}
    except Exception as e:
        health["database"] = {"status": "error", "latency_ms": 0, "error": str(e)[:100]}

    # Check Redis
    try:
        start = time.time()
        redis = await redis_client.get_redis()
        await redis.ping()
        latency = (time.time() - start) * 1000
        health["redis"] = {"status": "healthy", "latency_ms": round(latency, 1)}

        # Get active truck count from Redis (trucks that have sent data recently)
        # This is a placeholder - would need actual implementation based on how trucks report in
        health["trucks_online"] = 0

    except Exception as e:
        health["redis"] = {"status": "error", "latency_ms": 0, "error": str(e)[:100]}

    # Check last telemetry age (only if database is available)
    if db and health["database"]["status"] == "healthy":
        try:
            result = await db.execute(
                select(Position.ts_ms)
                .order_by(Position.ts_ms.desc())
                .limit(1)
            )
            last_ts_ms = result.scalar_one_or_none()
            if last_ts_ms:
                # ts_ms is milliseconds since epoch
                last_time = datetime.utcfromtimestamp(last_ts_ms / 1000)
                age = (datetime.utcnow() - last_time).total_seconds()
                health["last_telemetry_age_s"] = round(age, 1)
        except Exception:
            pass

    # Clean up database session
    if db:
        try:
            await db.close()
        except Exception:
            pass

    return health


# ============================================
# Event Endpoints
# ============================================

@router.get("/events", response_model=list[EventSummary])
async def list_events(db: AsyncSession = Depends(get_session)):
    """
    List all events with summary info.
    Returns events sorted by date (upcoming first, then live, then finished).
    """
    result = await db.execute(
        select(Event).order_by(Event.scheduled_start.desc().nullslast())
    )
    events = result.scalars().all()

    summaries = []
    for event in events:
        # Count vehicles for this event via EventVehicle junction table
        vehicle_count_result = await db.execute(
            select(func.count()).select_from(EventVehicle).where(EventVehicle.event_id == event.event_id)
        )
        vehicle_count = vehicle_count_result.scalar() or 0

        summaries.append(EventSummary(
            event_id=event.event_id,
            name=event.name,
            status=event.status,
            scheduled_start=event.scheduled_start,
            vehicle_count=vehicle_count,
            created_at=event.created_at,
        ))

    return summaries


@router.post("/events", response_model=EventResponse)
async def create_event(event_data: EventCreate, db: AsyncSession = Depends(get_session)):
    """
    Create a new race event.

    Accepts: name (required), description, scheduled_start, scheduled_end,
             location, classes, max_vehicles
    """
    admin_logger.info(f"=== CREATE EVENT ENDPOINT HIT ===")
    admin_logger.info(f"Creating event: {event_data.name}")
    admin_logger.info(f"Event data: {event_data.model_dump()}")

    event_id = generate_id("evt")

    event = Event(
        event_id=event_id,
        name=event_data.name,
        description=event_data.description,
        status="upcoming",
        scheduled_start=event_data.scheduled_start,
        scheduled_end=event_data.scheduled_end,
        location=event_data.location,
        classes=event_data.classes,
        max_vehicles=event_data.max_vehicles,
    )

    db.add(event)
    await db.commit()
    await db.refresh(event)

    return EventResponse(
        event_id=event.event_id,
        name=event.name,
        description=event.description,
        status=event.status,
        scheduled_start=event.scheduled_start,
        scheduled_end=event.scheduled_end,
        location=event.location,
        classes=event.classes or [],
        max_vehicles=event.max_vehicles or 50,
        vehicle_count=0,
        created_at=event.created_at,
    )


@router.get("/events/{event_id}", response_model=EventResponse)
async def get_event(event_id: str, db: AsyncSession = Depends(get_session)):
    """
    Get detailed event information.
    """
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()

    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Count vehicles via EventVehicle junction table
    vehicle_count_result = await db.execute(
        select(func.count()).select_from(EventVehicle).where(EventVehicle.event_id == event_id)
    )
    vehicle_count = vehicle_count_result.scalar() or 0

    return EventResponse(
        event_id=event.event_id,
        name=event.name,
        description=event.description,
        status=event.status,
        scheduled_start=event.scheduled_start,
        scheduled_end=event.scheduled_end,
        location=event.location,
        classes=event.classes or [],
        max_vehicles=event.max_vehicles or 50,
        vehicle_count=vehicle_count,
        created_at=event.created_at,
        course_geojson=event.course_geojson,  # Include course data for map display
    )


@router.patch("/events/{event_id}", response_model=EventResponse)
async def update_event(
    event_id: str,
    event_data: EventUpdate,
    db: AsyncSession = Depends(get_session)
):
    """
    Update an existing event's details.

    Only provided fields will be updated. Omitted fields remain unchanged.
    Cannot update status through this endpoint - use PUT /events/{event_id}/status instead.
    """
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()

    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Get the update data, excluding unset fields
    update_data = event_data.model_dump(exclude_unset=True)

    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")

    # Apply updates
    for field, value in update_data.items():
        setattr(event, field, value)

    await db.commit()
    await db.refresh(event)

    # Count vehicles for response
    vehicle_count_result = await db.execute(
        select(func.count()).select_from(EventVehicle).where(EventVehicle.event_id == event_id)
    )
    vehicle_count = vehicle_count_result.scalar() or 0

    admin_logger.info(f"Event {event_id} updated: {list(update_data.keys())}")

    return EventResponse(
        event_id=event.event_id,
        name=event.name,
        description=event.description,
        status=event.status,
        scheduled_start=event.scheduled_start,
        scheduled_end=event.scheduled_end,
        location=event.location,
        classes=event.classes or [],
        max_vehicles=event.max_vehicles or 50,
        vehicle_count=vehicle_count,
        created_at=event.created_at,
        course_geojson=event.course_geojson,  # Include course data for map display
    )


@router.post("/events/{event_id}/course")
async def upload_course(
    event_id: str,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_session)
):
    """
    Upload a course file (GPX/KML) for an event.
    Parses the file, stores course GeoJSON, and creates checkpoints.
    """
    # Verify event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()

    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Validate file type
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename provided")

    ext = file.filename.lower().split('.')[-1]
    if ext not in ['gpx', 'kml', 'kmz']:
        raise HTTPException(status_code=400, detail="Invalid file type. Use .gpx, .kml, or .kmz")

    # Read file content
    content = await file.read()

    # Parse based on file type
    try:
        content_str = content.decode('utf-8')
        if ext == 'gpx':
            course_data = parse_gpx(content_str)
        elif ext in ['kml', 'kmz']:
            course_data = parse_kml(content_str)
        else:
            raise HTTPException(status_code=400, detail="Unsupported file format")
    except NotImplementedError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        admin_logger.error(f"Failed to parse course file: {e}")
        raise HTTPException(status_code=400, detail=f"Failed to parse file: {str(e)}")

    # Update event with course GeoJSON and distance
    event.course_geojson = course_data["geojson"]
    if hasattr(event, 'course_distance_m'):
        event.course_distance_m = course_data["total_distance_m"]

    # Delete existing checkpoints for this event
    await db.execute(
        Checkpoint.__table__.delete().where(Checkpoint.event_id == event_id)
    )

    # Create new checkpoints with all parsed fields (PR-3 SCHEMA)
    checkpoints_created = 0
    for cp_data in course_data["checkpoints"]:
        checkpoint = Checkpoint(
            event_id=event_id,
            checkpoint_number=cp_data["checkpoint_number"],
            name=cp_data["name"],
            lat=cp_data["lat"],
            lon=cp_data["lon"],
            radius_m=cp_data["radius_m"],
            # PR-3: New fields from GPX parsing
            elevation_m=cp_data.get("elevation_m"),
            checkpoint_type=cp_data.get("checkpoint_type", "timing"),
            description=cp_data.get("description"),
        )
        db.add(checkpoint)
        checkpoints_created += 1

    await db.commit()

    return {
        "status": "ok",
        "message": f"Course file '{file.filename}' uploaded successfully",
        "total_distance_m": course_data["total_distance_m"],
        "point_count": course_data["point_count"],
        "checkpoints_created": checkpoints_created,
        "bounds": course_data["bounds"],
    }


# ============================================
# Vehicle Endpoints
# ============================================

@router.get("/events/{event_id}/vehicles", response_model=list[VehicleResponse])
async def list_vehicles(event_id: str, db: AsyncSession = Depends(get_session)):
    """
    List all vehicles registered for an event.
    Uses EventVehicle junction table to find vehicles for this event.
    """
    # Join Vehicle with EventVehicle to get vehicles for this event
    result = await db.execute(
        select(Vehicle)
        .join(EventVehicle, Vehicle.vehicle_id == EventVehicle.vehicle_id)
        .where(EventVehicle.event_id == event_id)
        .order_by(Vehicle.vehicle_number)
    )
    vehicles = result.scalars().all()

    return [
        VehicleResponse(
            vehicle_id=v.vehicle_id,
            vehicle_number=v.vehicle_number,
            team_name=v.team_name,
            driver_name=v.driver_name,
            codriver_name=None,
            vehicle_class=v.vehicle_class or 'unknown',
            auth_token=v.truck_token,  # Use truck_token from model
            created_at=v.created_at,
        )
        for v in vehicles
    ]


@router.post("/events/{event_id}/vehicles", response_model=VehicleResponse)
async def register_vehicle(
    event_id: str,
    vehicle_data: VehicleCreate,
    db: AsyncSession = Depends(get_session)
):
    """
    Register a new vehicle for an event.
    Creates vehicle and registers it for the event via EventVehicle.
    """
    # Verify event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()

    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Check if vehicle number already exists for this event
    existing = await db.execute(
        select(Vehicle)
        .join(EventVehicle, Vehicle.vehicle_id == EventVehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            Vehicle.vehicle_number == vehicle_data.vehicle_number
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
            detail=f"Vehicle number {vehicle_data.vehicle_number} already registered for this event"
        )

    vehicle_id = generate_id("veh")
    auth_token = generate_auth_token()

    # Create vehicle
    vehicle = Vehicle(
        vehicle_id=vehicle_id,
        vehicle_number=vehicle_data.vehicle_number,
        vehicle_class=vehicle_data.vehicle_class,
        team_name=vehicle_data.team_name,
        driver_name=vehicle_data.driver_name,
        truck_token=auth_token,
    )
    db.add(vehicle)

    # Register vehicle for event
    event_vehicle = EventVehicle(
        event_id=event_id,
        vehicle_id=vehicle_id,
    )
    db.add(event_vehicle)

    await db.commit()
    await db.refresh(vehicle)

    return VehicleResponse(
        vehicle_id=vehicle.vehicle_id,
        vehicle_number=vehicle.vehicle_number,
        team_name=vehicle.team_name,
        driver_name=vehicle.driver_name,
        codriver_name=vehicle_data.codriver_name,
        vehicle_class=vehicle_data.vehicle_class,
        auth_token=auth_token,
        created_at=vehicle.created_at,
    )


@router.post("/events/{event_id}/vehicles/{vehicle_id}/regenerate-token")
async def regenerate_vehicle_token(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession = Depends(get_session)
):
    """
    Regenerate the auth token for a vehicle.
    Use if the token was compromised or lost.
    """
    # Verify vehicle is registered for this event
    result = await db.execute(
        select(Vehicle)
        .join(EventVehicle, Vehicle.vehicle_id == EventVehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            Vehicle.vehicle_id == vehicle_id
        )
    )
    vehicle = result.scalar_one_or_none()

    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found or not registered for this event")

    new_token = generate_auth_token()

    # Update the truck_token in the database
    vehicle.truck_token = new_token
    await db.commit()

    return {
        "vehicle_id": vehicle_id,
        "new_token": new_token,
        "message": "Token regenerated. Update the truck with the new token.",
    }


# ============================================
# Event Status Endpoints
# ============================================

class StatusUpdate(BaseModel):
    """Event status update request."""
    status: str = Field(..., pattern="^(upcoming|in_progress|finished)$")


@router.put("/events/{event_id}/status")
async def update_event_status(
    event_id: str,
    status_data: StatusUpdate,
    db: AsyncSession = Depends(get_session)
):
    """
    Update event status (start/stop race).

    Valid transitions:
    - upcoming -> in_progress (start race)
    - in_progress -> finished (end race)
    - finished -> upcoming (reset for re-run)
    """
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()

    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    old_status = event.status
    new_status = status_data.status

    # Validate transition
    valid_transitions = {
        "upcoming": ["in_progress"],
        "in_progress": ["finished"],
        "finished": ["upcoming"],
    }

    if new_status not in valid_transitions.get(old_status, []):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status transition: {old_status} -> {new_status}"
        )

    event.status = new_status
    await db.commit()

    admin_logger.info(f"Event {event_id} status changed: {old_status} -> {new_status}")

    return {
        "event_id": event_id,
        "old_status": old_status,
        "new_status": new_status,
        "message": f"Event status updated to {new_status}",
    }


# ============================================
# Delete Endpoints
# ============================================

@router.delete("/events/{event_id}")
async def delete_event(event_id: str, db: AsyncSession = Depends(get_session)):
    """
    Delete an event and all associated data.

    WARNING: This is a destructive operation that removes:
    - The event itself
    - All vehicle registrations for this event (EventVehicle records)
    - All checkpoint crossings for this event
    - All position data for this event

    Use with caution. Events that are 'in_progress' cannot be deleted.
    """
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()

    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Safety check: don't allow deletion of in-progress events
    if event.status == "in_progress":
        raise HTTPException(
            status_code=400,
            detail="Cannot delete an event that is currently in progress. End the race first."
        )

    event_name = event.name

    # Delete associated data (cascade should handle EventVehicle, Checkpoint)
    # For Position and other data that might not have FK cascade, delete explicitly
    from app.models import Position, CheckpointCrossing

    # Delete positions for this event
    await db.execute(
        Position.__table__.delete().where(Position.event_id == event_id)
    )

    # Delete checkpoint crossings for this event
    await db.execute(
        CheckpointCrossing.__table__.delete().where(CheckpointCrossing.event_id == event_id)
    )

    # Delete the event (cascades to EventVehicle, Checkpoint)
    await db.delete(event)
    await db.commit()

    admin_logger.info(f"Event {event_id} ({event_name}) deleted")

    return {
        "status": "ok",
        "event_id": event_id,
        "message": f"Event '{event_name}' and all associated data deleted",
    }


@router.delete("/events/{event_id}/vehicles/{vehicle_id}")
async def delete_vehicle_from_event(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession = Depends(get_session)
):
    """
    Remove a vehicle from an event.

    This removes the EventVehicle registration record.
    The Vehicle record itself is kept (for historical tracking).
    Position data for this vehicle in this event is also deleted.
    """
    # Verify event exists
    event_result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = event_result.scalar_one_or_none()

    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Safety check: don't allow removal during in-progress events
    if event.status == "in_progress":
        raise HTTPException(
            status_code=400,
            detail="Cannot remove vehicles from an event that is currently in progress"
        )

    # Find the vehicle registration
    result = await db.execute(
        select(EventVehicle).where(
            EventVehicle.event_id == event_id,
            EventVehicle.vehicle_id == vehicle_id
        )
    )
    event_vehicle = result.scalar_one_or_none()

    if not event_vehicle:
        raise HTTPException(
            status_code=404,
            detail="Vehicle not found or not registered for this event"
        )

    # Get vehicle info for response
    vehicle_result = await db.execute(select(Vehicle).where(Vehicle.vehicle_id == vehicle_id))
    vehicle = vehicle_result.scalar_one_or_none()
    vehicle_number = vehicle.vehicle_number if vehicle else "unknown"

    # Delete position data for this vehicle in this event
    from app.models import Position, CheckpointCrossing

    await db.execute(
        Position.__table__.delete().where(
            Position.event_id == event_id,
            Position.vehicle_id == vehicle_id
        )
    )

    # Delete checkpoint crossings for this vehicle in this event
    await db.execute(
        CheckpointCrossing.__table__.delete().where(
            CheckpointCrossing.event_id == event_id,
            CheckpointCrossing.vehicle_id == vehicle_id
        )
    )

    # Remove the event registration
    await db.delete(event_vehicle)
    await db.commit()

    admin_logger.info(f"Vehicle {vehicle_id} (#{vehicle_number}) removed from event {event_id}")

    return {
        "status": "ok",
        "event_id": event_id,
        "vehicle_id": vehicle_id,
        "message": f"Vehicle #{vehicle_number} removed from event",
    }
