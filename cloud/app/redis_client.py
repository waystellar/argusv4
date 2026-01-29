"""
Redis client for pub/sub and caching.
"""
import json
from typing import Optional, AsyncIterator
from contextlib import asynccontextmanager

import redis.asyncio as redis
from redis.asyncio.client import PubSub

from app.config import get_settings

settings = get_settings()

# Global Redis connection pool
_redis_pool: Optional[redis.Redis] = None


async def get_redis() -> redis.Redis:
    """Get or create Redis connection."""
    global _redis_pool
    if _redis_pool is None:
        _redis_pool = redis.from_url(
            settings.redis_url,
            encoding="utf-8",
            decode_responses=True,
        )
    return _redis_pool


async def close_redis() -> None:
    """Close Redis connection on shutdown."""
    global _redis_pool
    if _redis_pool is not None:
        await _redis_pool.close()
        _redis_pool = None


# ============ Latest Positions Cache ============

async def set_latest_position(event_id: str, vehicle_id: str, position_data: dict) -> None:
    """Store latest position for a vehicle."""
    r = await get_redis()
    key = f"pos:latest:{event_id}"
    await r.hset(key, vehicle_id, json.dumps(position_data))
    await r.expire(key, 3600)  # Expire after 1 hour of no updates


async def get_latest_positions(event_id: str) -> dict[str, dict]:
    """Get all latest positions for an event."""
    r = await get_redis()
    key = f"pos:latest:{event_id}"
    data = await r.hgetall(key)
    return {vid: json.loads(pos) for vid, pos in data.items()}


async def get_latest_position(event_id: str, vehicle_id: str) -> Optional[dict]:
    """Get latest position for a single vehicle."""
    r = await get_redis()
    key = f"pos:latest:{event_id}"
    data = await r.hget(key, vehicle_id)
    return json.loads(data) if data else None


# ============ Pub/Sub for SSE ============

async def publish_event(event_id: str, event_type: str, data: dict) -> None:
    """Publish event to Redis channel for SSE fan-out."""
    r = await get_redis()
    channel = f"stream:{event_id}"
    message = json.dumps({"type": event_type, "data": data})
    await r.publish(channel, message)


@asynccontextmanager
async def subscribe_to_event(event_id: str) -> AsyncIterator[PubSub]:
    """Subscribe to event channel for SSE."""
    r = await get_redis()
    pubsub = r.pubsub()
    channel = f"stream:{event_id}"
    await pubsub.subscribe(channel)
    try:
        yield pubsub
    finally:
        await pubsub.unsubscribe(channel)
        await pubsub.close()


# ============ Truck Token Cache ============

async def cache_truck_token(token: str, vehicle_id: str, event_id: str) -> None:
    """Cache truck token for fast lookup."""
    r = await get_redis()
    key = f"token:{token}"
    await r.hset(key, mapping={"vehicle_id": vehicle_id, "event_id": event_id})
    await r.expire(key, 86400)  # 24 hour TTL


async def get_truck_token_info(token: str) -> Optional[dict]:
    """Get vehicle/event info from cached token."""
    r = await get_redis()
    key = f"token:{token}"
    data = await r.hgetall(key)
    return data if data else None


# ============ Vehicle Visibility Cache ============

async def set_vehicle_visibility(event_id: str, vehicle_id: str, visible: bool) -> None:
    """Cache vehicle visibility status."""
    r = await get_redis()
    key = f"visible:{event_id}"
    await r.hset(key, vehicle_id, "1" if visible else "0")


async def get_vehicle_visibility(event_id: str, vehicle_id: str) -> bool:
    """Check if vehicle is visible (default True)."""
    r = await get_redis()
    key = f"visible:{event_id}"
    value = await r.hget(key, vehicle_id)
    return value != "0"  # Default to visible if not set


async def get_visible_vehicles(event_id: str) -> set[str]:
    """Get set of visible vehicle IDs (for filtering)."""
    r = await get_redis()
    key = f"visible:{event_id}"
    data = await r.hgetall(key)
    # Return all except those explicitly set to "0"
    hidden = {vid for vid, val in data.items() if val == "0"}
    return hidden


# ============ Generic JSON Cache ============

async def get_json(key: str) -> Optional[dict]:
    """Get JSON value from cache."""
    r = await get_redis()
    data = await r.get(key)
    return json.loads(data) if data else None


async def set_json(key: str, value: dict, ex: int = 60) -> None:
    """Set JSON value in cache with expiry."""
    r = await get_redis()
    await r.set(key, json.dumps(value), ex=ex)


async def delete_key(key: str) -> None:
    """Delete a key from cache."""
    r = await get_redis()
    await r.delete(key)


