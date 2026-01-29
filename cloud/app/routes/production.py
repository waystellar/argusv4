"""
Production Director API routes - Camera switching and broadcast control.

These endpoints allow production directors to control the live broadcast,
including switching between vehicle cameras and selecting featured vehicles.

Missing feature implementation from Product Vision - Multi-Camera Architecture.

PR-1 SECURITY: Write endpoints require admin authentication via X-Admin-Token header.
Read endpoints (GET) remain public for fan viewers.
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models import Event, EventVehicle, Vehicle, VideoFeed, Position, PitNote
from app import redis_client
from app.config import get_settings
from app.services.auth import require_admin, AuthInfo
from app.services import stream_control
import re
import time
import uuid
import structlog

logger = structlog.get_logger()

settings = get_settings()
router = APIRouter(prefix="/api/v1/production", tags=["production"])

# Secondary router for edge-compatible paths (no prefix - added directly by main.py)
# Edge devices poll /api/v1/events/{event_id}/production/status
events_router = APIRouter(tags=["production"])

# TEAM-2: Shared regex for extracting YouTube video ID from various URL formats
_YOUTUBE_ID_RE = re.compile(
    r'(?:youtu\.be/|youtube\.com/(?:embed/|v/|watch\?v=|watch\?.+&v=|live/))([^?&/]+)'
)


def _youtube_embed_url(youtube_url: str) -> str:
    """Convert a YouTube watch/live URL to an embed URL. Returns '' if no match."""
    if not youtube_url:
        return ""
    m = _YOUTUBE_ID_RE.search(youtube_url)
    if m:
        return f"https://www.youtube.com/embed/{m.group(1)}?autoplay=1&mute=1"
    return ""


# ============ Schemas ============

class CameraSwitchRequest(BaseModel):
    """Request to switch active camera."""
    vehicle_id: str
    camera_name: str  # e.g., "chase", "pov", "roof", "front"


class FeaturedVehicleRequest(BaseModel):
    """Set featured vehicle for broadcast."""
    vehicle_id: str
    duration_seconds: Optional[int] = None  # None = until changed


class BroadcastStateResponse(BaseModel):
    """Current broadcast state."""
    event_id: str
    featured_vehicle_id: Optional[str]
    featured_camera: Optional[str]
    active_feeds: list[dict]
    updated_at: datetime


class CameraFeedResponse(BaseModel):
    """Available camera feed."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    camera_name: str
    youtube_url: str
    embed_url: str = ""
    type: str = "youtube"
    featured: bool = False
    is_live: bool


class TruckStatusResponse(BaseModel):
    """Truck connectivity status."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    status: str  # 'online', 'stale', 'offline', 'never_connected'
    last_heartbeat_ms: Optional[int]
    last_heartbeat_ago_s: Optional[float]
    data_rate_hz: float
    has_video_feed: bool


class TruckStatusListResponse(BaseModel):
    """List of all truck statuses for an event."""
    event_id: str
    trucks: list[TruckStatusResponse]
    online_count: int
    total_count: int
    checked_at: datetime


# ============ Edge Status Schemas ============

class EdgeCameraInfo(BaseModel):
    """Info about a camera device on the edge."""
    name: str  # chase, pov, roof, front
    device: Optional[str]  # /dev/video0, etc.
    status: str  # online, offline, error


class EdgeHeartbeatRequest(BaseModel):
    """Heartbeat from edge device reporting current status."""
    streaming_status: str  # idle, starting, live, error, stopping
    streaming_camera: Optional[str]  # Which camera is streaming
    streaming_started_at: Optional[int]  # Timestamp when streaming started
    streaming_error: Optional[str]  # Last error message if any
    cameras: list[EdgeCameraInfo]  # Available cameras
    last_can_ts: Optional[int]  # Last CAN telemetry timestamp
    last_gps_ts: Optional[int]  # Last GPS timestamp
    youtube_configured: bool  # Whether YouTube stream key is set
    youtube_url: Optional[str]  # Public YouTube URL
    # EDGE-URL-1: Edge device self-reported base URL for Pit Crew Portal access
    edge_url: Optional[str] = None  # e.g. http://192.168.0.18:8080


class EdgeStatusResponse(BaseModel):
    """Edge device status for control room display."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    # Connection status (from telemetry)
    connection_status: str  # online, stale, offline, never_connected
    last_heartbeat_ms: Optional[int]
    last_heartbeat_ago_s: Optional[float]
    data_rate_hz: float
    # Edge-reported status
    edge_online: bool  # Whether we've received a heartbeat recently
    streaming_status: str  # idle, starting, live, error
    streaming_camera: Optional[str]
    streaming_uptime_s: Optional[int]
    streaming_error: Optional[str]
    cameras: list[EdgeCameraInfo]
    last_can_ts: Optional[int]
    last_gps_ts: Optional[int]
    youtube_configured: bool
    youtube_url: Optional[str]
    edge_heartbeat_ms: Optional[int]


class EdgeStatusListResponse(BaseModel):
    """All edge statuses for an event."""
    event_id: str
    edges: list[EdgeStatusResponse]
    streaming_count: int  # Edges actively streaming
    online_count: int  # Edges with recent heartbeat
    total_count: int
    checked_at: datetime


# ============ Edge Command Schemas ============

class EdgeCommandRequest(BaseModel):
    """Command from cloud to edge device."""
    command: str  # set_active_camera, start_stream, stop_stream, list_cameras, get_status
    params: Optional[dict] = None  # e.g., {"camera": "pov"}


class EdgeCommandResponse(BaseModel):
    """Response from edge device to cloud."""
    command_id: str
    status: str  # success, error, pending
    message: Optional[str] = None
    data: Optional[dict] = None


class EdgeCommandResult(BaseModel):
    """Full command result for API response."""
    command_id: str
    vehicle_id: str
    command: str
    params: Optional[dict]
    status: str  # pending, success, error, timeout
    message: Optional[str]
    data: Optional[dict]
    sent_at: datetime
    responded_at: Optional[datetime]


class ActiveCameraState(BaseModel):
    """Persisted active camera state for a vehicle."""
    vehicle_id: str
    event_id: str
    camera: str  # chase, pov, roof, front
    streaming: bool
    updated_at: datetime
    updated_by: str  # admin_id or "edge"


# ============ PROMPT 4: Fan Page Stream State ============

class RacerStreamState(BaseModel):
    """
    Stream state for a vehicle - the single source of truth for fans.

    This model combines edge status and active camera state to provide
    a consistent view of what stream fans should be watching.
    """
    vehicle_id: str
    vehicle_number: str
    team_name: str
    # Stream status
    is_live: bool  # Whether stream is actively broadcasting
    streaming_status: str  # idle, starting, live, error
    # Active camera (what's being broadcast)
    active_camera: Optional[str]  # chase, pov, roof, front - the camera currently streaming
    # YouTube embed info
    youtube_url: Optional[str]  # The public YouTube URL to display
    youtube_embed_url: Optional[str]  # Ready-to-embed YouTube URL
    # Error state
    last_error: Optional[str]  # Last streaming error message
    # Timestamps
    streaming_started_at: Optional[int]  # When stream started (epoch ms)
    streaming_uptime_s: Optional[int]  # How long stream has been live
    updated_at: datetime  # When this state was last updated


class RacerStreamStateList(BaseModel):
    """All vehicle stream states for an event."""
    event_id: str
    vehicles: list[RacerStreamState]
    live_count: int  # Number of vehicles currently streaming
    checked_at: datetime


# ============ PROD-1: Featured Camera Schemas ============

class FeaturedCameraRequest(BaseModel):
    """Request to set featured camera for a vehicle."""
    camera_id: str  # chase, pov, roof, front


class FeaturedCameraResponse(BaseModel):
    """Response after requesting a camera switch."""
    request_id: str
    vehicle_id: str
    desired_camera: str
    status: str  # pending, success, failed, timeout


class FeaturedCameraState(BaseModel):
    """Full featured camera state for a vehicle."""
    vehicle_id: str
    event_id: str
    desired_camera: Optional[str]
    active_camera: Optional[str]
    request_id: Optional[str]
    status: str  # pending, success, failed, timeout, idle
    last_error: Optional[str]
    updated_at: datetime


# ============ Endpoints ============
# PR-1 SECURITY: Write endpoints use require_admin from centralized auth module.
# Read endpoints (GET) remain public for fan viewers.

