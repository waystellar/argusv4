"""
Stream Control API Routes

Unified API for streaming control across Production Control and Pit Crew.
Implements the Stream Control State Machine for consistent state management.

These endpoints are the single source of truth for stream state.
Both Production Control and Pit Crew UIs should use these endpoints.
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Header
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models import Event, EventVehicle, Vehicle
from app.services.stream_control import (
    StreamState,
    StreamControlState,
    StreamSource,
    StreamErrorReason,
    get_stream_state,
    get_available_sources,
    start_stream,
    stop_stream,
    handle_edge_response,
    handle_command_timeout,
    retry_from_error,
)
from app.services.auth import require_admin, AuthInfo
from app import redis_client


router = APIRouter(prefix="/api/v1/stream", tags=["stream-control"])


# ============ Schemas ============

class StreamStateResponse(BaseModel):
    """Stream control state response."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    state: str  # DISCONNECTED, IDLE, STARTING, STREAMING, STOPPING, ERROR
    source_id: Optional[str] = None
    error_reason: Optional[str] = None
    error_message: Optional[str] = None
    error_guidance: Optional[str] = None
    controlled_by: Optional[str] = None
    started_at: Optional[int] = None
    command_id: Optional[str] = None
    last_updated: str
    edge_heartbeat_ms: Optional[int] = None
    edge_connected: bool = False
    youtube_url: Optional[str] = None


class StreamSourceResponse(BaseModel):
    """Available stream source."""
    source_id: str
    label: str
    type: str
    available: bool
    device: Optional[str] = None
    preview_url: Optional[str] = None
    last_seen: Optional[int] = None


class SourcesListResponse(BaseModel):
    """List of available sources."""
    vehicle_id: str
    sources: list[StreamSourceResponse]
    edge_connected: bool
    checked_at: datetime


class StartStreamRequest(BaseModel):
    """Request to start streaming."""
    source_id: str  # Required: chase, pov, roof, front


class StartStreamResponse(BaseModel):
    """Response after starting stream request."""
    state: str
    command_id: Optional[str]
    source_id: str
    message: str


class StopStreamResponse(BaseModel):
    """Response after stopping stream."""
    state: str
    command_id: Optional[str]
    message: str


class CommandStatusResponse(BaseModel):
    """Status of a pending command."""
    command_id: str
    status: str  # pending, success, error
    state: str
    message: Optional[str] = None


class TimeoutRequest(BaseModel):
    """Report command timeout."""
    command_id: str


# ============ Helper Functions ============

async def _validate_vehicle(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession,
) -> tuple[Event, Vehicle]:
    """Validate event and vehicle exist."""
    # Validate event
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Validate vehicle in event
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            EventVehicle.vehicle_id == vehicle_id,
        )
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Vehicle not found in event")

    return event, row.Vehicle


def _build_state_response(
    vehicle: Vehicle,
    state: StreamControlState,
) -> StreamStateResponse:
    """Build stream state response from state object."""
    import time
    now_ms = int(time.time() * 1000)

    edge_connected = False
    if state.edge_heartbeat_ms:
        age_s = (now_ms - state.edge_heartbeat_ms) / 1000.0
        edge_connected = age_s < 30  # 30 second threshold

    return StreamStateResponse(
        vehicle_id=vehicle.vehicle_id,
        vehicle_number=vehicle.vehicle_number,
        team_name=vehicle.team_name,
        state=state.state.value,
        source_id=state.source_id,
        error_reason=state.error_reason.value if state.error_reason else None,
        error_message=state.error_message,
        error_guidance=state.error_guidance,
        controlled_by=state.controlled_by,
        started_at=state.started_at,
        command_id=state.command_id,
        last_updated=state.last_updated,
        edge_heartbeat_ms=state.edge_heartbeat_ms,
        edge_connected=edge_connected,
        youtube_url=state.youtube_url,
    )


# ============ Endpoints ============