# ============ PR-2 UX: Vehicle Last-Seen Tracking ============

async def set_vehicle_last_seen(event_id: str, vehicle_id: str, ts_ms: int) -> None:
    """
    Track when vehicle last sent data.
    Used for staleness detection on frontend.
    """
    r = await get_redis()
    key = f"lastseen:{event_id}"
    await r.hset(key, vehicle_id, str(ts_ms))
    await r.expire(key, 3600)  # 1 hour TTL


async def get_vehicle_last_seen(event_id: str, vehicle_id: str) -> Optional[int]:
    """Get last-seen timestamp for a single vehicle."""
    r = await get_redis()
    key = f"lastseen:{event_id}"
    data = await r.hget(key, vehicle_id)
    return int(data) if data else None


async def get_all_vehicles_last_seen(event_id: str) -> dict[str, int]:
    """Get last-seen timestamps for all vehicles in an event."""
    r = await get_redis()
    key = f"lastseen:{event_id}"
    data = await r.hgetall(key)
    return {vid: int(ts) for vid, ts in data.items()}


async def get_stale_vehicles(event_id: str, threshold_ms: int = 30000) -> list[str]:
    """
    Get vehicles that haven't sent data recently.

    Args:
        event_id: Event to check
        threshold_ms: Consider stale if no data for this many ms (default 30s)

    Returns:
        List of vehicle IDs that are stale
    """
    import time
    r = await get_redis()
    key = f"lastseen:{event_id}"
    data = await r.hgetall(key)
    now_ms = int(time.time() * 1000)
    return [vid for vid, ts in data.items() if now_ms - int(ts) > threshold_ms]


# ============ Edge Status Reporting ============

async def set_edge_status(event_id: str, vehicle_id: str, status: dict) -> None:
    """
    Store edge device status report.
    Status includes streaming state, camera devices, timestamps, etc.
    Expires after 30 seconds if not refreshed.
    """
    r = await get_redis()
    key = f"edge:{event_id}:{vehicle_id}"
    await r.set(key, json.dumps(status), ex=30)  # 30 second TTL
    # Also track all edges for this event
    await r.sadd(f"edges:{event_id}", vehicle_id)
    await r.expire(f"edges:{event_id}", 3600)


async def get_edge_status(event_id: str, vehicle_id: str) -> Optional[dict]:
    """Get edge status for a single vehicle."""
    r = await get_redis()
    key = f"edge:{event_id}:{vehicle_id}"
    data = await r.get(key)
    return json.loads(data) if data else None


async def get_all_edge_statuses(event_id: str) -> dict[str, dict]:
    """Get edge status for all vehicles in an event."""
    r = await get_redis()
    # Get all vehicle IDs that have reported
    vehicle_ids = await r.smembers(f"edges:{event_id}")
    result = {}
    for vid in vehicle_ids:
        key = f"edge:{event_id}:{vid}"
        data = await r.get(key)
        if data:
            result[vid] = json.loads(data)
    return result


async def publish_edge_status(event_id: str, vehicle_id: str, status: dict) -> None:
    """Publish edge status update to SSE channel."""
    await publish_event(event_id, "edge_status", {
        "vehicle_id": vehicle_id,
        **status
    })


# ============ Edge Presence (vehicle-scoped, no event_id required) ============

async def set_edge_presence(vehicle_id: str, data: dict) -> None:
    """
    CLOUD-MANAGE-0: Store edge presence info keyed by vehicle_id only.
    Used by simple heartbeat to store edge_url before event_id is known.
    TTL: 60 seconds (longer than event-scoped edge status since simple heartbeat
    is the first tier and may be the only one sending).
    """
    r = await get_redis()
    key = f"edge_presence:{vehicle_id}"
    await r.set(key, json.dumps(data), ex=60)


async def get_edge_presence(vehicle_id: str) -> Optional[dict]:
    """CLOUD-MANAGE-0: Get vehicle-scoped edge presence (edge_url, capabilities)."""
    r = await get_redis()
    key = f"edge_presence:{vehicle_id}"
    raw = await r.get(key)
    return json.loads(raw) if raw else None


# ============ Edge Command Management ============

async def set_edge_command(event_id: str, vehicle_id: str, command_id: str, command: dict) -> None:
    """
    Store a command for correlation with edge response.
    Expires after 60 seconds.
    """
    r = await get_redis()
    key = f"cmd:{event_id}:{vehicle_id}:{command_id}"
    await r.set(key, json.dumps(command), ex=60)


async def get_edge_command(event_id: str, vehicle_id: str, command_id: str) -> Optional[dict]:
    """Get a stored command by ID."""
    r = await get_redis()
    key = f"cmd:{event_id}:{vehicle_id}:{command_id}"
    data = await r.get(key)
    return json.loads(data) if data else None