@router.get("/events/{event_id}/broadcast", response_model=BroadcastStateResponse)
async def get_broadcast_state(
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get current broadcast state for an event.
    Shows featured vehicle, active camera, and available feeds.
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Get broadcast state from Redis
    state = await redis_client.get_json(f"broadcast:{event_id}")

    # Get all active video feeds
    result = await db.execute(
        select(VideoFeed, Vehicle)
        .join(Vehicle, VideoFeed.vehicle_id == Vehicle.vehicle_id)
        .where(
            VideoFeed.event_id == event_id,
            VideoFeed.permission_level == "public",
        )
    )
    feeds = [
        {
            "vehicle_id": row.VideoFeed.vehicle_id,
            "vehicle_number": row.Vehicle.vehicle_number,
            "team_name": row.Vehicle.team_name,
            "camera_name": row.VideoFeed.camera_name,
            "youtube_url": row.VideoFeed.youtube_url,
        }
        for row in result.all()
    ]

    return BroadcastStateResponse(
        event_id=event_id,
        featured_vehicle_id=state.get("featured_vehicle_id") if state else None,
        featured_camera=state.get("featured_camera") if state else None,
        active_feeds=feeds,
        updated_at=datetime.utcnow(),
    )


@router.post("/events/{event_id}/switch-camera")
async def switch_camera(
    event_id: str,
    data: CameraSwitchRequest,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Switch the featured camera for broadcast.
    Broadcasts camera switch event to all SSE clients.
    """
    # Validate event and vehicle
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            EventVehicle.vehicle_id == data.vehicle_id,
        )
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Vehicle not registered for event")

    # Validate camera feed exists
    result = await db.execute(
        select(VideoFeed).where(
            VideoFeed.event_id == event_id,
            VideoFeed.vehicle_id == data.vehicle_id,
            VideoFeed.camera_name == data.camera_name,
        )
    )
    feed = result.scalar_one_or_none()
    if not feed:
        raise HTTPException(status_code=404, detail="Camera feed not found")

    # Update broadcast state in Redis
    state = {
        "featured_vehicle_id": data.vehicle_id,
        "featured_camera": data.camera_name,
        "youtube_url": feed.youtube_url,
        "updated_at": datetime.utcnow().isoformat(),
    }
    await redis_client.set_json(f"broadcast:{event_id}", state)

    # Broadcast camera switch to SSE clients
    await redis_client.publish_event(
        event_id,
        "camera_switch",
        {
            "vehicle_id": data.vehicle_id,
            "vehicle_number": row.Vehicle.vehicle_number,
            "camera_name": data.camera_name,
            "youtube_url": feed.youtube_url,
        },
    )

    return {
        "status": "switched",
        "vehicle_id": data.vehicle_id,
        "camera_name": data.camera_name,
        "youtube_url": feed.youtube_url,
    }


@router.post("/events/{event_id}/featured-vehicle")
async def set_featured_vehicle(
    event_id: str,
    data: FeaturedVehicleRequest,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Set the featured vehicle for broadcast highlights.
    Can optionally set a duration after which it reverts to auto-selection.
    """
    # Validate vehicle
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            EventVehicle.vehicle_id == data.vehicle_id,
        )
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Vehicle not registered for event")

    # Get current broadcast state
    state = await redis_client.get_json(f"broadcast:{event_id}") or {}

    # Update featured vehicle
    state["featured_vehicle_id"] = data.vehicle_id
    state["featured_until"] = None
    if data.duration_seconds:
        import time
        state["featured_until"] = int(time.time()) + data.duration_seconds

    await redis_client.set_json(f"broadcast:{event_id}", state)

    # Broadcast featured vehicle change
    await redis_client.publish_event(
        event_id,
        "featured_vehicle",
        {
            "vehicle_id": data.vehicle_id,
            "vehicle_number": row.Vehicle.vehicle_number,
            "team_name": row.Vehicle.team_name,
            "duration_seconds": data.duration_seconds,
        },
    )

    return {
        "status": "featured",
        "vehicle_id": data.vehicle_id,
        "vehicle_number": row.Vehicle.vehicle_number,
        "duration_seconds": data.duration_seconds,
    }


# ============ PROMPT 4: Public Stream State Endpoints ============

@router.get("/events/{event_id}/vehicles/{vehicle_id}/stream-state", response_model=RacerStreamState)
async def get_racer_stream_state(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get the current stream state for a single vehicle.

    PUBLIC ENDPOINT - No authentication required.

    This is the single source of truth for fans to know:
    - Is this racer streaming?
    - Which camera is active?
    - What YouTube URL should I show?

    The endpoint combines:
    - Edge heartbeat status (is_live, streaming_camera)
    - Persisted active camera state
    - YouTube URL from edge or video feed database
    """
    # Validate vehicle exists in event
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

    vehicle = row.Vehicle
    now = datetime.utcnow()
    now_ms = int(time.time() * 1000)

    # Get edge-reported status (live streaming info)
    edge_status = await redis_client.get_edge_status(event_id, vehicle_id) or {}

    # Get persisted active camera state
    active_camera_state = await redis_client.get_active_camera(event_id, vehicle_id)

    # Determine streaming state
    streaming_status = edge_status.get("streaming_status", "idle")
    is_live = streaming_status == "live"

    # Determine active camera (edge-reported takes precedence if streaming)
    if is_live and edge_status.get("streaming_camera"):
        active_camera = edge_status.get("streaming_camera")
    elif active_camera_state:
        active_camera = active_camera_state.get("camera")
    else:
        active_camera = None

    # Get YouTube URL - from edge status or fallback to database
    youtube_url = edge_status.get("youtube_url")

    if not youtube_url:
        # Fallback: Try to get from video feed database
        feed_result = await db.execute(
            select(VideoFeed)
            .where(
                VideoFeed.event_id == event_id,
                VideoFeed.vehicle_id == vehicle_id,
                VideoFeed.camera_name == (active_camera or "chase"),
            )
        )
        feed = feed_result.scalar_one_or_none()
        if feed:
            youtube_url = feed.youtube_url

    # Build YouTube embed URL if we have a regular YouTube URL
    youtube_embed_url = _youtube_embed_url(youtube_url) or None

    # Calculate streaming uptime
    streaming_started_at = edge_status.get("streaming_started_at")
    streaming_uptime_s = None
    if streaming_started_at and is_live:
        streaming_uptime_s = int((now_ms - streaming_started_at) / 1000)

    # Determine updated_at (most recent of edge heartbeat or camera state)
    edge_heartbeat_ts = edge_status.get("heartbeat_ts")
    camera_updated_at = active_camera_state.get("updated_at") if active_camera_state else None

    if edge_heartbeat_ts:
        updated_at = datetime.utcfromtimestamp(edge_heartbeat_ts / 1000)
    elif camera_updated_at:
        updated_at = datetime.fromisoformat(camera_updated_at)
    else:
        updated_at = now

    return RacerStreamState(
        vehicle_id=vehicle_id,
        vehicle_number=vehicle.vehicle_number,
        team_name=vehicle.team_name,
        is_live=is_live,
        streaming_status=streaming_status,
        active_camera=active_camera,
        youtube_url=youtube_url,
        youtube_embed_url=youtube_embed_url,
        last_error=edge_status.get("streaming_error"),
        streaming_started_at=streaming_started_at,
        streaming_uptime_s=streaming_uptime_s,
        updated_at=updated_at,
    )


@router.get("/events/{event_id}/stream-states", response_model=RacerStreamStateList)
async def get_all_stream_states(
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get stream states for all vehicles in an event.

    PUBLIC ENDPOINT - No authentication required.

    Returns stream state for all visible vehicles, sorted by:
    1. Live streams first
    2. Then by vehicle number
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Get all visible vehicles for this event
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            EventVehicle.visible == True,
        )
    )
    event_vehicles = result.all()

    if not event_vehicles:
        return RacerStreamStateList(
            event_id=event_id,
            vehicles=[],
            live_count=0,
            checked_at=datetime.utcnow(),
        )

    # Get all edge statuses from Redis
    edge_statuses = await redis_client.get_all_edge_statuses(event_id)

    now = datetime.utcnow()
    now_ms = int(time.time() * 1000)
    vehicles = []
    live_count = 0

    for row in event_vehicles:
        vehicle = row.Vehicle

        # Get edge-reported status
        edge_status = edge_statuses.get(vehicle.vehicle_id, {})

        # Get persisted active camera state
        active_camera_state = await redis_client.get_active_camera(event_id, vehicle.vehicle_id)

        # Determine streaming state
        streaming_status = edge_status.get("streaming_status", "idle")
        is_live = streaming_status == "live"
        if is_live:
            live_count += 1

        # Determine active camera
        if is_live and edge_status.get("streaming_camera"):
            active_camera = edge_status.get("streaming_camera")
        elif active_camera_state:
            active_camera = active_camera_state.get("camera")
        else:
            active_camera = None

        # Get YouTube URL
        youtube_url = edge_status.get("youtube_url")

        if not youtube_url:
            # Fallback: Try video feed database
            feed_result = await db.execute(
                select(VideoFeed)
                .where(
                    VideoFeed.event_id == event_id,
                    VideoFeed.vehicle_id == vehicle.vehicle_id,
                    VideoFeed.camera_name == (active_camera or "chase"),
                )
            )
            feed = feed_result.scalar_one_or_none()
            if feed:
                youtube_url = feed.youtube_url

        # Build embed URL
        youtube_embed_url = _youtube_embed_url(youtube_url) or None

        # Calculate uptime
        streaming_started_at = edge_status.get("streaming_started_at")
        streaming_uptime_s = None
        if streaming_started_at and is_live:
            streaming_uptime_s = int((now_ms - streaming_started_at) / 1000)

        # Determine updated_at
        edge_heartbeat_ts = edge_status.get("heartbeat_ts")
        camera_updated_at = active_camera_state.get("updated_at") if active_camera_state else None

        if edge_heartbeat_ts:
            updated_at = datetime.utcfromtimestamp(edge_heartbeat_ts / 1000)
        elif camera_updated_at:
            updated_at = datetime.fromisoformat(camera_updated_at)
        else:
            updated_at = now

        vehicles.append(RacerStreamState(
            vehicle_id=vehicle.vehicle_id,
            vehicle_number=vehicle.vehicle_number,
            team_name=vehicle.team_name,
            is_live=is_live,
            streaming_status=streaming_status,
            active_camera=active_camera,
            youtube_url=youtube_url,
            youtube_embed_url=youtube_embed_url,
            last_error=edge_status.get("streaming_error"),
            streaming_started_at=streaming_started_at,
            streaming_uptime_s=streaming_uptime_s,
            updated_at=updated_at,
        ))

    # Sort: live streams first, then by vehicle number
    vehicles.sort(key=lambda v: (0 if v.is_live else 1, v.vehicle_number))

    return RacerStreamStateList(
        event_id=event_id,
        vehicles=vehicles,
        live_count=live_count,
        checked_at=datetime.utcnow(),
    )


@router.get("/events/{event_id}/cameras", response_model=list[CameraFeedResponse])
async def list_available_cameras(
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    List all available camera feeds for an event.

    FIXED: Section E - Returns cameras from two sources:
    1. VideoFeed database records (teams have configured feeds)
    2. Edge-reported cameras via heartbeat (fallback for unconfigured feeds)

    This ensures the control room camera grid shows cameras as soon as
    edge devices connect, even before teams configure VideoFeed records.

    TEAM-2: Each feed now includes embed_url (server-computed), type, and
    featured indicator from the featured-camera state machine.
    """
    feeds = []
    seen_cameras = set()  # Track (vehicle_id, camera_name) to avoid duplicates

    # TEAM-2: Collect featured camera state per vehicle for 'featured' indicator
    featured_cameras: dict[str, str] = {}  # vehicle_id -> featured camera_name

    # Source 1: Get configured video feeds from database
    result = await db.execute(
        select(VideoFeed, Vehicle, EventVehicle)
        .join(Vehicle, VideoFeed.vehicle_id == Vehicle.vehicle_id)
        .join(EventVehicle, (
            (EventVehicle.vehicle_id == Vehicle.vehicle_id) &
            (EventVehicle.event_id == VideoFeed.event_id)
        ))
        .where(
            VideoFeed.event_id == event_id,
            VideoFeed.permission_level == "public",
            EventVehicle.visible == True,
        )
    )

    for row in result.all():
        vid = row.VideoFeed.vehicle_id
        key = (vid, row.VideoFeed.camera_name)
        seen_cameras.add(key)
        url = row.VideoFeed.youtube_url
        feeds.append(CameraFeedResponse(
            vehicle_id=vid,
            vehicle_number=row.Vehicle.vehicle_number,
            team_name=row.Vehicle.team_name,
            camera_name=row.VideoFeed.camera_name,
            youtube_url=url,
            embed_url=_youtube_embed_url(url),
            is_live=bool(url),
        ))

    # Source 2: Get edge-reported cameras that don't have VideoFeed records
    # This allows cameras to appear in grid before teams configure feeds
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            EventVehicle.visible == True,
        )
    )
    event_vehicles = result.all()

    # Get all edge statuses from Redis
    edge_statuses = await redis_client.get_all_edge_statuses(event_id)

    for row in event_vehicles:
        vehicle = row.Vehicle
        edge_status = edge_statuses.get(vehicle.vehicle_id, {})

        # Get cameras reported by edge device
        edge_cameras = edge_status.get("cameras", [])
        youtube_url = edge_status.get("youtube_url", "")
        streaming_camera = edge_status.get("streaming_camera")
        streaming_status = edge_status.get("streaming_status", "idle")

        for cam_info in edge_cameras:
            cam_name = cam_info.get("name", "unknown")
            key = (vehicle.vehicle_id, cam_name)

            # Skip if we already have a VideoFeed record for this camera
            if key in seen_cameras:
                continue

            # Determine if this camera is live
            is_live = (
                streaming_status == "live" and
                streaming_camera == cam_name and
                bool(youtube_url)
            )

            cam_url = youtube_url if is_live else ""
            seen_cameras.add(key)
            feeds.append(CameraFeedResponse(
                vehicle_id=vehicle.vehicle_id,
                vehicle_number=vehicle.vehicle_number,
                team_name=vehicle.team_name,
                camera_name=cam_name,
                youtube_url=cam_url,
                embed_url=_youtube_embed_url(cam_url),
                is_live=is_live,
            ))

    # TEAM-2: Look up featured camera state per vehicle and mark feeds
    for row in event_vehicles:
        vid = row.Vehicle.vehicle_id
        featured_state = await redis_client.get_featured_camera_state(event_id, vid)
        if featured_state and featured_state.get("status") in ("success", "pending"):
            active_cam = featured_state.get("active_camera") or featured_state.get("desired_camera")
            if active_cam:
                featured_cameras[vid] = active_cam

    for feed in feeds:
        if featured_cameras.get(feed.vehicle_id) == feed.camera_name:
            feed.featured = True

    # PROD-CAM-1: Ensure all 4 canonical camera slots exist for each vehicle
    # Add placeholder feeds for any missing camera slots
    for row in event_vehicles:
        vehicle = row.Vehicle
        for cam_name in CANONICAL_CAMERAS:
            key = (vehicle.vehicle_id, cam_name)
            if key not in seen_cameras:
                # Add placeholder camera (not detected/configured yet)
                seen_cameras.add(key)
                feeds.append(CameraFeedResponse(
                    vehicle_id=vehicle.vehicle_id,
                    vehicle_number=vehicle.vehicle_number,
                    team_name=vehicle.team_name,
                    camera_name=cam_name,
                    youtube_url="",
                    embed_url="",
                    is_live=False,
                    featured=featured_cameras.get(vehicle.vehicle_id) == cam_name,
                ))

    # Sort by vehicle number, then camera name (canonical order)
    camera_order = {cam: i for i, cam in enumerate(CANONICAL_CAMERAS)}
    feeds.sort(key=lambda f: (f.vehicle_number, camera_order.get(f.camera_name, 99)))

    return feeds


