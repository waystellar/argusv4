"""
Team dashboard API routes - permission management and team authentication.
"""
from datetime import datetime, timedelta
from typing import Optional
import secrets

from fastapi import APIRouter, Depends, HTTPException, Header
from pydantic import BaseModel, EmailStr
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
import jwt

from app.database import get_session
from app.models import (
    Vehicle, Event, EventVehicle, TelemetryPermission, VideoFeed, generate_id
)
from app.config import get_settings
from app import redis_client

settings = get_settings()
router = APIRouter(prefix="/api/v1/team", tags=["team"])


# ============ Schemas ============

class TeamLoginRequest(BaseModel):
    """Request team access via vehicle number + token."""
    vehicle_number: str
    team_token: str  # Could be truck_token or separate team token


class TeamLoginResponse(BaseModel):
    """Team session token."""
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    vehicle_id: str
    vehicle_number: str
    team_name: str


class PermissionUpdate(BaseModel):
    """Update permission for a field."""
    field_name: str
    permission_level: str  # public, premium, private, hidden


class PermissionBulkUpdate(BaseModel):
    """Bulk update permissions."""
    permissions: list[PermissionUpdate]


class VideoFeedUpdate(BaseModel):
    """Update video feed URL and permission."""
    camera_name: str
    youtube_url: str
    permission_level: str = "public"


class PermissionResponse(BaseModel):
    """Current permission state."""
    field_name: str
    permission_level: str
    updated_at: Optional[datetime]


class TeamDashboardResponse(BaseModel):
    """Full team dashboard state."""
    vehicle_id: str
    vehicle_number: str
    team_name: str
    event_id: Optional[str]
    telemetry_permissions: list[PermissionResponse]
    video_feeds: list[dict]
    visible: bool


# ============ Auth Helpers ============

def create_team_token(vehicle_id: str, vehicle_number: str, team_name: str) -> str:
    """Create JWT for team dashboard access."""
    payload = {
        "sub": vehicle_id,
        "vehicle_number": vehicle_number,
        "team_name": team_name,
        "type": "team",
        "exp": datetime.utcnow() + timedelta(hours=24),
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, settings.secret_key, algorithm="HS256")


def decode_team_token(token: str) -> dict:
    """Decode and validate team JWT."""
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        if payload.get("type") != "team":
            raise HTTPException(status_code=401, detail="Invalid token type")
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


