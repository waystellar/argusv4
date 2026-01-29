"""
Telemetry ingest and query API routes.

FIXED: Added rate limiting - trucks get 1000 req/min, public gets 100 req/min.
"""
import time
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Header, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert  # PR-4: For idempotent upsert
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.database import get_session
from app.models import Vehicle, EventVehicle, Position, Event, TelemetryData
from app.schemas import (
    TelemetryIngestRequest,
    TelemetryIngestResponse,
    LatestPositionsResponse,
    VehiclePosition,
)
from app.services.geo import is_valid_speed, compute_progress_miles
from app.services.checkpoint_service import check_checkpoint_crossings
from app.services.kalman_filter import smooth_position
from app import redis_client
from app.config import get_settings

settings = get_settings()
router = APIRouter(prefix="/api/v1", tags=["telemetry"])

# FIXED: Create route-specific limiter for truck endpoints (higher limit)
limiter = Limiter(key_func=get_remote_address)


async def validate_truck_token(
    x_truck_token: str = Header(..., alias="X-Truck-Token"),
    db: AsyncSession = Depends(get_session),
) -> tuple[str, str]:
    """
    Validate truck token and return (vehicle_id, event_id).
    First checks Redis cache, falls back to database.
    """
    # Check Redis cache first
    token_info = await redis_client.get_truck_token_info(x_truck_token)
    if token_info:
        return token_info["vehicle_id"], token_info["event_id"]

    # Fall back to database
    result = await db.execute(
        select(Vehicle).where(Vehicle.truck_token == x_truck_token)
    )
    vehicle = result.scalar_one_or_none()
    if not vehicle:
        raise HTTPException(status_code=401, detail="Invalid truck token")

    # Find active event registration
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle.vehicle_id,
            Event.status == "in_progress",
        )
        .order_by(Event.created_at.desc())
        .limit(1)
    )
    row = result.first()
    if not row:
        raise HTTPException(
            status_code=400,
            detail="Vehicle not registered for any active event",
        )

    event_vehicle, event = row
    event_id = event.event_id

    # Cache for future requests
    await redis_client.cache_truck_token(x_truck_token, vehicle.vehicle_id, event_id)

    return vehicle.vehicle_id, event_id


