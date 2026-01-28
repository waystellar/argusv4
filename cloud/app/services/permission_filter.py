"""
Field-level permission filtering for telemetry data.

Filters telemetry fields based on vehicle permission settings and viewer access level.
"""
from typing import Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import TelemetryPermission, VideoFeed
from app import redis_client

# Default permission levels for fields if not explicitly set
# PR-2 SCHEMA: Canonical field names aligned across Edge/Cloud/Web
DEFAULT_PERMISSIONS = {
    # GPS is always public (core fan experience)
    "lat": "public",
    "lon": "public",
    "speed_mps": "public",
    "heading_deg": "public",
    # Engine telemetry defaults (canonical names)
    "rpm": "public",
    "gear": "public",
    "throttle_pct": "premium",
    "coolant_temp_c": "premium",  # Canonical: Celsius
    "oil_pressure_psi": "private",  # Canonical: PSI
    "fuel_pressure_psi": "private",  # Canonical: PSI
    "speed_mph": "public",  # CAN-reported speed
    # NOTE: Suspension fields removed - not currently in use
    # Biometrics (private by default)
    "heart_rate": "private",
    "heart_rate_zone": "private",
}

# Permission levels ordered by access (higher index = more restricted)
PERMISSION_ORDER = ["public", "premium", "private", "hidden"]


def get_permission_rank(level: str) -> int:
    """Get numeric rank for permission level (0=public, 3=hidden)."""
    try:
        return PERMISSION_ORDER.index(level)
    except ValueError:
        return 3  # Default to hidden if unknown


def can_access(field_permission: str, viewer_access: str) -> bool:
    """
    Check if viewer can access a field.

    Args:
        field_permission: Permission level set for the field
        viewer_access: Viewer's access level ("public", "premium", or "team")

    Returns:
        True if viewer can see this field
    """
    if viewer_access == "team":
        # Team members can see everything except hidden
        return field_permission != "hidden"

    if field_permission == "hidden":
        return False

    # For public/premium viewers, check permission rank
    field_rank = get_permission_rank(field_permission)
    viewer_rank = get_permission_rank(viewer_access)

    return field_rank <= viewer_rank


async def get_vehicle_permissions(
    vehicle_id: str,
    event_id: str,
    db: AsyncSession,
) -> dict[str, str]:
    """
    Get permission levels for all telemetry fields for a vehicle.

    Returns dict of field_name -> permission_level, using defaults for unset fields.
    """
    # Check cache first
    cache_key = f"permissions:{event_id}:{vehicle_id}"
    cached = await redis_client.get_json(cache_key)
    if cached:
        return cached

    # Query database
    result = await db.execute(
        select(TelemetryPermission).where(
            TelemetryPermission.vehicle_id == vehicle_id,
            TelemetryPermission.event_id == event_id,
        )
    )
    db_permissions = {p.field_name: p.permission_level for p in result.scalars().all()}

    # Merge with defaults
    permissions = {**DEFAULT_PERMISSIONS, **db_permissions}

    # Cache for 60 seconds
    await redis_client.set_json(cache_key, permissions, ex=60)

    return permissions


async def filter_telemetry_data(
    data: dict,
    vehicle_id: str,
    event_id: str,
    viewer_access: str,
    db: AsyncSession,
) -> dict:
    """
    Filter telemetry data based on viewer access level.

    Args:
        data: Raw telemetry data dict
        vehicle_id: Vehicle ID
        event_id: Event ID
        viewer_access: "public", "premium", or "team"
        db: Database session

    Returns:
        Filtered dict with only accessible fields
    """
    permissions = await get_vehicle_permissions(vehicle_id, event_id, db)

    filtered = {}
    for field, value in data.items():
        # Always include metadata fields
        if field in ("vehicle_id", "ts_ms", "event_id", "type"):
            filtered[field] = value
            continue

        # Check field permission
        field_permission = permissions.get(field, "hidden")
        if can_access(field_permission, viewer_access):
            filtered[field] = value

    return filtered


async def filter_position_for_viewer(
    position: dict,
    event_id: str,
    viewer_access: str = "public",
    db: AsyncSession = None,
) -> dict:
    """
    Filter a position update for a specific viewer access level.

    PROMPT 5: Now integrates with TelemetrySharingPolicy.
    - For fans (public/premium): Uses allow_fans from policy
    - For team: Uses allow_production from policy
    - Policy filtering is applied - server-side enforcement, never trust client

    Safe defaults if no policy:
    - Fans: Nothing (empty allow_fans)
    - Production/Team: GPS only
    """
    vehicle_id = position.get("vehicle_id")
    if not vehicle_id:
        # No filtering possible without vehicle_id
        return position

    # PROMPT 5: Get telemetry sharing policy
    policy = await redis_client.get_telemetry_policy(event_id, vehicle_id)

    # Determine which policy list to use based on viewer type
    if viewer_access == "team":
        policy_allowed = set(policy.get("allow_production", []))
    else:
        # public and premium viewers use allow_fans
        policy_allowed = set(policy.get("allow_fans", []))

    # Always include metadata fields
    filtered = {
        "vehicle_id": vehicle_id,
        "ts_ms": position.get("ts_ms"),
    }

    # Copy vehicle_number and team_name if present (metadata, always visible)
    if "vehicle_number" in position:
        filtered["vehicle_number"] = position["vehicle_number"]
    if "team_name" in position:
        filtered["team_name"] = position["team_name"]

    # All telemetry fields that could be in a position update
    all_fields = [
        "lat", "lon", "speed_mps", "heading_deg", "altitude_m", "hdop", "satellites",
        "rpm", "gear", "throttle_pct", "coolant_temp_c",
        "oil_pressure_psi", "fuel_pressure_psi", "speed_mph",
        "heart_rate", "heart_rate_zone"
    ]

    # PROMPT 5: Only include fields that are in the policy's allowed list
    # This is server-side enforcement - never trust the client
    for field in all_fields:
        if field in position and field in policy_allowed:
            filtered[field] = position[field]

    return filtered


# FIXED: Made function async and added await (Issue #6 from audit)
# Previously the coroutine was created but never executed
async def invalidate_permission_cache(event_id: str, vehicle_id: str) -> None:
    """
    Invalidate cached permissions for a vehicle.
    Call this when permissions are updated.
    """
    cache_key = f"permissions:{event_id}:{vehicle_id}"
    await redis_client.delete_key(cache_key)