async def get_current_team(
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_session),
) -> dict:
    """Dependency to get current team from Authorization header."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")

    token = authorization[7:]
    payload = decode_team_token(token)

    # Verify vehicle still exists
    result = await db.execute(
        select(Vehicle).where(Vehicle.vehicle_id == payload["sub"])
    )
    vehicle = result.scalar_one_or_none()
    if not vehicle:
        raise HTTPException(status_code=401, detail="Vehicle not found")

    return {
        "vehicle_id": payload["sub"],
        "vehicle_number": payload["vehicle_number"],
        "team_name": payload["team_name"],
    }


# ============ Endpoints ============

@router.post("/login", response_model=TeamLoginResponse)
async def team_login(
    data: TeamLoginRequest,
    db: AsyncSession = Depends(get_session),
):
    """
    Login to team dashboard using vehicle number and team token.
    For MVP, team_token is the truck_token.
    """
    # Find vehicle by number and token
    result = await db.execute(
        select(Vehicle).where(
            Vehicle.vehicle_number == data.vehicle_number,
            Vehicle.truck_token == data.team_token,
        )
    )
    vehicle = result.scalar_one_or_none()

    if not vehicle:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # Create session token
    access_token = create_team_token(
        vehicle.vehicle_id,
        vehicle.vehicle_number,
        vehicle.team_name,
    )

    return TeamLoginResponse(
        access_token=access_token,
        expires_in=86400,  # 24 hours
        vehicle_id=vehicle.vehicle_id,
        vehicle_number=vehicle.vehicle_number,
        team_name=vehicle.team_name,
    )


@router.get("/dashboard", response_model=TeamDashboardResponse)
async def get_dashboard(
    team: dict = Depends(get_current_team),
    db: AsyncSession = Depends(get_session),
):
    """Get full team dashboard state including all permissions."""
    vehicle_id = team["vehicle_id"]

    # Get vehicle with current event
    result = await db.execute(
        select(Vehicle).where(Vehicle.vehicle_id == vehicle_id)
    )
    vehicle = result.scalar_one()

    # Find active event registration
    # FIXED: Section D - Include scheduled events so teams can configure before race starts
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle_id,
            Event.status.in_(["scheduled", "in_progress"]),
        )
        .order_by(Event.created_at.desc())
        .limit(1)
    )
    row = result.first()
    event_id = row.Event.event_id if row else None
    visible = row.EventVehicle.visible if row else True

    # Get telemetry permissions
    if event_id:
        result = await db.execute(
            select(TelemetryPermission).where(
                TelemetryPermission.vehicle_id == vehicle_id,
                TelemetryPermission.event_id == event_id,
            )
        )
        perms = result.scalars().all()
    else:
        perms = []

    # Build default permissions if none exist
    # FIXED: Field names must match permission_filter.py DEFAULT_PERMISSIONS
    default_fields = [
        ("lat", "public"),
        ("lon", "public"),
        ("speed_mps", "public"),
        ("heading_deg", "public"),
        ("rpm", "public"),
        ("gear", "public"),
        ("coolant_temp", "premium"),
        ("oil_pressure", "private"),
        ("fuel_pressure", "private"),
        ("throttle_pct", "premium"),
        ("heart_rate", "private"),
        ("heart_rate_zone", "private"),
        # NOTE: Suspension fields removed - not currently in use
    ]

    perm_dict = {p.field_name: p for p in perms}
    telemetry_permissions = []
    for field, default_level in default_fields:
        if field in perm_dict:
            p = perm_dict[field]
            telemetry_permissions.append(PermissionResponse(
                field_name=p.field_name,
                permission_level=p.permission_level,
                updated_at=p.updated_at,
            ))
        else:
            telemetry_permissions.append(PermissionResponse(
                field_name=field,
                permission_level=default_level,
                updated_at=None,
            ))

    # Get video feeds
    if event_id:
        result = await db.execute(
            select(VideoFeed).where(
                VideoFeed.vehicle_id == vehicle_id,
                VideoFeed.event_id == event_id,
            )
        )
        feeds = result.scalars().all()
    else:
        feeds = []

    video_feeds = [
        {
            "camera_name": f.camera_name,
            "youtube_url": f.youtube_url,
            "permission_level": f.permission_level,
        }
        for f in feeds
    ]

    # Add default camera slots if not configured
    default_cameras = ["chase", "pov", "roof", "front"]
    existing_cameras = {f["camera_name"] for f in video_feeds}
    for cam in default_cameras:
        if cam not in existing_cameras:
            video_feeds.append({
                "camera_name": cam,
                "youtube_url": "",
                "permission_level": "public",
            })

    return TeamDashboardResponse(
        vehicle_id=vehicle_id,
        vehicle_number=vehicle.vehicle_number,
        team_name=vehicle.team_name,
        event_id=event_id,
        telemetry_permissions=telemetry_permissions,
        video_feeds=video_feeds,
        visible=visible,
    )


@router.get("/diagnostics")
async def get_diagnostics(
    team: dict = Depends(get_current_team),
    db: AsyncSession = Depends(get_session),
):
    """
    Get real-time edge device diagnostics for team dashboard.
    Uses Redis last-seen tracking from telemetry ingest to determine edge status.
    """
    import time

    vehicle_id = team["vehicle_id"]

    # Find active event for this vehicle
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle_id,
            Event.status.in_(["scheduled", "in_progress"]),
        )
        .order_by(Event.created_at.desc())
        .limit(1)
    )
    row = result.first()
    event_id = row.Event.event_id if row else None
    visible = row.EventVehicle.visible if row else True

    now_ms = int(time.time() * 1000)

    # Get last-seen timestamp from Redis (set by telemetry ingest)
    edge_last_seen_ms = None
    if event_id:
        edge_last_seen_ms = await redis_client.get_vehicle_last_seen(event_id, vehicle_id)

    # Determine edge status from last-seen age
    if edge_last_seen_ms is not None:
        age_s = (now_ms - edge_last_seen_ms) / 1000
        if age_s <= 30:
            edge_status = "online"
        elif age_s <= 60:
            edge_status = "stale"
        else:
            edge_status = "offline"
    else:
        edge_status = "unknown"

    # Get detailed edge status from Redis (set by edge heartbeat, 30s TTL)
    edge_detail = None
    if event_id:
        edge_detail = await redis_client.get_edge_status(event_id, vehicle_id)

    # Get latest cached position for last_position_ms
    last_position_ms = None
    if event_id:
        cached_pos = await redis_client.get_latest_position(event_id, vehicle_id)
        if cached_pos and "ts_ms" in cached_pos:
            last_position_ms = cached_pos["ts_ms"]

    # Build video status from DB
    video_status = "none"
    if event_id:
        from app.models import VideoFeed as VideoFeedModel
        vf_result = await db.execute(
            select(VideoFeedModel).where(
                VideoFeedModel.vehicle_id == vehicle_id,
                VideoFeedModel.event_id == event_id,
            )
        )
        feeds = vf_result.scalars().all()
        has_urls = any(f.youtube_url for f in feeds)
        if has_urls:
            video_status = "configured"

    # Merge edge detail fields if available
    gps_status = "unknown"
    can_status = "unknown"
    queue_depth = None
    data_rate_hz = None
    edge_ip = None
    edge_version = None

    if edge_detail:
        gps_status = edge_detail.get("gps_status", "unknown")
        can_status = edge_detail.get("can_status", "unknown")
        queue_depth = edge_detail.get("queue_depth")
        data_rate_hz = edge_detail.get("data_rate_hz")
        edge_ip = edge_detail.get("edge_ip")
        edge_version = edge_detail.get("edge_version")
        if edge_detail.get("video_streaming"):
            video_status = "streaming"

    # Infer GPS locked if we have recent position data
    if gps_status == "unknown" and last_position_ms is not None:
        pos_age_s = (now_ms - last_position_ms) / 1000
        if pos_age_s <= 30:
            gps_status = "locked"
        elif pos_age_s <= 120:
            gps_status = "searching"

    return {
        "vehicle_id": vehicle_id,
        "event_id": event_id,
        "visible": visible,
        "edge_last_seen_ms": edge_last_seen_ms,
        "edge_status": edge_status,
        "is_online": edge_status == "online",
        "gps_status": gps_status,
        "can_status": can_status,
        "video_status": video_status,
        "queue_depth": queue_depth,
        "last_position_ms": last_position_ms,
        "data_rate_hz": data_rate_hz,
        "edge_ip": edge_ip,
        "edge_version": edge_version,
    }


@router.put("/permissions")
async def update_permissions(
    data: PermissionBulkUpdate,
    team: dict = Depends(get_current_team),
    db: AsyncSession = Depends(get_session),
):
    """Update telemetry permissions for team's vehicle."""
    vehicle_id = team["vehicle_id"]

    # Get active event
    # FIXED: Section D - Include scheduled events so teams can configure before race starts
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle_id,
            Event.status.in_(["scheduled", "in_progress"]),
        )
        .limit(1)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=400, detail="No active event for vehicle")

    event_id = row.Event.event_id

    # Validate permission levels
    valid_levels = {"public", "premium", "private", "hidden"}
    for perm in data.permissions:
        if perm.permission_level not in valid_levels:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid permission level: {perm.permission_level}"
            )

    # Update or create permissions
    for perm in data.permissions:
        result = await db.execute(
            select(TelemetryPermission).where(
                TelemetryPermission.vehicle_id == vehicle_id,
                TelemetryPermission.event_id == event_id,
                TelemetryPermission.field_name == perm.field_name,
            )
        )
        existing = result.scalar_one_or_none()

        if existing:
            existing.permission_level = perm.permission_level
            existing.updated_at = datetime.utcnow()
        else:
            new_perm = TelemetryPermission(
                vehicle_id=vehicle_id,
                event_id=event_id,
                field_name=perm.field_name,
                permission_level=perm.permission_level,
            )
            db.add(new_perm)

    await db.commit()

    # Invalidate permission cache
    cache_key = f"permissions:{event_id}:{vehicle_id}"
    await redis_client.delete_key(cache_key)

    # Broadcast permission update to SSE clients
    await redis_client.publish_event(
        event_id,
        "permission_update",
        {
            "vehicle_id": vehicle_id,
            "permissions": [p.model_dump() for p in data.permissions],
        },
    )

    return {"status": "updated", "count": len(data.permissions)}