@router.post("/telemetry/ingest", response_model=TelemetryIngestResponse)
@limiter.limit(f"{settings.rate_limit_trucks}/minute")  # FIXED: Higher rate limit for trucks
async def ingest_telemetry(
    request: Request,  # FIXED: Required for rate limiter
    data: TelemetryIngestRequest,
    db: AsyncSession = Depends(get_session),
    x_truck_token: str = Header(..., alias="X-Truck-Token"),
):
    """
    Ingest batch of GPS positions from truck.
    Validates token, rejects outliers, detects checkpoint crossings.
    """
    # Validate token
    vehicle_id, event_id = await validate_truck_token(x_truck_token, db)

    # Get last known position for outlier rejection
    last_pos = await redis_client.get_latest_position(event_id, vehicle_id)

    accepted = 0
    rejected = 0
    all_crossings = []

    # Get vehicle info for SSE broadcast
    result = await db.execute(select(Vehicle).where(Vehicle.vehicle_id == vehicle_id))
    vehicle = result.scalar_one()

    for pos in data.positions:
        # Reject old data
        now_ms = int(time.time() * 1000)
        age_s = (now_ms - pos.ts_ms) / 1000.0
        if age_s > settings.position_batch_max_age_s:
            rejected += 1
            continue

        # Apply Kalman filter for smoothing and outlier rejection
        smooth_lat, smooth_lon, smooth_speed, smooth_heading, is_outlier = smooth_position(
            vehicle_id,
            pos.lat,
            pos.lon,
            pos.ts_ms,
            pos.speed_mps,
            pos.heading_deg,
        )

        if is_outlier:
            rejected += 1
            # Still use smoothed position for tracking, but don't store raw
            last_pos = {
                "lat": smooth_lat,
                "lon": smooth_lon,
                "ts_ms": pos.ts_ms,
                "speed_mps": smooth_speed,
                "heading_deg": smooth_heading,
            }
            continue

        # PR-4 IDEMPOTENCY: Use INSERT ON CONFLICT DO NOTHING for retry safety
        # If edge retries after timeout, duplicate positions are silently ignored
        # Primary key: (event_id, vehicle_id, ts_ms)
        stmt = insert(Position).values(
            event_id=event_id,
            vehicle_id=vehicle_id,
            ts_ms=pos.ts_ms,
            lat=pos.lat,  # Store raw for historical analysis
            lon=pos.lon,
            speed_mps=pos.speed_mps,
            heading_deg=pos.heading_deg,
            altitude_m=pos.altitude_m,
            hdop=pos.hdop,
            satellites=pos.satellites,
        ).on_conflict_do_nothing(
            index_elements=['event_id', 'vehicle_id', 'ts_ms']
        )
        result = await db.execute(stmt)
        if result.rowcount > 0:
            accepted += 1
        # Note: Even if duplicate, we still process for real-time display + checkpoint detection

        # Update last position with smoothed values for real-time display
        last_pos = {
            "lat": smooth_lat,
            "lon": smooth_lon,
            "ts_ms": pos.ts_ms,
            "speed_mps": smooth_speed,
            "heading_deg": smooth_heading,
            "raw_lat": pos.lat,
            "raw_lon": pos.lon,
        }

        # Check checkpoint crossings
        crossings = await check_checkpoint_crossings(
            db, event_id, vehicle_id, pos.lat, pos.lon, pos.ts_ms
        )
        all_crossings.extend(crossings)

    # FIXED: Process and store telemetry data (Issue #4 from audit)
    # PR-2 SCHEMA: Use canonical field names
    latest_telemetry = {}
    if data.telemetry:
        for telem in data.telemetry:
            # Reject old telemetry data
            now_ms = int(time.time() * 1000)
            age_s = (now_ms - telem.ts_ms) / 1000.0
            if age_s > settings.position_batch_max_age_s:
                continue

            # PR-4 IDEMPOTENCY: Use INSERT ON CONFLICT DO NOTHING for retry safety
            # Primary key: (event_id, vehicle_id, ts_ms)
            stmt = insert(TelemetryData).values(
                event_id=event_id,
                vehicle_id=vehicle_id,
                ts_ms=telem.ts_ms,
                rpm=telem.rpm,
                gear=telem.gear,
                throttle_pct=telem.throttle_pct,
                coolant_temp_c=telem.coolant_temp_c,
                oil_pressure_psi=telem.oil_pressure_psi,
                fuel_pressure_psi=telem.fuel_pressure_psi,
                speed_mph=telem.speed_mph,
                # NOTE: Suspension fields removed - not currently in use
                heart_rate=telem.heart_rate,
                heart_rate_zone=telem.heart_rate_zone,
            ).on_conflict_do_nothing(
                index_elements=['event_id', 'vehicle_id', 'ts_ms']
            )
            await db.execute(stmt)

            # Track latest telemetry for Redis/SSE (canonical field names)
            canonical_fields = [
                'rpm', 'gear', 'throttle_pct', 'coolant_temp_c',
                'oil_pressure_psi', 'fuel_pressure_psi', 'speed_mph',
                # NOTE: Suspension fields removed - not currently in use
                'heart_rate', 'heart_rate_zone'
            ]
            for field in canonical_fields:
                value = getattr(telem, field, None)
                if value is not None:
                    latest_telemetry[field] = value

    # Commit all positions and telemetry
    await db.commit()

    # PROGRESS-1: Compute course progress for the latest position
    progress_data = {}
    if last_pos:
        # Load course_geojson from event (cached query - event already validated)
        event_result = await db.execute(select(Event).where(Event.event_id == event_id))
        event_obj = event_result.scalar_one_or_none()
        if event_obj and event_obj.course_geojson:
            progress = compute_progress_miles(
                last_pos["lat"], last_pos["lon"], event_obj.course_geojson
            )
            if progress:
                progress_miles, miles_remaining, _ = progress
                progress_data = {
                    "progress_miles": round(progress_miles, 2),
                    "miles_remaining": round(miles_remaining, 2),
                }

    # Update Redis with latest position and telemetry
    # FIXED: Broadcast telemetry even when no new GPS data (supports telemetry-only uploads)
    if last_pos or latest_telemetry:
        # If we have a new position, use it; otherwise use cached position for telemetry-only updates
        if last_pos:
            last_pos["vehicle_number"] = vehicle.vehicle_number
            last_pos["team_name"] = vehicle.team_name
            # Include latest telemetry data in position cache
            last_pos.update(latest_telemetry)
            # PROGRESS-1: Include progress in cached position
            last_pos.update(progress_data)
            await redis_client.set_latest_position(event_id, vehicle_id, last_pos)
            # Track last-seen timestamp for staleness detection
            await redis_client.set_vehicle_last_seen(event_id, vehicle_id, last_pos["ts_ms"])

            # Broadcast position + telemetry to SSE subscribers
            sse_data = {
                "vehicle_id": vehicle_id,
                "vehicle_number": vehicle.vehicle_number,
                "lat": last_pos["lat"],
                "lon": last_pos["lon"],
                "speed_mps": last_pos.get("speed_mps"),
                "heading_deg": last_pos.get("heading_deg"),
                "ts_ms": last_pos["ts_ms"],
            }
            sse_data.update(latest_telemetry)
            # PROGRESS-1: Include progress in SSE broadcast
            sse_data.update(progress_data)
            await redis_client.publish_event(event_id, "position", sse_data)
        elif latest_telemetry:
            # Telemetry-only update (no GPS) - broadcast telemetry data
            # Use latest timestamp from telemetry
            latest_ts = max(t.ts_ms for t in data.telemetry) if data.telemetry else int(time.time() * 1000)
            sse_data = {
                "vehicle_id": vehicle_id,
                "vehicle_number": vehicle.vehicle_number,
                "ts_ms": latest_ts,
            }
            sse_data.update(latest_telemetry)
            await redis_client.publish_event(event_id, "telemetry", sse_data)

    return TelemetryIngestResponse(
        accepted=accepted,
        rejected=rejected,
        checkpoint_crossings=all_crossings,
    )


