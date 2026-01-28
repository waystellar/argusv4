"""
Event management API routes.
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models import Event, Checkpoint, EventVehicle, generate_id
from app.schemas import EventCreate, EventResponse, CourseUploadResponse
from app.services.gpx_parser import parse_gpx

router = APIRouter(prefix="/api/v1/events", tags=["events"])


def event_to_response(event: Event, vehicle_count: int = 0) -> EventResponse:
    """Convert Event model to EventResponse with computed fields."""
    return EventResponse(
        event_id=event.event_id,
        name=event.name,
        status=event.status,
        scheduled_start=event.scheduled_start,
        total_laps=event.total_laps,
        course_distance_m=event.course_distance_m,
        course_geojson=event.course_geojson,
        vehicle_count=vehicle_count,
        created_at=event.created_at,
    )


@router.post("", response_model=EventResponse, status_code=201)
async def create_event(
    event_data: EventCreate,
    db: AsyncSession = Depends(get_session),
):
    """Create a new racing event."""
    event = Event(
        event_id=generate_id("evt"),
        name=event_data.name,
        scheduled_start=event_data.scheduled_start,
        total_laps=event_data.total_laps,
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return event_to_response(event, vehicle_count=0)


@router.get("", response_model=list[EventResponse])
async def list_events(
    status: Optional[str] = None,
    db: AsyncSession = Depends(get_session),
):
    """List all events, optionally filtered by status."""
    # Query events with vehicle counts using a subquery
    vehicle_count_subq = (
        select(EventVehicle.event_id, func.count(EventVehicle.vehicle_id).label("count"))
        .group_by(EventVehicle.event_id)
        .subquery()
    )

    query = (
        select(Event, func.coalesce(vehicle_count_subq.c.count, 0).label("vehicle_count"))
        .outerjoin(vehicle_count_subq, Event.event_id == vehicle_count_subq.c.event_id)
        .order_by(Event.created_at.desc())
    )

    if status:
        query = query.where(Event.status == status)

    result = await db.execute(query)
    rows = result.all()

    return [event_to_response(event, vehicle_count) for event, vehicle_count in rows]


@router.get("/{event_id}", response_model=EventResponse)
async def get_event(
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Get event details."""
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Get vehicle count
    count_result = await db.execute(
        select(func.count(EventVehicle.vehicle_id))
        .where(EventVehicle.event_id == event_id)
    )
    vehicle_count = count_result.scalar() or 0

    return event_to_response(event, vehicle_count)


@router.post("/{event_id}/course", response_model=CourseUploadResponse)
async def upload_course(
    event_id: str,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_session),
):
    """Upload GPX course file for an event."""
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Validate file type
    if not file.filename.endswith(".gpx"):
        raise HTTPException(status_code=400, detail="File must be a .gpx file")

    # Parse GPX
    try:
        content = await file.read()
        gpx_data = parse_gpx(content.decode("utf-8"))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to parse GPX: {str(e)}")

    # Update event with course data
    event.course_geojson = gpx_data["geojson"]
    event.course_distance_m = gpx_data["total_distance_m"]

    # Delete existing checkpoints
    await db.execute(
        Checkpoint.__table__.delete().where(Checkpoint.event_id == event_id)
    )

    # Create checkpoints from waypoints
    # FIX: gpx_parser returns "checkpoint_number", not "number"
    for cp_data in gpx_data["checkpoints"]:
        checkpoint = Checkpoint(
            checkpoint_id=generate_id("cp"),
            event_id=event_id,
            checkpoint_number=cp_data["checkpoint_number"],
            name=cp_data["name"],
            lat=cp_data["lat"],
            lon=cp_data["lon"],
        )
        db.add(checkpoint)

    await db.commit()

    return CourseUploadResponse(
        event_id=event_id,
        total_distance_m=gpx_data["total_distance_m"],
        checkpoint_count=len(gpx_data["checkpoints"]),
        bounds=gpx_data["bounds"],
    )


@router.patch("/{event_id}/status")
async def update_event_status(
    event_id: str,
    status: str,
    db: AsyncSession = Depends(get_session),
):
    """Update event status (upcoming, in_progress, finished)."""
    if status not in ("upcoming", "in_progress", "finished"):
        raise HTTPException(status_code=400, detail="Invalid status")

    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    event.status = status
    event.updated_at = datetime.utcnow()
    await db.commit()

    return {"event_id": event_id, "status": status}