@router.put("/visibility")
async def update_visibility(
    visible: bool,
    team: dict = Depends(get_current_team),
    db: AsyncSession = Depends(get_session),
):
    """Toggle vehicle visibility on fan dashboard."""
    vehicle_id = team["vehicle_id"]

    # Get active event registration
    # FIXED: Section D - Include scheduled events so teams can configure before race starts
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle_id,
            Event.status.in_(["scheduled", "in_progress"]),
        )
        .limit(1)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=400, detail="No active event for vehicle")

    event_vehicle = row.EventVehicle
    event_id = row.Event.event_id

    # Update visibility
    event_vehicle.visible = visible
    await db.commit()

    # Update cache and broadcast
    await redis_client.set_vehicle_visibility(event_id, vehicle_id, visible)
    await redis_client.publish_event(
        event_id,
        "permission",
        {"vehicle_id": vehicle_id, "visible": visible},
    )

    return {"vehicle_id": vehicle_id, "visible": visible}


@router.put("/video")
async def update_video_feed(
    data: VideoFeedUpdate,
    team: dict = Depends(get_current_team),
    db: AsyncSession = Depends(get_session),
):
    """Update video feed URL and permission."""
    vehicle_id = team["vehicle_id"]

    # Get active event
    # FIXED: Section D - Include scheduled events so teams can configure before race starts
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle_id,
            Event.status.in_(["scheduled", "in_progress"]),
        )
        .limit(1)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=400, detail="No active event for vehicle")

    event_id = row.Event.event_id

    # Validate camera name
    valid_cameras = {"chase", "pov", "roof", "front", "side", "rear"}
    if data.camera_name not in valid_cameras:
        raise HTTPException(status_code=400, detail=f"Invalid camera: {data.camera_name}")

    # Update or create video feed
    result = await db.execute(
        select(VideoFeed).where(
            VideoFeed.vehicle_id == vehicle_id,
            VideoFeed.event_id == event_id,
            VideoFeed.camera_name == data.camera_name,
        )
    )
    feed = result.scalar_one_or_none()

    if feed:
        feed.youtube_url = data.youtube_url
        feed.permission_level = data.permission_level
    else:
        feed = VideoFeed(
            vehicle_id=vehicle_id,
            event_id=event_id,
            camera_name=data.camera_name,
            youtube_url=data.youtube_url,
            permission_level=data.permission_level,
        )
        db.add(feed)

    await db.commit()

    # Broadcast video feed update
    await redis_client.publish_event(
        event_id,
        "video_update",
        {
            "vehicle_id": vehicle_id,
            "camera_name": data.camera_name,
            "youtube_url": data.youtube_url if data.permission_level == "public" else None,
            "permission_level": data.permission_level,
        },
    )

    return {"status": "updated", "camera": data.camera_name}