@router.delete("/events/{event_id}/featured-vehicle")
async def clear_featured_vehicle(
    event_id: str,
    auth: AuthInfo = Depends(require_admin),
):
    """
    Clear the featured vehicle, returning to auto-selection mode.
    """
    state = await redis_client.get_json(f"broadcast:{event_id}") or {}
    state.pop("featured_vehicle_id", None)
    state.pop("featured_until", None)
    await redis_client.set_json(f"broadcast:{event_id}", state)

    # Broadcast clear event
    await redis_client.publish_event(
        event_id,
        "featured_vehicle",
        {"vehicle_id": None, "auto_select": True},
    )

    return {"status": "cleared", "auto_select": True}


@router.get("/events/{event_id}/truck-status", response_model=TruckStatusListResponse)
async def get_truck_status(
    event_id: str,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Get connectivity status for all trucks in an event.

    Requires admin authentication.

    Status is determined by how recently position data was received:
    - online: < 5 seconds ago
    - stale: 5-30 seconds ago
    - offline: > 30 seconds ago
    - never_connected: no data ever received
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Get all vehicles for this event with their info
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(EventVehicle.event_id == event_id)
    )
    event_vehicles = result.all()

    if not event_vehicles:
        return TruckStatusListResponse(
            event_id=event_id,
            trucks=[],
            online_count=0,
            total_count=0,
            checked_at=datetime.utcnow(),
        )

    # Get latest position for each vehicle
    now_ms = int(time.time() * 1000)
    trucks = []
    online_count = 0

    for row in event_vehicles:
        ev = row.EventVehicle
        vehicle = row.Vehicle

        # Get latest position for this vehicle
        pos_result = await db.execute(
            select(Position)
            .where(
                Position.event_id == event_id,
                Position.vehicle_id == vehicle.vehicle_id,
            )
            .order_by(Position.ts_ms.desc())
            .limit(1)
        )
        latest_pos = pos_result.scalar_one_or_none()

        # Check for video feed
        feed_result = await db.execute(
            select(VideoFeed)
            .where(
                VideoFeed.event_id == event_id,
                VideoFeed.vehicle_id == vehicle.vehicle_id,
            )
            .limit(1)
        )
        has_video = feed_result.scalar_one_or_none() is not None

        # Determine status based on last position timestamp
        if latest_pos is None:
            status = "never_connected"
            last_heartbeat_ms = None
            last_heartbeat_ago_s = None
            data_rate_hz = 0.0
        else:
            last_heartbeat_ms = latest_pos.ts_ms
            last_heartbeat_ago_s = (now_ms - latest_pos.ts_ms) / 1000.0

            if last_heartbeat_ago_s < 5:
                status = "online"
                online_count += 1
            elif last_heartbeat_ago_s < 30:
                status = "stale"
            else:
                status = "offline"

            # Estimate data rate (count positions in last 10 seconds)
            ten_sec_ago = now_ms - 10000
            rate_result = await db.execute(
                select(Position)
                .where(
                    Position.event_id == event_id,
                    Position.vehicle_id == vehicle.vehicle_id,
                    Position.ts_ms >= ten_sec_ago,
                )
            )
            recent_count = len(rate_result.all())
            data_rate_hz = recent_count / 10.0

        trucks.append(TruckStatusResponse(
            vehicle_id=vehicle.vehicle_id,
            vehicle_number=vehicle.vehicle_number,
            team_name=vehicle.team_name,
            status=status,
            last_heartbeat_ms=last_heartbeat_ms,
            last_heartbeat_ago_s=last_heartbeat_ago_s,
            data_rate_hz=data_rate_hz,
            has_video_feed=has_video,
        ))

    # Sort by status (online first, then stale, then offline, then never_connected)
    status_order = {"online": 0, "stale": 1, "offline": 2, "never_connected": 3}
    trucks.sort(key=lambda t: (status_order.get(t.status, 4), t.vehicle_number))

    return TruckStatusListResponse(
        event_id=event_id,
        trucks=trucks,
        online_count=online_count,
        total_count=len(trucks),
        checked_at=datetime.utcnow(),
    )


# ============ Edge Heartbeat & Status Endpoints ============