async def publish_edge_command(event_id: str, vehicle_id: str, command: dict) -> None:
    """
    Publish a command to edge device via SSE.
    Edge subscribes to 'edge_command' events filtered by vehicle_id.
    """
    await publish_event(event_id, "edge_command", {
        "vehicle_id": vehicle_id,
        **command
    })


async def publish_command_response(event_id: str, vehicle_id: str, response: dict) -> None:
    """Publish command response to SSE for UI update."""
    await publish_event(event_id, "command_response", {
        "vehicle_id": vehicle_id,
        **response
    })


# ============ Active Camera State ============

async def set_active_camera(
    event_id: str,
    vehicle_id: str,
    camera: str,
    streaming: bool = None,
    updated_by: str = "admin",
) -> None:
    """
    Persist active camera selection for a vehicle.
    This is the authoritative state that survives restarts.
    """
    import time
    from datetime import datetime
    r = await get_redis()
    key = f"active_camera:{event_id}:{vehicle_id}"

    # Get existing state to preserve streaming status if not specified
    existing = await r.get(key)
    if existing:
        existing_data = json.loads(existing)
        if streaming is None:
            streaming = existing_data.get("streaming", False)
    else:
        if streaming is None:
            streaming = False

    state = {
        "camera": camera,
        "streaming": streaming,
        "updated_at": datetime.utcnow().isoformat(),
        "updated_by": updated_by,
    }
    await r.set(key, json.dumps(state))

    # Publish change to SSE
    await publish_event(event_id, "active_camera_change", {
        "vehicle_id": vehicle_id,
        "camera": camera,
        "streaming": streaming,
    })


async def get_active_camera(event_id: str, vehicle_id: str) -> Optional[dict]:
    """Get the active camera state for a vehicle."""
    r = await get_redis()
    key = f"active_camera:{event_id}:{vehicle_id}"
    data = await r.get(key)
    return json.loads(data) if data else None


async def set_streaming_state(event_id: str, vehicle_id: str, streaming: bool) -> None:
    """Update just the streaming state without changing camera."""
    r = await get_redis()
    key = f"active_camera:{event_id}:{vehicle_id}"
    existing = await r.get(key)
    if existing:
        state = json.loads(existing)
        state["streaming"] = streaming
        from datetime import datetime
        state["updated_at"] = datetime.utcnow().isoformat()
        await r.set(key, json.dumps(state))

        # Publish change
        await publish_event(event_id, "streaming_state_change", {
            "vehicle_id": vehicle_id,
            "streaming": streaming,
            "camera": state.get("camera"),
        })


# ============ PROD-1: Featured Camera State ============

async def set_featured_camera_state(
    event_id: str,
    vehicle_id: str,
    state: dict,
) -> None:
    """
    Persist featured camera state for a vehicle.

    State fields:
      desired_camera: what production requested
      active_camera: what edge confirmed
      request_id: pending command ID
      status: pending / success / failed / timeout
      last_error: short error string or None
      updated_at: ISO timestamp
    """
    r = await get_redis()
    key = f"featured_camera:{event_id}:{vehicle_id}"
    await r.set(key, json.dumps(state))


async def get_featured_camera_state(event_id: str, vehicle_id: str) -> Optional[dict]:
    """Get featured camera state for a vehicle."""
    r = await get_redis()
    key = f"featured_camera:{event_id}:{vehicle_id}"
    data = await r.get(key)
    return json.loads(data) if data else None


# ============ STREAM-3: Stream Profile State ============

async def set_stream_profile_state(
    event_id: str,
    vehicle_id: str,
    state: dict,
) -> None:
    """
    Persist stream profile state for a vehicle.

    State fields:
      desired_profile: what production requested (e.g. "720p30")
      active_profile: what edge confirmed
      request_id: pending command ID
      status: pending / success / failed / timeout
      last_error: short error string or None
      updated_at: ISO timestamp
    """
    r = await get_redis()
    key = f"stream_profile:{event_id}:{vehicle_id}"
    await r.set(key, json.dumps(state))


async def get_stream_profile_state(event_id: str, vehicle_id: str) -> Optional[dict]:
    """Get stream profile state for a vehicle."""
    r = await get_redis()
    key = f"stream_profile:{event_id}:{vehicle_id}"
    data = await r.get(key)
    return json.loads(data) if data else None


# ============ PROMPT 5: Telemetry Sharing Policy ============