@router.get("/preview")
async def preview_fan_view(
    team: dict = Depends(get_current_team),
    db: AsyncSession = Depends(get_session),
):
    """
    Preview what fans see based on current permissions.
    Returns filtered telemetry and video feeds.
    """
    vehicle_id = team["vehicle_id"]

    # Get active event
    # FIXED: Section D - Include scheduled events so teams can preview before race starts
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle_id,
            Event.status.in_(["scheduled", "in_progress"]),
        )
        .limit(1)
    )
    row = result.first()
    if not row:
        return {"visible": False, "telemetry": {}, "video_feeds": []}

    event_id = row.Event.event_id
    visible = row.EventVehicle.visible

    if not visible:
        return {"visible": False, "telemetry": {}, "video_feeds": []}

    # Get public telemetry permissions
    result = await db.execute(
        select(TelemetryPermission).where(
            TelemetryPermission.vehicle_id == vehicle_id,
            TelemetryPermission.event_id == event_id,
            TelemetryPermission.permission_level == "public",
        )
    )
    public_perms = result.scalars().all()

    # Get latest position from Redis
    position = await redis_client.get_latest_position(event_id, vehicle_id)

    # Filter to public fields
    public_fields = {p.field_name for p in public_perms}
    # Add default public fields (using correct field names from permission_filter.py)
    public_fields.update({"lat", "lon", "speed_mps", "heading_deg"})

    telemetry = {}
    if position:
        if "lat" in public_fields:
            telemetry["lat"] = position.get("lat")
        if "lon" in public_fields:
            telemetry["lon"] = position.get("lon")
        if "speed_mps" in public_fields:
            telemetry["speed_mps"] = position.get("speed_mps")
        if "heading_deg" in public_fields:
            telemetry["heading_deg"] = position.get("heading_deg")

    # Get public video feeds
    result = await db.execute(
        select(VideoFeed).where(
            VideoFeed.vehicle_id == vehicle_id,
            VideoFeed.event_id == event_id,
            VideoFeed.permission_level == "public",
        )
    )
    feeds = result.scalars().all()

    return {
        "visible": True,
        "telemetry": telemetry,
        "video_feeds": [
            {"camera_name": f.camera_name, "youtube_url": f.youtube_url}
            for f in feeds
        ],
    }


# ============ PROMPT 5: Telemetry Sharing Policy ============

class TelemetrySharingPolicyUpdate(BaseModel):
    """Update telemetry sharing policy."""
    allow_production: list[str]  # Fields production team can see
    allow_fans: list[str]  # Fields fans can see (must be subset of allow_production)