@router.post("/events/{event_id}/edge/heartbeat")
async def edge_heartbeat(
    event_id: str,
    data: EdgeHeartbeatRequest,
    request: Request,
    db: AsyncSession = Depends(get_session),
):
    """
    Receive heartbeat from edge device reporting streaming/device status.

    This endpoint is called periodically by edge devices (every ~10 seconds)
    to report their current state including streaming status, camera availability,
    and telemetry timestamps.

    Authenticated via X-Truck-Token header.
    """
    # Validate truck token
    truck_token = request.headers.get("X-Truck-Token")
    if not truck_token:
        raise HTTPException(status_code=401, detail="Missing X-Truck-Token header")

    # Look up token in cache or database
    token_info = await redis_client.get_truck_token_info(truck_token)
    if not token_info:
        # Check database
        result = await db.execute(
            select(Vehicle).where(Vehicle.truck_token == truck_token)
        )
        vehicle = result.scalar_one_or_none()
        if not vehicle:
            raise HTTPException(status_code=401, detail="Invalid truck token")

        # Check if vehicle is registered for this event
        result = await db.execute(
            select(EventVehicle).where(
                EventVehicle.event_id == event_id,
                EventVehicle.vehicle_id == vehicle.vehicle_id,
            )
        )
        if not result.scalar_one_or_none():
            raise HTTPException(status_code=403, detail="Vehicle not registered for this event")

        vehicle_id = vehicle.vehicle_id
        # Cache for future requests
        await redis_client.cache_truck_token(truck_token, vehicle_id, event_id)
    else:
        vehicle_id = token_info["vehicle_id"]
        if token_info.get("event_id") != event_id:
            raise HTTPException(status_code=403, detail="Token not valid for this event")

    # Build status object
    status = {
        "streaming_status": data.streaming_status,
        "streaming_camera": data.streaming_camera,
        "streaming_started_at": data.streaming_started_at,
        "streaming_error": data.streaming_error,
        "cameras": [c.model_dump() for c in data.cameras],
        "last_can_ts": data.last_can_ts,
        "last_gps_ts": data.last_gps_ts,
        "youtube_configured": data.youtube_configured,
        "youtube_url": data.youtube_url,
        "heartbeat_ts": int(time.time() * 1000),
        # EDGE-URL-1: Store edge device URL for Team Dashboard auto-discovery
        "edge_url": data.edge_url,
    }

    # Store in Redis (expires after 30s if not refreshed)
    await redis_client.set_edge_status(event_id, vehicle_id, status)

    # Update last-seen so Team Dashboard shows "online" from heartbeat alone
    # (previously only set by telemetry ingest, so edge showed "unknown" until GPS data arrived)
    heartbeat_ts = status["heartbeat_ts"]
    await redis_client.set_vehicle_last_seen(event_id, vehicle_id, heartbeat_ts)

    # Publish to SSE for real-time updates
    await redis_client.publish_edge_status(event_id, vehicle_id, status)

    log = structlog.get_logger()
    log.info("edge_heartbeat_received", vehicle_id=vehicle_id, event_id=event_id,
             streaming_status=data.streaming_status, cameras=len(data.cameras))

    return {"success": True, "vehicle_id": vehicle_id}


@router.get("/events/{event_id}/edge-status", response_model=EdgeStatusListResponse)
async def get_edge_status_list(
    event_id: str,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Get streaming/device status for all edge devices in an event.

    Combines telemetry-based connectivity with edge-reported streaming status.
    Requires admin authentication.
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Get all vehicles for this event
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(EventVehicle.event_id == event_id)
    )
    event_vehicles = result.all()

    if not event_vehicles:
        return EdgeStatusListResponse(
            event_id=event_id,
            edges=[],
            streaming_count=0,
            online_count=0,
            total_count=0,
            checked_at=datetime.utcnow(),
        )

    # Get all edge statuses from Redis
    edge_statuses = await redis_client.get_all_edge_statuses(event_id)

    now_ms = int(time.time() * 1000)
    edges = []
    streaming_count = 0
    online_count = 0

    for row in event_vehicles:
        ev = row.EventVehicle
        vehicle = row.Vehicle

        # Get telemetry-based connectivity (from latest position)
        pos_result = await db.execute(
            select(Position)
            .where(
                Position.event_id == event_id,
                Position.vehicle_id == vehicle.vehicle_id,
            )
            .order_by(Position.ts_ms.desc())
            .limit(1)
        )
        latest_pos = pos_result.scalar_one_or_none()

        if latest_pos is None:
            connection_status = "never_connected"
            last_heartbeat_ms = None
            last_heartbeat_ago_s = None
            data_rate_hz = 0.0
        else:
            last_heartbeat_ms = latest_pos.ts_ms
            last_heartbeat_ago_s = (now_ms - latest_pos.ts_ms) / 1000.0

            if last_heartbeat_ago_s < 5:
                connection_status = "online"
            elif last_heartbeat_ago_s < 30:
                connection_status = "stale"
            else:
                connection_status = "offline"

            # Estimate data rate
            ten_sec_ago = now_ms - 10000
            rate_result = await db.execute(
                select(Position)
                .where(
                    Position.event_id == event_id,
                    Position.vehicle_id == vehicle.vehicle_id,
                    Position.ts_ms >= ten_sec_ago,
                )
            )
            recent_count = len(rate_result.all())
            data_rate_hz = recent_count / 10.0

        # Get edge-reported status (from actual edge heartbeat)
        edge_status = edge_statuses.get(vehicle.vehicle_id, {})
        edge_heartbeat_ms = edge_status.get("heartbeat_ts")

        # Calculate edge_online from actual heartbeat, not just presence of status
        edge_heartbeat_age_s = None
        if edge_heartbeat_ms:
            edge_heartbeat_age_s = (now_ms - edge_heartbeat_ms) / 1000.0
            edge_online = edge_heartbeat_age_s < 30  # 30s threshold for edge connectivity
        else:
            edge_online = False

        # FIXED: Make connection_status consistent with edge_online
        # Prefer edge heartbeat for connection status when available
        if edge_heartbeat_ms is not None:
            if edge_heartbeat_age_s < 5:
                connection_status = "online"
            elif edge_heartbeat_age_s < 30:
                connection_status = "stale"
            else:
                connection_status = "offline"
            # Override last_heartbeat to use edge heartbeat (more accurate)
            last_heartbeat_ms = edge_heartbeat_ms
            last_heartbeat_ago_s = edge_heartbeat_age_s

        streaming_status = edge_status.get("streaming_status", "unknown")
        streaming_camera = edge_status.get("streaming_camera")
        streaming_started_at = edge_status.get("streaming_started_at")
        streaming_error = edge_status.get("streaming_error")

        # Calculate streaming uptime
        streaming_uptime_s = None
        if streaming_started_at and streaming_status == "live":
            streaming_uptime_s = int((now_ms - streaming_started_at) / 1000)

        # Parse camera info
        cameras_raw = edge_status.get("cameras", [])
        cameras = [
            EdgeCameraInfo(
                name=c.get("name", "unknown"),
                device=c.get("device"),
                status=c.get("status", "unknown"),
            )
            for c in cameras_raw
        ]

        if edge_online:
            online_count += 1
        if streaming_status == "live":
            streaming_count += 1

        edges.append(EdgeStatusResponse(
            vehicle_id=vehicle.vehicle_id,
            vehicle_number=vehicle.vehicle_number,
            team_name=vehicle.team_name,
            connection_status=connection_status,
            last_heartbeat_ms=last_heartbeat_ms,
            last_heartbeat_ago_s=last_heartbeat_ago_s,
            data_rate_hz=data_rate_hz,
            edge_online=edge_online,
            streaming_status=streaming_status,
            streaming_camera=streaming_camera,
            streaming_uptime_s=streaming_uptime_s,
            streaming_error=streaming_error,
            cameras=cameras,
            last_can_ts=edge_status.get("last_can_ts"),
            last_gps_ts=edge_status.get("last_gps_ts"),
            youtube_configured=edge_status.get("youtube_configured", False),
            youtube_url=edge_status.get("youtube_url"),
            edge_heartbeat_ms=edge_heartbeat_ms,
        ))

    # Sort by streaming status (live first), then by connection status
    status_order = {"live": 0, "starting": 1, "error": 2, "idle": 3, "unknown": 4}
    conn_order = {"online": 0, "stale": 1, "offline": 2, "never_connected": 3}
    edges.sort(key=lambda e: (
        status_order.get(e.streaming_status, 5),
        conn_order.get(e.connection_status, 4),
        e.vehicle_number,
    ))

    return EdgeStatusListResponse(
        event_id=event_id,
        edges=edges,
        streaming_count=streaming_count,
        online_count=online_count,
        total_count=len(edges),
        checked_at=datetime.utcnow(),
    )