@router.get("/events/{event_id}/positions/latest", response_model=LatestPositionsResponse)
@limiter.limit(f"{settings.rate_limit_public}/minute")  # FIXED: Public rate limit
async def get_latest_positions(
    request: Request,  # FIXED: Required for rate limiter
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get latest positions for all vehicles in an event.
    Used for initial map load and as SSE fallback.
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Event not found")

    # Get hidden vehicles to filter out
    hidden = await redis_client.get_visible_vehicles(event_id)

    # Get latest positions from Redis
    positions = await redis_client.get_latest_positions(event_id)

    # Build response
    vehicles = []
    for vid, pos in positions.items():
        if vid in hidden:
            continue  # Skip hidden vehicles

        vehicles.append(
            VehiclePosition(
                vehicle_id=vid,
                vehicle_number=pos.get("vehicle_number", ""),
                team_name=pos.get("team_name", ""),
                lat=pos["lat"],
                lon=pos["lon"],
                speed_mps=pos.get("speed_mps"),
                heading_deg=pos.get("heading_deg"),
                last_checkpoint=pos.get("last_checkpoint"),
                last_update_ms=pos["ts_ms"],
                progress_miles=pos.get("progress_miles"),
                miles_remaining=pos.get("miles_remaining"),
            )
        )

    return LatestPositionsResponse(
        event_id=event_id,
        ts=datetime.utcnow(),
        vehicles=vehicles,
    )


@router.get("/truck/me")
@limiter.limit(f"{settings.rate_limit_trucks}/minute")
async def get_truck_info(
    request: Request,
    db: AsyncSession = Depends(get_session),
    x_truck_token: str = Header(..., alias="X-Truck-Token"),
):
    """
    Get current truck information including active event registration.

    This endpoint allows edge devices to discover:
    - Their vehicle_id
    - Their current event_id (if registered for an active event)
    - Vehicle details (number, team name, class)

    Used by video_director.py to get event_id for SSE subscription.
    """
    try:
        vehicle_id, event_id = await validate_truck_token(x_truck_token, db)
    except HTTPException as e:
        # Return structured error for edge device handling
        return {
            "status": "error",
            "message": str(e.detail),
            "vehicle_id": None,
            "event_id": None,
        }

    # Get vehicle details
    result = await db.execute(select(Vehicle).where(Vehicle.vehicle_id == vehicle_id))
    vehicle = result.scalar_one()

    # Get event details
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one()

    return {
        "status": "ok",
        "vehicle_id": vehicle_id,
        "event_id": event_id,
        "vehicle_number": vehicle.vehicle_number,
        "team_name": vehicle.team_name,
        "vehicle_class": vehicle.vehicle_class,
        "event_name": event.name,
        "event_status": event.status,
    }


@router.post("/telemetry/heartbeat")
@limiter.limit(f"{settings.rate_limit_trucks}/minute")
async def telemetry_heartbeat(
    request: Request,
    db: AsyncSession = Depends(get_session),
    x_truck_token: str = Header(..., alias="X-Truck-Token"),
):
    """
    CLOUD-EDGE-STATUS-1: Simple heartbeat endpoint for edge presence tracking.

    This endpoint allows edge devices to report they are alive WITHOUT needing
    to know their event_id upfront. The server auto-discovers the event from
    the truck token.

    EDGE-CLOUD-1: Works for events in ANY status (not just in_progress).
    Returns event_status so edge can distinguish "event not live" from "connected".

    CLOUD-MANAGE-0: Accepts optional JSON body with edge_url and capabilities.
    This allows edge_url to be available in Team Dashboard immediately, before
    the detailed production heartbeat (which requires event_id) has been sent.

    Updates:
    - last_seen timestamp in Redis (for online/offline detection)
    - edge_presence in Redis (for edge_url auto-discovery)
    - Broadcasts presence to SSE subscribers

    Returns:
    - vehicle_id, event_id (for edge to cache if needed)
    - event_status: current event status (draft, scheduled, in_progress, completed)
    - server_ts_ms (for clock sync)
    """
    # EDGE-CLOUD-1: Validate token with relaxed event status check.
    # Unlike validate_truck_token (which requires in_progress), heartbeat
    # accepts any event status so edge can connect before race starts.

    # Check Redis cache first
    token_info = await redis_client.get_truck_token_info(x_truck_token)
    if token_info:
        vehicle_id = token_info["vehicle_id"]
        event_id = token_info["event_id"]
        # Fetch current event status (cache may be stale on status)
        result = await db.execute(select(Event).where(Event.event_id == event_id))
        event_obj = result.scalar_one_or_none()
        event_status = event_obj.status if event_obj else "unknown"
    else:
        # Fall back to database
        result = await db.execute(
            select(Vehicle).where(Vehicle.truck_token == x_truck_token)
        )
        vehicle = result.scalar_one_or_none()
        if not vehicle:
            raise HTTPException(status_code=401, detail="Invalid truck token")

        # Find ANY event registration (not just in_progress)
        result = await db.execute(
            select(EventVehicle, Event)
            .join(Event, EventVehicle.event_id == Event.event_id)
            .where(EventVehicle.vehicle_id == vehicle.vehicle_id)
            .order_by(Event.created_at.desc())
            .limit(1)
        )
        row = result.first()
        if not row:
            raise HTTPException(
                status_code=400,
                detail="Vehicle not registered for any event",
            )

        event_vehicle, event_obj = row
        vehicle_id = vehicle.vehicle_id
        event_id = event_obj.event_id
        event_status = event_obj.status

        # Cache token for future requests (regardless of event status)
        await redis_client.cache_truck_token(x_truck_token, vehicle_id, event_id)

    # Update last-seen timestamp
    now_ms = int(time.time() * 1000)
    await redis_client.set_vehicle_last_seen(event_id, vehicle_id, now_ms)

    # CLOUD-MANAGE-0: Extract optional edge_url and capabilities from JSON body.
    # This allows Team Dashboard to discover edge_url before event_id is known.
    try:
        body = await request.json()
    except Exception:
        body = {}

    if body and isinstance(body, dict):
        edge_presence = {
            "edge_url": body.get("edge_url"),
            "capabilities": body.get("capabilities", []),
            "heartbeat_ts": now_ms,
            "event_id": event_id,
        }
        await redis_client.set_edge_presence(vehicle_id, edge_presence)

    # Publish presence event to SSE (optional, for real-time UI updates)
    await redis_client.publish_event(event_id, "presence", {
        "vehicle_id": vehicle_id,
        "ts_ms": now_ms,
        "status": "online",
    })

    return {
        "status": "ok",
        "vehicle_id": vehicle_id,
        "event_id": event_id,
        "event_status": event_status,
        "server_ts_ms": now_ms,
    }