# Telemetry field groups for easier configuration
TELEMETRY_FIELD_GROUPS = {
    "gps": ["lat", "lon", "speed_mps", "heading_deg", "altitude_m"],
    "engine_basic": ["rpm", "gear", "speed_mph"],
    "engine_advanced": ["throttle_pct", "coolant_temp_c", "oil_pressure_psi", "fuel_pressure_psi"],
    "biometrics": ["heart_rate", "heart_rate_zone"],
}

# All individual telemetry fields
ALL_TELEMETRY_FIELDS = [
    "lat", "lon", "speed_mps", "heading_deg", "altitude_m",  # GPS
    "rpm", "gear", "speed_mph",  # Engine basic
    "throttle_pct", "coolant_temp_c", "oil_pressure_psi", "fuel_pressure_psi",  # Engine advanced
    "heart_rate", "heart_rate_zone",  # Biometrics
]

# Safe defaults when no policy is set
# Production gets GPS only, fans get nothing
DEFAULT_TELEMETRY_POLICY = {
    "allow_production": ["lat", "lon", "speed_mps", "heading_deg"],  # GPS only
    "allow_fans": [],  # Nothing by default - pit crew must explicitly enable
}


async def set_telemetry_policy(
    event_id: str,
    vehicle_id: str,
    allow_production: list[str],
    allow_fans: list[str],
) -> dict:
    """
    Store telemetry sharing policy for a vehicle.

    Args:
        event_id: Event ID
        vehicle_id: Vehicle ID
        allow_production: List of field names production team can see
        allow_fans: List of field names fans can see (must be subset of allow_production)

    Returns:
        The stored policy
    """
    from datetime import datetime
    r = await get_redis()
    key = f"telemetry_policy:{event_id}:{vehicle_id}"

    # Validate that allow_fans is subset of allow_production
    fan_fields = set(allow_fans)
    production_fields = set(allow_production)
    if not fan_fields.issubset(production_fields):
        # Automatically constrain fans to production-allowed fields
        allow_fans = list(fan_fields.intersection(production_fields))

    policy = {
        "allow_production": allow_production,
        "allow_fans": allow_fans,
        "updated_at": datetime.utcnow().isoformat(),
    }

    await r.set(key, json.dumps(policy))

    # Publish policy change for real-time UI updates
    await publish_event(event_id, "telemetry_policy_change", {
        "vehicle_id": vehicle_id,
        "allow_production": allow_production,
        "allow_fans": allow_fans,
    })

    return policy


async def get_telemetry_policy(event_id: str, vehicle_id: str) -> dict:
    """
    Get telemetry sharing policy for a vehicle.

    Returns default safe policy if none is set.
    """
    r = await get_redis()
    key = f"telemetry_policy:{event_id}:{vehicle_id}"
    data = await r.get(key)

    if data:
        return json.loads(data)

    # Return safe defaults
    return DEFAULT_TELEMETRY_POLICY.copy()


async def delete_telemetry_policy(event_id: str, vehicle_id: str) -> None:
    """Delete telemetry policy, reverting to defaults."""
    r = await get_redis()
    key = f"telemetry_policy:{event_id}:{vehicle_id}"
    await r.delete(key)


async def filter_telemetry_by_policy(
    telemetry: dict,
    event_id: str,
    vehicle_id: str,
    viewer_type: str,  # "production" or "fan"
) -> dict:
    """
    Filter telemetry data based on sharing policy.

    Server-side enforcement - never trust the client.

    Args:
        telemetry: Raw telemetry dict
        event_id: Event ID
        vehicle_id: Vehicle ID
        viewer_type: "production" for control room, "fan" for public viewers

    Returns:
        Filtered telemetry with only allowed fields
    """
    policy = await get_telemetry_policy(event_id, vehicle_id)

    # Get allowed fields based on viewer type
    if viewer_type == "production":
        allowed_fields = set(policy.get("allow_production", []))
    else:  # fan
        allowed_fields = set(policy.get("allow_fans", []))

    # Always include metadata fields
    always_include = {"vehicle_id", "ts_ms", "event_id", "vehicle_number", "team_name", "type"}

    filtered = {}
    for field, value in telemetry.items():
        if field in always_include or field in allowed_fields:
            filtered[field] = value

    return filtered


async def get_all_vehicle_policies(event_id: str) -> dict[str, dict]:
    """
    Get telemetry policies for all vehicles in an event.

    Returns dict of vehicle_id -> policy
    """
    r = await get_redis()
    # Get all keys matching the pattern
    pattern = f"telemetry_policy:{event_id}:*"
    keys = []
    async for key in r.scan_iter(match=pattern):
        keys.append(key)

    policies = {}
    for key in keys:
        data = await r.get(key)
        if data:
            # Extract vehicle_id from key
            vehicle_id = key.split(":")[-1]
            policies[vehicle_id] = json.loads(data)

    return policies