@router.get("/events/{event_id}/edge/{vehicle_id}", response_model=EdgeStatusResponse)
async def get_single_edge_status(
    event_id: str,
    vehicle_id: str,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Get detailed status for a single edge device.
    Used for the drill-down view in the control room.
    """
    # Validate vehicle exists in event
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

    vehicle = row.Vehicle

    # Get telemetry-based connectivity
    now_ms = int(time.time() * 1000)
    pos_result = await db.execute(
        select(Position)
        .where(
            Position.event_id == event_id,
            Position.vehicle_id == vehicle_id,
        )
        .order_by(Position.ts_ms.desc())
        .limit(1)
    )
    latest_pos = pos_result.scalar_one_or_none()

    if latest_pos is None:
        connection_status = "never_connected"
        last_heartbeat_ms = None
        last_heartbeat_ago_s = None
        data_rate_hz = 0.0
    else:
        last_heartbeat_ms = latest_pos.ts_ms
        last_heartbeat_ago_s = (now_ms - latest_pos.ts_ms) / 1000.0

        if last_heartbeat_ago_s < 5:
            connection_status = "online"
        elif last_heartbeat_ago_s < 30:
            connection_status = "stale"
        else:
            connection_status = "offline"

        ten_sec_ago = now_ms - 10000
        rate_result = await db.execute(
            select(Position)
            .where(
                Position.event_id == event_id,
                Position.vehicle_id == vehicle_id,
                Position.ts_ms >= ten_sec_ago,
            )
        )
        recent_count = len(rate_result.all())
        data_rate_hz = recent_count / 10.0

    # Get edge-reported status (from actual edge heartbeat)
    edge_status = await redis_client.get_edge_status(event_id, vehicle_id) or {}
    edge_heartbeat_ms = edge_status.get("heartbeat_ts")

    # Calculate edge_online from actual heartbeat, not just presence of status
    edge_heartbeat_age_s = None
    if edge_heartbeat_ms:
        edge_heartbeat_age_s = (now_ms - edge_heartbeat_ms) / 1000.0
        edge_online = edge_heartbeat_age_s < 30  # 30s threshold for edge connectivity
    else:
        edge_online = False

    # FIXED: Make connection_status consistent with edge_online
    # Prefer edge heartbeat for connection status when available
    if edge_heartbeat_ms is not None:
        if edge_heartbeat_age_s < 5:
            connection_status = "online"
        elif edge_heartbeat_age_s < 30:
            connection_status = "stale"
        else:
            connection_status = "offline"
        # Override last_heartbeat to use edge heartbeat (more accurate)
        last_heartbeat_ms = edge_heartbeat_ms
        last_heartbeat_ago_s = edge_heartbeat_age_s

    streaming_status = edge_status.get("streaming_status", "unknown")
    streaming_camera = edge_status.get("streaming_camera")
    streaming_started_at = edge_status.get("streaming_started_at")
    streaming_error = edge_status.get("streaming_error")

    streaming_uptime_s = None
    if streaming_started_at and streaming_status == "live":
        streaming_uptime_s = int((now_ms - streaming_started_at) / 1000)

    cameras_raw = edge_status.get("cameras", [])
    cameras = [
        EdgeCameraInfo(
            name=c.get("name", "unknown"),
            device=c.get("device"),
            status=c.get("status", "unknown"),
        )
        for c in cameras_raw
    ]

    return EdgeStatusResponse(
        vehicle_id=vehicle_id,
        vehicle_number=vehicle.vehicle_number,
        team_name=vehicle.team_name,
        connection_status=connection_status,
        last_heartbeat_ms=last_heartbeat_ms,
        last_heartbeat_ago_s=last_heartbeat_ago_s,
        data_rate_hz=data_rate_hz,
        edge_online=edge_online,
        streaming_status=streaming_status,
        streaming_camera=streaming_camera,
        streaming_uptime_s=streaming_uptime_s,
        streaming_error=streaming_error,
        cameras=cameras,
        last_can_ts=edge_status.get("last_can_ts"),
        last_gps_ts=edge_status.get("last_gps_ts"),
        youtube_configured=edge_status.get("youtube_configured", False),
        youtube_url=edge_status.get("youtube_url"),
        edge_heartbeat_ms=edge_heartbeat_ms,
    )


# ============ Edge-Compatible Production Status Endpoint ============
# This endpoint matches the path that edge devices expect: /api/v1/events/{event_id}/production/status

class ProductionStatusResponse(BaseModel):
    """Production status for edge devices."""
    event_id: str
    status: str  # 'idle', 'live', 'paused'
    current_camera: str  # Featured camera name
    featured_vehicle_id: Optional[str]
    stream_health: str  # 'healthy', 'degraded', 'offline'
    viewer_count: int
    updated_at: datetime


@events_router.get("/api/v1/events/{event_id}/production/status", response_model=ProductionStatusResponse)
async def get_production_status(
    event_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get production status for an event.

    This endpoint is polled by edge devices to display current production state.
    Returns featured camera, stream status, and viewer count.
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Get broadcast state from Redis
    state = await redis_client.get_json(f"broadcast:{event_id}")

    # Determine production status
    if state:
        status = "live" if state.get("featured_vehicle_id") else "idle"
        current_camera = state.get("featured_camera", "chase")
        featured_vehicle_id = state.get("featured_vehicle_id")
    else:
        status = "idle"
        current_camera = "chase"
        featured_vehicle_id = None

    # Viewer count - not currently tracked, placeholder for future
    viewer_count = 0

    # Determine stream health based on recent data
    # For now, assume healthy if we have any featured content
    stream_health = "healthy" if status == "live" else "idle"

    return ProductionStatusResponse(
        event_id=event_id,
        status=status,
        current_camera=current_camera,
        featured_vehicle_id=featured_vehicle_id,
        stream_health=stream_health,
        viewer_count=viewer_count,
        updated_at=datetime.utcnow(),
    )


# ============ Edge Command Endpoints ============
# Bidirectional cloud ↔ edge communication for camera control

VALID_COMMANDS = {"set_active_camera", "start_stream", "stop_stream", "list_cameras", "get_status", "set_stream_profile"}

# CAM-CONTRACT-1B: Canonical 4-camera slots with backward compatibility
# Canonical names: main, cockpit, chase, suspension
VALID_CAMERAS = {"main", "cockpit", "chase", "suspension"}

# CAM-CONTRACT-1B: Backward compatibility aliases for legacy edge devices
CAMERA_SLOT_ALIASES = {
    "pov": "cockpit",
    "roof": "chase",
    "front": "suspension",
    "rear": "suspension",  # CAM-CONTRACT-1B: rear is now suspension
    "cam0": "main",
    "camera": "main",
    "default": "main",
}

# All valid camera names (canonical + aliases) for validation
ALL_VALID_CAMERAS = VALID_CAMERAS | set(CAMERA_SLOT_ALIASES.keys())

def normalize_camera_slot(slot_id: str) -> str:
    """CAM-CONTRACT-1B: Normalize camera slot to canonical name."""
    if slot_id in VALID_CAMERAS:
        return slot_id
    return CAMERA_SLOT_ALIASES.get(slot_id, slot_id)

# PROD-CAM-1 + CAM-CONTRACT-1B: Canonical camera slots - always show 4 cameras per vehicle
# Order matters for grid display (main first as primary broadcast camera)
CANONICAL_CAMERAS = ["main", "cockpit", "chase", "suspension"]
VALID_STREAM_PROFILES = {"1080p30", "720p30", "480p30", "360p30"}


@router.post("/events/{event_id}/edge/{vehicle_id}/command", response_model=EdgeCommandResult)
async def send_edge_command(
    event_id: str,
    vehicle_id: str,
    cmd: EdgeCommandRequest,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Send a command to an edge device.

    Commands:
    - set_active_camera: Switch to a different camera. Params: {"camera": "main|cockpit|chase|suspension"}
      CAM-CONTRACT-1B: Also accepts legacy names (pov, roof, front, rear) which are auto-normalized.
    - start_stream: Start streaming with current or specified camera. Params: {"camera": "main"} (optional)
    - stop_stream: Stop streaming
    - list_cameras: Request list of available cameras
    - get_status: Request full status update

    The command is published to the edge via SSE. Edge responds via POST to /command-response.
    This endpoint returns immediately with pending status; poll /commands/{command_id} for result.
    """
    # Validate command
    if cmd.command not in VALID_COMMANDS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid command. Valid commands: {', '.join(VALID_COMMANDS)}"
        )

    # Validate camera param if setting camera
    # CAM-CONTRACT-0: Accept both canonical and legacy camera names
    if cmd.command == "set_active_camera":
        camera = cmd.params.get("camera") if cmd.params else None
        if not camera or camera not in ALL_VALID_CAMERAS:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid camera. Valid cameras: {', '.join(sorted(VALID_CAMERAS))}"
            )
        # Normalize to canonical name for downstream processing
        cmd.params["camera"] = normalize_camera_slot(camera)

    # STREAM-3: Validate profile param if setting stream profile
    if cmd.command == "set_stream_profile":
        profile = cmd.params.get("profile") if cmd.params else None
        if not profile or profile not in VALID_STREAM_PROFILES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid profile. Valid profiles: {', '.join(sorted(VALID_STREAM_PROFILES))}"
            )

    # Validate vehicle exists in event
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

    # Check if edge is online (has recent heartbeat)
    edge_status = await redis_client.get_edge_status(event_id, vehicle_id)
    if not edge_status:
        raise HTTPException(
            status_code=503,
            detail="Edge device is offline. Cannot send command."
        )

    # Generate command ID
    command_id = f"cmd_{uuid.uuid4().hex[:12]}"
    now = datetime.utcnow()

    # Build command payload
    command_payload = {
        "command_id": command_id,
        "command": cmd.command,
        "params": cmd.params or {},
        "sent_at": now.isoformat(),
        "sender": auth.admin_id if hasattr(auth, "admin_id") else "admin",
    }

    # Store command in Redis with 60s TTL (for response correlation)
    await redis_client.set_edge_command(event_id, vehicle_id, command_id, {
        **command_payload,
        "status": "pending",
        "vehicle_id": vehicle_id,
    })

    # Publish command to edge via SSE channel
    await redis_client.publish_edge_command(event_id, vehicle_id, command_payload)

    return EdgeCommandResult(
        command_id=command_id,
        vehicle_id=vehicle_id,
        command=cmd.command,
        params=cmd.params,
        status="pending",
        message="Command sent to edge device",
        data=None,
        sent_at=now,
        responded_at=None,
    )