class TelemetrySharingPolicyResponse(BaseModel):
    """Current telemetry sharing policy."""
    vehicle_id: str
    event_id: str
    allow_production: list[str]
    allow_fans: list[str]
    available_fields: list[str]  # All available fields for reference
    field_groups: dict[str, list[str]]  # Field groups for UI convenience
    updated_at: Optional[str]


@router.get("/sharing-policy", response_model=TelemetrySharingPolicyResponse)
async def get_sharing_policy(
    team: dict = Depends(get_current_team),
    db: AsyncSession = Depends(get_session),
):
    """
    Get current telemetry sharing policy.

    Returns what fields are shared with production team and fans.
    If no policy is set, returns safe defaults (GPS for production, nothing for fans).
    """
    vehicle_id = team["vehicle_id"]

    # Get active event
    # FIXED: Section D - Include scheduled events so teams can configure before race starts
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle_id,
            Event.status.in_(["scheduled", "in_progress"]),
        )
        .limit(1)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=400, detail="No active event for vehicle")

    event_id = row.Event.event_id

    # Get policy from Redis
    policy = await redis_client.get_telemetry_policy(event_id, vehicle_id)

    return TelemetrySharingPolicyResponse(
        vehicle_id=vehicle_id,
        event_id=event_id,
        allow_production=policy.get("allow_production", []),
        allow_fans=policy.get("allow_fans", []),
        available_fields=redis_client.ALL_TELEMETRY_FIELDS,
        field_groups=redis_client.TELEMETRY_FIELD_GROUPS,
        updated_at=policy.get("updated_at"),
    )


@router.put("/sharing-policy")
async def update_sharing_policy(
    data: TelemetrySharingPolicyUpdate,
    team: dict = Depends(get_current_team),
    db: AsyncSession = Depends(get_session),
):
    """
    Update telemetry sharing policy.

    Controls what telemetry data is visible to:
    - Production team (control room): sees `allow_production` fields
    - Fans (public viewers): sees `allow_fans` fields

    Constraint: allow_fans must be a subset of allow_production.
    If a field is in allow_fans but not allow_production, it will be removed from allow_fans.

    Safe defaults if not configured:
    - Production: GPS only (lat, lon, speed_mps, heading_deg)
    - Fans: Nothing (must be explicitly enabled)
    """
    vehicle_id = team["vehicle_id"]

    # Get active event
    # FIXED: Section D - Include scheduled events so teams can configure before race starts
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle_id,
            Event.status.in_(["scheduled", "in_progress"]),
        )
        .limit(1)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=400, detail="No active event for vehicle")

    event_id = row.Event.event_id

    # Validate fields
    valid_fields = set(redis_client.ALL_TELEMETRY_FIELDS)
    invalid_production = set(data.allow_production) - valid_fields
    invalid_fans = set(data.allow_fans) - valid_fields

    if invalid_production:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid production fields: {invalid_production}"
        )
    if invalid_fans:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid fan fields: {invalid_fans}"
        )

    # Store policy (function handles subset constraint)
    policy = await redis_client.set_telemetry_policy(
        event_id=event_id,
        vehicle_id=vehicle_id,
        allow_production=data.allow_production,
        allow_fans=data.allow_fans,
    )

    return {
        "status": "updated",
        "allow_production": policy["allow_production"],
        "allow_fans": policy["allow_fans"],
    }


@router.delete("/sharing-policy")
async def reset_sharing_policy(
    team: dict = Depends(get_current_team),
    db: AsyncSession = Depends(get_session),
):
    """
    Reset telemetry sharing policy to safe defaults.

    Defaults:
    - Production: GPS only (lat, lon, speed_mps, heading_deg)
    - Fans: Nothing
    """
    vehicle_id = team["vehicle_id"]

    # Get active event
    # FIXED: Section D - Include scheduled events so teams can configure before race starts
    result = await db.execute(
        select(EventVehicle, Event)
        .join(Event, EventVehicle.event_id == Event.event_id)
        .where(
            EventVehicle.vehicle_id == vehicle_id,
            Event.status.in_(["scheduled", "in_progress"]),
        )
        .limit(1)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=400, detail="No active event for vehicle")

    event_id = row.Event.event_id

    # Delete policy
    await redis_client.delete_telemetry_policy(event_id, vehicle_id)

    return {
        "status": "reset",
        "defaults": redis_client.DEFAULT_TELEMETRY_POLICY,
    }