@router.get("/events/{event_id}/vehicles/{vehicle_id}/state", response_model=StreamStateResponse)
async def get_vehicle_stream_state(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get current stream control state for a vehicle.

    PUBLIC ENDPOINT - No authentication required.

    This is the single source of truth for stream state that both
    Production Control and Pit Crew UIs should use.

    Returns:
        StreamStateResponse with current state, source, errors, etc.
    """
    event, vehicle = await _validate_vehicle(event_id, vehicle_id, db)
    state = await get_stream_state(event_id, vehicle_id)
    return _build_state_response(vehicle, state)


@router.get("/events/{event_id}/vehicles/{vehicle_id}/sources", response_model=SourcesListResponse)
async def get_vehicle_sources(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get available stream sources (cameras) for a vehicle.

    PUBLIC ENDPOINT - No authentication required.

    Returns sources from edge heartbeat data with availability status.
    If edge is offline, returns default cameras as unavailable.
    """
    event, vehicle = await _validate_vehicle(event_id, vehicle_id, db)

    sources = await get_available_sources(event_id, vehicle_id)

    # Check edge connectivity
    edge_status = await redis_client.get_edge_status(event_id, vehicle_id)

    return SourcesListResponse(
        vehicle_id=vehicle_id,
        sources=[
            StreamSourceResponse(
                source_id=s.source_id,
                label=s.label,
                type=s.type,
                available=s.available,
                device=s.device,
                preview_url=s.preview_url,
                last_seen=s.last_seen,
            )
            for s in sources
        ],
        edge_connected=edge_status is not None,
        checked_at=datetime.utcnow(),
    )


@router.post("/events/{event_id}/vehicles/{vehicle_id}/start", response_model=StartStreamResponse)
async def start_vehicle_stream(
    event_id: str,
    vehicle_id: str,
    request: StartStreamRequest,
    db: AsyncSession = Depends(get_session),
    authorization: str = Header(None),
):
    """
    Start streaming for a vehicle.

    REQUIRES AUTHENTICATION via Authorization header.
    Can be either admin token (Production Control) or truck token (Pit Crew).

    Args:
        source_id: Camera to stream (chase, pov, roof, front) - REQUIRED

    Returns:
        StartStreamResponse with new state and command_id for tracking.

    The response state will be STARTING while waiting for edge ACK.
    Poll /state or listen to SSE for state updates.
    """
    event, vehicle = await _validate_vehicle(event_id, vehicle_id, db)

    # Determine controller based on auth
    controller = "production"  # Default for admin
    if authorization:
        if authorization.startswith("Bearer "):
            # Admin token
            controller = "production"
        elif authorization.startswith("Truck "):
            # Truck token - pit crew
            controller = "pit_crew"
    else:
        # Check X-Truck-Token header as fallback
        controller = "pit_crew"

    try:
        state, command_id = await start_stream(
            event_id=event_id,
            vehicle_id=vehicle_id,
            source_id=request.source_id,
            controller=controller,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    if state.state == StreamState.ERROR:
        return StartStreamResponse(
            state=state.state.value,
            command_id=None,
            source_id=request.source_id,
            message=state.error_message or "Failed to start stream",
        )

    return StartStreamResponse(
        state=state.state.value,
        command_id=command_id,
        source_id=request.source_id,
        message=f"Starting stream on {request.source_id}. Waiting for edge confirmation.",
    )


@router.post("/events/{event_id}/vehicles/{vehicle_id}/stop", response_model=StopStreamResponse)
async def stop_vehicle_stream(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession = Depends(get_session),
    authorization: str = Header(None),
):
    """
    Stop streaming for a vehicle.

    REQUIRES AUTHENTICATION via Authorization header.

    Stop is always allowed regardless of who started the stream.
    This ensures Production Control can stop a stream that Pit Crew started,
    and vice versa.

    Returns:
        StopStreamResponse with new state and command_id for tracking.
    """
    event, vehicle = await _validate_vehicle(event_id, vehicle_id, db)

    # Determine controller based on auth
    controller = "production" if authorization and authorization.startswith("Bearer ") else "pit_crew"

    state, command_id = await stop_stream(
        event_id=event_id,
        vehicle_id=vehicle_id,
        controller=controller,
    )

    return StopStreamResponse(
        state=state.state.value,
        command_id=command_id,
        message="Stopping stream. Waiting for edge confirmation.",
    )


@router.get("/events/{event_id}/vehicles/{vehicle_id}/command/{command_id}", response_model=CommandStatusResponse)
async def get_command_status(
    event_id: str,
    vehicle_id: str,
    command_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get status of a pending command.

    Used for polling after start/stop request.
    Alternative: listen to SSE stream_state_change events.
    """
    event, vehicle = await _validate_vehicle(event_id, vehicle_id, db)

    # Get command from Redis
    command = await redis_client.get_edge_command(event_id, vehicle_id, command_id)

    # Get current state
    state = await get_stream_state(event_id, vehicle_id)

    if not command:
        # Command expired or not found
        return CommandStatusResponse(
            command_id=command_id,
            status="expired",
            state=state.state.value,
            message="Command expired or not found",
        )

    return CommandStatusResponse(
        command_id=command_id,
        status=command.get("status", "pending"),
        state=state.state.value,
        message=command.get("message"),
    )


@router.post("/events/{event_id}/vehicles/{vehicle_id}/timeout")
async def report_command_timeout(
    event_id: str,
    vehicle_id: str,
    request: TimeoutRequest,
    db: AsyncSession = Depends(get_session),
):
    """
    Report that a command timed out.

    Called by the UI when polling expires without edge response.
    Transitions state to ERROR with EDGE_TIMEOUT reason.
    """
    event, vehicle = await _validate_vehicle(event_id, vehicle_id, db)

    state = await handle_command_timeout(
        event_id=event_id,
        vehicle_id=vehicle_id,
        command_id=request.command_id,
    )

    return _build_state_response(vehicle, state)


@router.post("/events/{event_id}/vehicles/{vehicle_id}/retry")
async def retry_from_error_state(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Clear error state and retry.

    Transitions from ERROR back to IDLE or DISCONNECTED based on connectivity.
    """
    event, vehicle = await _validate_vehicle(event_id, vehicle_id, db)

    state = await retry_from_error(event_id, vehicle_id)

    return _build_state_response(vehicle, state)


# ============ Bulk Endpoints for Dashboard ============

@router.get("/events/{event_id}/states")
async def get_all_stream_states(
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get stream states for all vehicles in an event.

    PUBLIC ENDPOINT.

    Useful for dashboards that need to show status of all vehicles.
    """
    # Validate event
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Get all vehicles
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(EventVehicle.event_id == event_id)
    )
    event_vehicles = result.all()

    states = []
    streaming_count = 0
    connected_count = 0

    for row in event_vehicles:
        vehicle = row.Vehicle
        state = await get_stream_state(event_id, vehicle.vehicle_id)
        response = _build_state_response(vehicle, state)
        states.append(response)

        if state.state == StreamState.STREAMING:
            streaming_count += 1
        if response.edge_connected:
            connected_count += 1

    return {
        "event_id": event_id,
        "vehicles": [s.model_dump() for s in states],
        "streaming_count": streaming_count,
        "connected_count": connected_count,
        "total_count": len(states),
        "checked_at": datetime.utcnow().isoformat(),
    }


# ============ Edge Response Handler ============
# This is called from production.py when edge sends command response

@router.post("/events/{event_id}/vehicles/{vehicle_id}/edge-response")
async def handle_edge_command_response(
    event_id: str,
    vehicle_id: str,
    command_id: str,
    status: str,
    message: Optional[str] = None,
    data: Optional[dict] = None,
    db: AsyncSession = Depends(get_session),
):
    """
    Handle command response from edge device.

    This endpoint is called internally when an edge device ACKs a command.
    Updates the stream state machine based on the response.
    """
    event, vehicle = await _validate_vehicle(event_id, vehicle_id, db)

    state = await handle_edge_response(
        event_id=event_id,
        vehicle_id=vehicle_id,
        command_id=command_id,
        status=status,
        message=message,
        data=data,
    )

    return _build_state_response(vehicle, state)