@router.post("/events/{event_id}/edge/command-response")
async def receive_edge_command_response(
    event_id: str,
    response: EdgeCommandResponse,
    request: Request,
    db: AsyncSession = Depends(get_session),
):
    """
    Receive command response from edge device.

    Called by edge device after executing a command.
    Updates the command status and publishes to SSE for UI update.
    Authenticated via X-Truck-Token header.
    """
    # Validate truck token
    truck_token = request.headers.get("X-Truck-Token")
    if not truck_token:
        raise HTTPException(status_code=401, detail="Missing X-Truck-Token header")

    token_info = await redis_client.get_truck_token_info(truck_token)
    if not token_info:
        # Check database
        result = await db.execute(
            select(Vehicle).where(Vehicle.truck_token == truck_token)
        )
        vehicle = result.scalar_one_or_none()
        if not vehicle:
            raise HTTPException(status_code=401, detail="Invalid truck token")
        vehicle_id = vehicle.vehicle_id
    else:
        vehicle_id = token_info["vehicle_id"]

    # Get the pending command
    command = await redis_client.get_edge_command(event_id, vehicle_id, response.command_id)
    if not command:
        raise HTTPException(status_code=404, detail="Command not found or expired")

    # Update command status
    now = datetime.utcnow()
    command["status"] = response.status
    command["message"] = response.message
    command["data"] = response.data
    command["responded_at"] = now.isoformat()

    # Update in Redis
    await redis_client.set_edge_command(event_id, vehicle_id, response.command_id, command)

    # If set_active_camera succeeded, persist the active camera state
    if command["command"] == "set_active_camera" and response.status == "success":
        camera = command.get("params", {}).get("camera")
        if camera:
            await redis_client.set_active_camera(event_id, vehicle_id, camera)

    # Update featured camera state on set_active_camera ACK
    if command["command"] == "set_active_camera":
        featured_state = await redis_client.get_featured_camera_state(event_id, vehicle_id)
        if featured_state and featured_state.get("request_id") == response.command_id:
            camera = command.get("params", {}).get("camera")
            if response.status == "success":
                featured_state["active_camera"] = camera
                featured_state["status"] = "success"
                featured_state["last_error"] = None
                featured_state["updated_at"] = datetime.utcnow().isoformat()
                logger.info(
                    "Featured camera switch confirmed: event=%s vehicle=%s camera=%s",
                    event_id, vehicle_id, camera,
                )
            else:
                featured_state["status"] = "failed"
                featured_state["last_error"] = response.message or "Edge returned error"
                featured_state["updated_at"] = datetime.utcnow().isoformat()
                logger.warning(
                    "Featured camera switch failed: event=%s vehicle=%s error=%s",
                    event_id, vehicle_id, response.message,
                )
            await redis_client.set_featured_camera_state(event_id, vehicle_id, featured_state)

    # STREAM-3: Update stream profile state on set_stream_profile ACK
    if command["command"] == "set_stream_profile":
        profile_state = await redis_client.get_stream_profile_state(event_id, vehicle_id)
        if profile_state and profile_state.get("request_id") == response.command_id:
            profile = command.get("params", {}).get("profile")
            if response.status == "success":
                profile_state["active_profile"] = profile
                profile_state["status"] = "success"
                profile_state["last_error"] = None
                profile_state["updated_at"] = datetime.utcnow().isoformat()
                logger.info(
                    "Stream profile switch confirmed: event=%s vehicle=%s profile=%s",
                    event_id, vehicle_id, profile,
                )
            else:
                profile_state["status"] = "failed"
                profile_state["last_error"] = response.message or "Edge returned error"
                profile_state["updated_at"] = datetime.utcnow().isoformat()
                logger.warning(
                    "Stream profile switch failed: event=%s vehicle=%s error=%s",
                    event_id, vehicle_id, response.message,
                )
            await redis_client.set_stream_profile_state(event_id, vehicle_id, profile_state)

    # If start_stream succeeded, update streaming state
    if command["command"] == "start_stream" and response.status == "success":
        camera = response.data.get("camera") if response.data else None
        if camera:
            await redis_client.set_active_camera(event_id, vehicle_id, camera)

    # Update stream control state machine for stream commands
    if command["command"] in ("start_stream", "stop_stream"):
        await stream_control.handle_edge_response(
            event_id=event_id,
            vehicle_id=vehicle_id,
            command_id=response.command_id,
            status=response.status,
            message=response.message,
            data=response.data,
        )

    # Publish response to SSE for UI update
    await redis_client.publish_command_response(event_id, vehicle_id, {
        "command_id": response.command_id,
        "status": response.status,
        "message": response.message,
        "data": response.data,
    })

    return {"success": True, "command_id": response.command_id}


@router.get("/events/{event_id}/edge/{vehicle_id}/command/{command_id}", response_model=EdgeCommandResult)
async def get_command_status(
    event_id: str,
    vehicle_id: str,
    command_id: str,
    auth: AuthInfo = Depends(require_admin),
):
    """
    Get the status of a command sent to an edge device.

    Poll this endpoint to check if a command has been acknowledged.
    """
    command = await redis_client.get_edge_command(event_id, vehicle_id, command_id)
    if not command:
        raise HTTPException(status_code=404, detail="Command not found or expired")

    return EdgeCommandResult(
        command_id=command_id,
        vehicle_id=vehicle_id,
        command=command["command"],
        params=command.get("params"),
        status=command["status"],
        message=command.get("message"),
        data=command.get("data"),
        sent_at=datetime.fromisoformat(command["sent_at"]),
        responded_at=datetime.fromisoformat(command["responded_at"]) if command.get("responded_at") else None,
    )


@router.get("/events/{event_id}/edge/{vehicle_id}/active-camera", response_model=ActiveCameraState)
async def get_active_camera(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get the current active camera for a vehicle.

    This is the authoritative source for which camera should be streaming.
    Returns persisted state that survives service restarts.
    """
    # Validate vehicle exists
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            EventVehicle.vehicle_id == vehicle_id,
        )
    )
    if not result.first():
        raise HTTPException(status_code=404, detail="Vehicle not found in event")

    # Get active camera from Redis
    state = await redis_client.get_active_camera(event_id, vehicle_id)

    if not state:
        # Default state
        return ActiveCameraState(
            vehicle_id=vehicle_id,
            event_id=event_id,
            camera="chase",  # Default camera
            streaming=False,
            updated_at=datetime.utcnow(),
            updated_by="default",
        )

    return ActiveCameraState(
        vehicle_id=vehicle_id,
        event_id=event_id,
        camera=state.get("camera", "chase"),
        streaming=state.get("streaming", False),
        updated_at=datetime.fromisoformat(state["updated_at"]) if state.get("updated_at") else datetime.utcnow(),
        updated_by=state.get("updated_by", "unknown"),
    )


@router.put("/events/{event_id}/edge/{vehicle_id}/active-camera")
async def set_active_camera_state(
    event_id: str,
    vehicle_id: str,
    camera: str,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Set the active camera for a vehicle (cloud-authoritative).

    This updates the persisted state. To actually switch the camera on the edge,
    use the /command endpoint with set_active_camera command.
    """
    if camera not in VALID_CAMERAS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid camera. Valid cameras: {', '.join(VALID_CAMERAS)}"
        )

    # Validate vehicle exists
    result = await db.execute(
        select(EventVehicle).where(
            EventVehicle.event_id == event_id,
            EventVehicle.vehicle_id == vehicle_id,
        )
    )
    if not result.first():
        raise HTTPException(status_code=404, detail="Vehicle not found in event")

    await redis_client.set_active_camera(
        event_id,
        vehicle_id,
        camera,
        updated_by=auth.admin_id if hasattr(auth, "admin_id") else "admin",
    )

    return {"success": True, "camera": camera}


# ============ PROD-1: Featured Camera Endpoint ============

FEATURED_CAMERA_TIMEOUT_S = 15  # Seconds before marking switch as timed out


@router.post(
    "/events/{event_id}/vehicles/{vehicle_id}/featured-camera",
    response_model=FeaturedCameraResponse,
    status_code=202,
)
async def set_featured_camera(
    event_id: str,
    vehicle_id: str,
    data: FeaturedCameraRequest,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Request a camera switch for a vehicle.

    Sets the desired camera and sends a command to the edge device.
    Returns 202 immediately; poll the GET endpoint or watch SSE for ACK.

    Idempotency: if a pending request exists for the same camera, returns
    the existing request_id instead of creating a new command.
    """

    camera_id = data.camera_id
    now = datetime.utcnow()
    now_ms = int(time.time() * 1000)

    # Validate camera_id
    if camera_id not in VALID_CAMERAS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid camera_id. Must be one of: {', '.join(VALID_CAMERAS)}"
        )

    # Validate vehicle exists in event
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

    # Idempotency: check for existing pending request with same camera
    existing = await redis_client.get_featured_camera_state(event_id, vehicle_id)
    if (
        existing
        and existing.get("status") == "pending"
        and existing.get("desired_camera") == camera_id
    ):
        # Same camera already pending — return existing request_id
        logger.info(
            "featured_camera_idempotent",
            event_id=event_id,
            vehicle_id=vehicle_id,
            camera_id=camera_id,
            request_id=existing["request_id"],
        )
        return FeaturedCameraResponse(
            request_id=existing["request_id"],
            vehicle_id=vehicle_id,
            desired_camera=camera_id,
            status="pending",
        )

    # Generate request_id
    request_id = f"fc_{uuid.uuid4().hex[:12]}"

    # Persist desired state as pending
    state = {
        "desired_camera": camera_id,
        "active_camera": existing.get("active_camera") if existing else None,
        "request_id": request_id,
        "status": "pending",
        "last_error": None,
        "updated_at": now.isoformat(),
        "timeout_at": (now_ms + FEATURED_CAMERA_TIMEOUT_S * 1000),
    }
    await redis_client.set_featured_camera_state(event_id, vehicle_id, state)

    logger.info(
        "featured_camera_requested",
        event_id=event_id,
        vehicle_id=vehicle_id,
        camera_id=camera_id,
        request_id=request_id,
    )

    # Build edge command payload
    command_payload = {
        "command_id": request_id,
        "command": "set_active_camera",
        "params": {"camera": camera_id},
        "sent_at": now.isoformat(),
        "sender": auth.admin_id if hasattr(auth, "admin_id") else "admin",
    }

    # Store command for correlation (60s TTL)
    await redis_client.set_edge_command(event_id, vehicle_id, request_id, {
        **command_payload,
        "status": "pending",
        "vehicle_id": vehicle_id,
    })

    # Publish command to edge via SSE
    await redis_client.publish_edge_command(event_id, vehicle_id, command_payload)

    logger.info(
        "featured_camera_command_sent",
        event_id=event_id,
        vehicle_id=vehicle_id,
        camera_id=camera_id,
        request_id=request_id,
    )

    # Also update broadcast state so fans see the intended camera immediately
    broadcast = {
        "featured_vehicle_id": vehicle_id,
        "featured_camera": camera_id,
        "updated_at": now.isoformat(),
    }
    await redis_client.set_json(f"broadcast:{event_id}", broadcast, ex=3600)

    return FeaturedCameraResponse(
        request_id=request_id,
        vehicle_id=vehicle_id,
        desired_camera=camera_id,
        status="pending",
    )


@router.get(
    "/events/{event_id}/vehicles/{vehicle_id}/featured-camera",
    response_model=FeaturedCameraState,
)
async def get_featured_camera(
    event_id: str,
    vehicle_id: str,
):
    """
    Get the current featured camera state for a vehicle.

    Shows desired vs active camera, pending status, and any errors.
    Automatically marks timed-out requests.
    """
    state = await redis_client.get_featured_camera_state(event_id, vehicle_id)

    now_ms = int(time.time() * 1000)

    if not state:
        return FeaturedCameraState(
            vehicle_id=vehicle_id,
            event_id=event_id,
            desired_camera=None,
            active_camera=None,
            request_id=None,
            status="idle",
            last_error=None,
            updated_at=datetime.utcnow(),
        )

    # Auto-timeout: if pending and past deadline, mark as timeout
    if state.get("status") == "pending" and state.get("timeout_at"):
        if now_ms > state["timeout_at"]:
            state["status"] = "timeout"
            rid = state.get("request_id", "unknown")
            state["last_error"] = f"Edge did not respond within {FEATURED_CAMERA_TIMEOUT_S}s (request_id={rid})"
            state["updated_at"] = datetime.utcnow().isoformat()
            await redis_client.set_featured_camera_state(event_id, vehicle_id, state)
            logger.warning(
                "featured_camera_timeout",
                event_id=event_id,
                vehicle_id=vehicle_id,
                request_id=rid,
                desired_camera=state.get("desired_camera"),
                timeout_s=FEATURED_CAMERA_TIMEOUT_S,
            )

    return FeaturedCameraState(
        vehicle_id=vehicle_id,
        event_id=event_id,
        desired_camera=state.get("desired_camera"),
        active_camera=state.get("active_camera"),
        request_id=state.get("request_id"),
        status=state.get("status", "idle"),
        last_error=state.get("last_error"),
        updated_at=datetime.fromisoformat(state["updated_at"]) if state.get("updated_at") else datetime.utcnow(),
    )


# ============ STREAM-3: Per-Vehicle Stream Profile Control ============

STREAM_PROFILE_TIMEOUT_S = 15  # Seconds before marking switch as timed out

STREAM_PROFILE_LABELS = {
    "1080p30": "1080p @ 4500k",
    "720p30": "720p @ 2500k",
    "480p30": "480p @ 1200k",
    "360p30": "360p @ 800k",
}


class StreamProfileRequest(BaseModel):
    """Request to set stream quality profile for a vehicle."""
    profile: str  # 1080p30, 720p30, 480p30, 360p30


class StreamProfileResponse(BaseModel):
    """Response after requesting a stream profile change."""
    request_id: str
    vehicle_id: str
    desired_profile: str
    status: str  # pending, success, failed, timeout


class StreamProfileState(BaseModel):
    """Full stream profile state for a vehicle."""
    vehicle_id: str
    event_id: str
    desired_profile: Optional[str]
    active_profile: Optional[str]
    request_id: Optional[str]
    status: str  # pending, success, failed, timeout, idle
    last_error: Optional[str]
    updated_at: datetime


@router.post(
    "/events/{event_id}/vehicles/{vehicle_id}/stream-profile",
    response_model=StreamProfileResponse,
    status_code=202,
)
async def set_stream_profile(
    event_id: str,
    vehicle_id: str,
    data: StreamProfileRequest,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Request a stream quality profile change for a vehicle.

    Sets the desired profile and sends a command to the edge device.
    Returns 202 immediately; poll the GET endpoint or watch SSE for ACK.

    Idempotency: if a pending request exists for the same profile, returns
    the existing request_id instead of creating a new command.
    """
    profile = data.profile
    now = datetime.utcnow()
    now_ms = int(time.time() * 1000)

    # Validate profile
    if profile not in VALID_STREAM_PROFILES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid profile. Must be one of: {', '.join(sorted(VALID_STREAM_PROFILES))}"
        )

    # Validate vehicle exists in event
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

    # Idempotency: check for existing pending request with same profile
    existing = await redis_client.get_stream_profile_state(event_id, vehicle_id)
    if (
        existing
        and existing.get("status") == "pending"
        and existing.get("desired_profile") == profile
    ):
        logger.info(
            "stream_profile_idempotent",
            event_id=event_id,
            vehicle_id=vehicle_id,
            profile=profile,
            request_id=existing["request_id"],
        )
        return StreamProfileResponse(
            request_id=existing["request_id"],
            vehicle_id=vehicle_id,
            desired_profile=profile,
            status="pending",
        )

    # Generate request_id
    request_id = f"sp_{uuid.uuid4().hex[:12]}"

    # Persist desired state as pending
    state = {
        "desired_profile": profile,
        "active_profile": existing.get("active_profile") if existing else None,
        "request_id": request_id,
        "status": "pending",
        "last_error": None,
        "updated_at": now.isoformat(),
        "timeout_at": (now_ms + STREAM_PROFILE_TIMEOUT_S * 1000),
    }
    await redis_client.set_stream_profile_state(event_id, vehicle_id, state)

    logger.info(
        "stream_profile_requested",
        event_id=event_id,
        vehicle_id=vehicle_id,
        profile=profile,
        request_id=request_id,
    )

    # Build edge command payload
    command_payload = {
        "command_id": request_id,
        "command": "set_stream_profile",
        "params": {"profile": profile, "source": "production"},
        "sent_at": now.isoformat(),
        "sender": auth.admin_id if hasattr(auth, "admin_id") else "admin",
    }

    # Store command for correlation (60s TTL)
    await redis_client.set_edge_command(event_id, vehicle_id, request_id, {
        **command_payload,
        "status": "pending",
        "vehicle_id": vehicle_id,
    })

    # Publish command to edge via SSE
    await redis_client.publish_edge_command(event_id, vehicle_id, command_payload)

    logger.info(
        "stream_profile_command_sent",
        event_id=event_id,
        vehicle_id=vehicle_id,
        profile=profile,
        request_id=request_id,
    )

    return StreamProfileResponse(
        request_id=request_id,
        vehicle_id=vehicle_id,
        desired_profile=profile,
        status="pending",
    )


@router.get(
    "/events/{event_id}/vehicles/{vehicle_id}/stream-profile",
    response_model=StreamProfileState,
)
async def get_stream_profile(
    event_id: str,
    vehicle_id: str,
):
    """
    Get the current stream profile state for a vehicle.

    Shows desired vs active profile, pending status, and any errors.
    Automatically marks timed-out requests.
    """
    state = await redis_client.get_stream_profile_state(event_id, vehicle_id)

    now_ms = int(time.time() * 1000)

    if not state:
        return StreamProfileState(
            vehicle_id=vehicle_id,
            event_id=event_id,
            desired_profile=None,
            active_profile=None,
            request_id=None,
            status="idle",
            last_error=None,
            updated_at=datetime.utcnow(),
        )

    # Auto-timeout: if pending and past deadline, mark as timeout
    if state.get("status") == "pending" and state.get("timeout_at"):
        if now_ms > state["timeout_at"]:
            state["status"] = "timeout"
            state["last_error"] = "Edge did not respond within timeout"
            state["updated_at"] = datetime.utcnow().isoformat()
            await redis_client.set_stream_profile_state(event_id, vehicle_id, state)

    return StreamProfileState(
        vehicle_id=vehicle_id,
        event_id=event_id,
        desired_profile=state.get("desired_profile"),
        active_profile=state.get("active_profile"),
        request_id=state.get("request_id"),
        status=state.get("status", "idle"),
        last_error=state.get("last_error"),
        updated_at=datetime.fromisoformat(state["updated_at"]) if state.get("updated_at") else datetime.utcnow(),
    )


# ============ PROMPT 5: Telemetry Visibility for Production Team ============

class ProductionTelemetryResponse(BaseModel):
    """Filtered telemetry for production team view."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    telemetry: dict  # Filtered based on allow_production policy
    policy: dict  # Current sharing policy summary
    last_update_ms: Optional[int]


class FanTelemetryResponse(BaseModel):
    """Filtered telemetry for fan view."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    telemetry: dict  # Filtered based on allow_fans policy
    last_update_ms: Optional[int]


class TelemetryPolicySummary(BaseModel):
    """Summary of vehicle telemetry policy for admin view."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    allow_production: list[str]
    allow_fans: list[str]
    updated_at: Optional[str]


class EventTelemetryPoliciesResponse(BaseModel):
    """All telemetry policies for an event."""
    event_id: str
    policies: list[TelemetryPolicySummary]
    checked_at: datetime


@router.get("/events/{event_id}/vehicles/{vehicle_id}/telemetry", response_model=ProductionTelemetryResponse)
async def get_production_telemetry(
    event_id: str,
    vehicle_id: str,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Get filtered telemetry for production team.

    Server-side filtering based on the vehicle's telemetry sharing policy.
    Only returns fields in the `allow_production` list.

    Requires admin authentication.
    """
    # Validate vehicle exists in event
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

    vehicle = row.Vehicle

    # Get latest position/telemetry from Redis
    raw_telemetry = await redis_client.get_latest_position(event_id, vehicle_id) or {}

    # Get policy
    policy = await redis_client.get_telemetry_policy(event_id, vehicle_id)

    # Filter telemetry server-side
    filtered = await redis_client.filter_telemetry_by_policy(
        telemetry=raw_telemetry,
        event_id=event_id,
        vehicle_id=vehicle_id,
        viewer_type="production",
    )

    return ProductionTelemetryResponse(
        vehicle_id=vehicle_id,
        vehicle_number=vehicle.vehicle_number,
        team_name=vehicle.team_name,
        telemetry=filtered,
        policy={
            "allow_production": policy.get("allow_production", []),
            "allow_fans": policy.get("allow_fans", []),
        },
        last_update_ms=raw_telemetry.get("ts_ms"),
    )


@router.get("/events/{event_id}/vehicles/{vehicle_id}/telemetry/fan", response_model=FanTelemetryResponse)
async def get_fan_telemetry(
    event_id: str,
    vehicle_id: str,
    db: AsyncSession = Depends(get_session),
):
    """
    Get filtered telemetry for fans.

    PUBLIC ENDPOINT - No authentication required.

    Server-side filtering based on the vehicle's telemetry sharing policy.
    Only returns fields in the `allow_fans` list.

    If no policy is set, returns nothing (safe default).
    """
    # Validate vehicle exists in event and is visible
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(
            EventVehicle.event_id == event_id,
            EventVehicle.vehicle_id == vehicle_id,
            EventVehicle.visible == True,
        )
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Vehicle not found or not visible")

    vehicle = row.Vehicle

    # Get latest position/telemetry from Redis
    raw_telemetry = await redis_client.get_latest_position(event_id, vehicle_id) or {}

    # Filter telemetry server-side - NEVER trust the client
    filtered = await redis_client.filter_telemetry_by_policy(
        telemetry=raw_telemetry,
        event_id=event_id,
        vehicle_id=vehicle_id,
        viewer_type="fan",
    )

    return FanTelemetryResponse(
        vehicle_id=vehicle_id,
        vehicle_number=vehicle.vehicle_number,
        team_name=vehicle.team_name,
        telemetry=filtered,
        last_update_ms=raw_telemetry.get("ts_ms"),
    )


@router.get("/events/{event_id}/telemetry-policies", response_model=EventTelemetryPoliciesResponse)
async def get_event_telemetry_policies(
    event_id: str,
    auth: AuthInfo = Depends(require_admin),
    db: AsyncSession = Depends(get_session),
):
    """
    Get all telemetry policies for an event.

    Admin endpoint to see what each team is sharing.
    Requires admin authentication.
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Get all vehicles in event
    result = await db.execute(
        select(EventVehicle, Vehicle)
        .join(Vehicle, EventVehicle.vehicle_id == Vehicle.vehicle_id)
        .where(EventVehicle.event_id == event_id)
    )
    event_vehicles = result.all()

    policies = []
    for row in event_vehicles:
        vehicle = row.Vehicle
        policy = await redis_client.get_telemetry_policy(event_id, vehicle.vehicle_id)
        policies.append(TelemetryPolicySummary(
            vehicle_id=vehicle.vehicle_id,
            vehicle_number=vehicle.vehicle_number,
            team_name=vehicle.team_name,
            allow_production=policy.get("allow_production", []),
            allow_fans=policy.get("allow_fans", []),
            updated_at=policy.get("updated_at"),
        ))

    # Sort by vehicle number
    policies.sort(key=lambda p: p.vehicle_number)

    return EventTelemetryPoliciesResponse(
        event_id=event_id,
        policies=policies,
        checked_at=datetime.utcnow(),
    )


# ============ PIT-NOTES-1: Pit Notes from Edge to Control Room ============

class PitNoteCreateRequest(BaseModel):
    """Request to create a pit note from edge device."""
    vehicle_id: str
    note: str
    timestamp_ms: Optional[int] = None  # If not provided, use server time


class PitNoteResponse(BaseModel):
    """Single pit note response."""
    note_id: str
    event_id: str
    vehicle_id: str
    vehicle_number: Optional[str]
    team_name: Optional[str]
    message: str
    timestamp_ms: int
    created_at: datetime


class PitNotesListResponse(BaseModel):
    """List of pit notes for an event."""
    event_id: str
    notes: list[PitNoteResponse]
    total: int


@events_router.post("/api/v1/events/{event_id}/pit-notes", response_model=PitNoteResponse)
async def create_pit_note(
    event_id: str,
    data: PitNoteCreateRequest,
    request: Request,
    db: AsyncSession = Depends(get_session),
):
    """
    Create a pit note from edge device.

    PIT-NOTES-1: Edge devices send notes to cloud for race control visibility.
    Authenticated via X-Truck-Token header.
    """
    # Validate truck token
    truck_token = request.headers.get("X-Truck-Token")
    if not truck_token:
        raise HTTPException(status_code=401, detail="Missing X-Truck-Token header")

    # Look up token in cache or database
    token_info = await redis_client.get_truck_token_info(truck_token)
    if not token_info:
        # Check database
        result = await db.execute(
            select(Vehicle).where(Vehicle.truck_token == truck_token)
        )
        vehicle = result.scalar_one_or_none()
        if not vehicle:
            raise HTTPException(status_code=401, detail="Invalid truck token")

        # Check if vehicle is registered for this event
        result = await db.execute(
            select(EventVehicle).where(
                EventVehicle.event_id == event_id,
                EventVehicle.vehicle_id == vehicle.vehicle_id,
            )
        )
        if not result.scalar_one_or_none():
            raise HTTPException(status_code=403, detail="Vehicle not registered for this event")

        vehicle_id = vehicle.vehicle_id
        vehicle_number = vehicle.vehicle_number
        team_name = vehicle.team_name
        # Cache for future requests
        await redis_client.cache_truck_token(truck_token, vehicle_id, event_id)
    else:
        vehicle_id = token_info["vehicle_id"]
        if token_info.get("event_id") != event_id:
            raise HTTPException(status_code=403, detail="Token not valid for this event")
        # Fetch vehicle details for denormalized fields
        result = await db.execute(
            select(Vehicle).where(Vehicle.vehicle_id == vehicle_id)
        )
        vehicle = result.scalar_one_or_none()
        vehicle_number = vehicle.vehicle_number if vehicle else None
        team_name = vehicle.team_name if vehicle else None

    # Validate note content
    message = data.note.strip()
    if not message:
        raise HTTPException(status_code=400, detail="Note message cannot be empty")
    if len(message) > 1000:
        raise HTTPException(status_code=400, detail="Note message too long (max 1000 chars)")

    # Create timestamp
    timestamp_ms = data.timestamp_ms or int(time.time() * 1000)

    # Create pit note
    pit_note = PitNote(
        event_id=event_id,
        vehicle_id=vehicle_id,
        vehicle_number=vehicle_number,
        team_name=team_name,
        message=message,
        timestamp_ms=timestamp_ms,
    )
    db.add(pit_note)
    await db.commit()
    await db.refresh(pit_note)

    logger.info("pit_note_created", note_id=pit_note.note_id, event_id=event_id,
                vehicle_id=vehicle_id, vehicle_number=vehicle_number)

    return PitNoteResponse(
        note_id=pit_note.note_id,
        event_id=pit_note.event_id,
        vehicle_id=pit_note.vehicle_id,
        vehicle_number=pit_note.vehicle_number,
        team_name=pit_note.team_name,
        message=pit_note.message,
        timestamp_ms=pit_note.timestamp_ms,
        created_at=pit_note.created_at,
    )


@events_router.get("/api/v1/events/{event_id}/pit-notes", response_model=PitNotesListResponse)
async def get_pit_notes(
    event_id: str,
    limit: int = 50,
    db: AsyncSession = Depends(get_session),
):
    """
    Get pit notes for an event.

    PIT-NOTES-1: Control room fetches notes for display.
    Public endpoint (no auth required) - notes are not sensitive.
    """
    # Validate event exists
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Fetch notes, newest first
    limit = min(limit, 100)  # Cap at 100
    result = await db.execute(
        select(PitNote)
        .where(PitNote.event_id == event_id)
        .order_by(PitNote.timestamp_ms.desc())
        .limit(limit)
    )
    notes = result.scalars().all()

    # Get total count
    from sqlalchemy import func
    count_result = await db.execute(
        select(func.count()).select_from(PitNote).where(PitNote.event_id == event_id)
    )
    total = count_result.scalar() or 0

    return PitNotesListResponse(
        event_id=event_id,
        notes=[
            PitNoteResponse(
                note_id=n.note_id,
                event_id=n.event_id,
                vehicle_id=n.vehicle_id,
                vehicle_number=n.vehicle_number,
                team_name=n.team_name,
                message=n.message,
                timestamp_ms=n.timestamp_ms,
                created_at=n.created_at,
            )
            for n in notes
        ],
        total=total,
    )
