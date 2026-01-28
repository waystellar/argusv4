"""
Stream Control State Machine

This module provides a unified, authoritative state machine for streaming control
across both Production Control and Pit Crew interfaces.

State Machine:
    DISCONNECTED → (edge heartbeat) → IDLE
    IDLE → (start request) → STARTING → (edge ACK) → STREAMING
    IDLE → (start request, timeout) → ERROR
    STREAMING → (stop request) → STOPPING → (edge ACK) → IDLE
    STREAMING → (stop request, timeout) → ERROR
    * → (no heartbeat for threshold) → DISCONNECTED

Key Invariants:
    - Stream cannot be STREAMING unless edge has ACKed (or verified signal exists)
    - Start requests must specify a source_id (camera)
    - Stop is always allowed by authorized users regardless of who started
    - If edge is unreachable, UI shows DISCONNECTED with retry guidance
"""
import time
import uuid
from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel
import structlog

from app import redis_client

logger = structlog.get_logger("stream_control")


class StreamState(str, Enum):
    """Stream control states."""
    DISCONNECTED = "DISCONNECTED"  # Edge not reachable (no recent heartbeat)
    IDLE = "IDLE"                  # Connected, no active stream
    STARTING = "STARTING"          # Start requested, awaiting ACK
    STREAMING = "STREAMING"        # Active stream confirmed by edge
    STOPPING = "STOPPING"          # Stop requested, awaiting ACK
    ERROR = "ERROR"                # Failed start/stop with reason


class StreamErrorReason(str, Enum):
    """Error reasons for stream failures."""
    EDGE_TIMEOUT = "EDGE_TIMEOUT"           # Edge didn't respond in time
    EDGE_DISCONNECTED = "EDGE_DISCONNECTED" # Edge went offline during operation
    EDGE_REJECTED = "EDGE_REJECTED"         # Edge explicitly rejected command
    INVALID_SOURCE = "INVALID_SOURCE"       # Requested camera not available
    YOUTUBE_NOT_CONFIGURED = "YOUTUBE_NOT_CONFIGURED"  # No YouTube stream key
    FFMPEG_FAILED = "FFMPEG_FAILED"         # FFmpeg process failed to start
    UNKNOWN = "UNKNOWN"                     # Unknown error


class StreamControlState(BaseModel):
    """Full stream control state for a vehicle."""
    state: StreamState
    source_id: Optional[str] = None         # Camera: chase, pov, roof, front
    error_reason: Optional[StreamErrorReason] = None
    error_message: Optional[str] = None
    error_guidance: Optional[str] = None    # User-facing guidance for error resolution
    controlled_by: Optional[str] = None     # "production" or "pit_crew"
    started_at: Optional[int] = None        # Epoch ms when streaming started
    command_id: Optional[str] = None        # Pending command ID for tracking
    last_updated: str                        # ISO timestamp
    edge_heartbeat_ms: Optional[int] = None # Last edge heartbeat timestamp
    youtube_url: Optional[str] = None       # Public YouTube URL when streaming


class StreamSource(BaseModel):
    """Available stream source (camera)."""
    source_id: str                  # chase, pov, roof, front
    label: str                      # Human-readable label
    type: str                       # "camera"
    available: bool                 # Whether device is available
    device: Optional[str] = None    # Device path (/dev/video0)
    preview_url: Optional[str] = None
    last_seen: Optional[int] = None # Last activity timestamp


# Configuration
HEARTBEAT_THRESHOLD_S = 30  # Consider edge disconnected after this many seconds
COMMAND_TIMEOUT_S = 15      # How long to wait for edge ACK


async def _get_redis():
    """Get Redis client."""
    return await redis_client.get_redis()


def _state_key(event_id: str, vehicle_id: str) -> str:
    """Redis key for stream state."""
    return f"stream_state:{event_id}:{vehicle_id}"


async def get_stream_state(event_id: str, vehicle_id: str) -> StreamControlState:
    """
    Get current stream control state for a vehicle.

    Automatically transitions to DISCONNECTED if edge heartbeat is stale.
    """
    r = await _get_redis()
    key = _state_key(event_id, vehicle_id)

    # Get stored state
    import json
    data = await r.get(key)

    now = datetime.utcnow()
    now_ms = int(time.time() * 1000)

    # Get edge status to check connectivity
    edge_status = await redis_client.get_edge_status(event_id, vehicle_id)
    edge_heartbeat_ms = edge_status.get("heartbeat_ts") if edge_status else None

    # Determine if edge is connected (has recent heartbeat)
    edge_connected = False
    if edge_heartbeat_ms:
        age_s = (now_ms - edge_heartbeat_ms) / 1000.0
        edge_connected = age_s < HEARTBEAT_THRESHOLD_S

    # If we have stored state, use it as base
    if data:
        stored = json.loads(data)
        state = StreamControlState(
            state=StreamState(stored.get("state", "IDLE")),
            source_id=stored.get("source_id"),
            error_reason=StreamErrorReason(stored["error_reason"]) if stored.get("error_reason") else None,
            error_message=stored.get("error_message"),
            error_guidance=stored.get("error_guidance"),
            controlled_by=stored.get("controlled_by"),
            started_at=stored.get("started_at"),
            command_id=stored.get("command_id"),
            last_updated=stored.get("last_updated", now.isoformat()),
            edge_heartbeat_ms=edge_heartbeat_ms,
            youtube_url=stored.get("youtube_url") or (edge_status.get("youtube_url") if edge_status else None),
        )
    else:
        # No stored state - create default
        state = StreamControlState(
            state=StreamState.DISCONNECTED if not edge_connected else StreamState.IDLE,
            last_updated=now.isoformat(),
            edge_heartbeat_ms=edge_heartbeat_ms,
            youtube_url=edge_status.get("youtube_url") if edge_status else None,
        )

    # Auto-transition to DISCONNECTED if edge went offline
    if not edge_connected and state.state not in [StreamState.DISCONNECTED, StreamState.ERROR]:
        state.state = StreamState.DISCONNECTED
        state.error_reason = StreamErrorReason.EDGE_DISCONNECTED
        state.error_message = "Edge device is offline"
        state.error_guidance = "Check edge device power and network connection. Edge must send heartbeats."
        state.last_updated = now.isoformat()
        # Save transition
        await _save_state(event_id, vehicle_id, state)

    # If edge just reconnected and we're in DISCONNECTED, transition to IDLE
    if edge_connected and state.state == StreamState.DISCONNECTED:
        # Check if edge is actually streaming (from heartbeat)
        if edge_status and edge_status.get("streaming_status") == "live":
            state.state = StreamState.STREAMING
            state.source_id = edge_status.get("streaming_camera")
            state.started_at = edge_status.get("streaming_started_at")
            state.youtube_url = edge_status.get("youtube_url")
        else:
            state.state = StreamState.IDLE
        state.error_reason = None
        state.error_message = None
        state.error_guidance = None
        state.last_updated = now.isoformat()
        await _save_state(event_id, vehicle_id, state)

    # Sync streaming state from edge heartbeat if we're out of sync
    if edge_connected and edge_status:
        edge_streaming = edge_status.get("streaming_status") == "live"
        our_streaming = state.state == StreamState.STREAMING

        if edge_streaming and not our_streaming and state.state != StreamState.STARTING:
            # Edge started streaming (maybe from local controls)
            state.state = StreamState.STREAMING
            state.source_id = edge_status.get("streaming_camera")
            state.started_at = edge_status.get("streaming_started_at")
            state.youtube_url = edge_status.get("youtube_url")
            state.controlled_by = state.controlled_by or "pit_crew"
            state.last_updated = now.isoformat()
            await _save_state(event_id, vehicle_id, state)

        elif not edge_streaming and our_streaming and state.state != StreamState.STOPPING:
            # Edge stopped streaming (maybe from local controls)
            state.state = StreamState.IDLE
            state.source_id = None
            state.started_at = None
            state.controlled_by = None
            state.last_updated = now.isoformat()
            await _save_state(event_id, vehicle_id, state)

    return state


async def _save_state(event_id: str, vehicle_id: str, state: StreamControlState) -> None:
    """Save stream state to Redis."""
    import json
    r = await _get_redis()
    key = _state_key(event_id, vehicle_id)

    data = {
        "state": state.state.value,
        "source_id": state.source_id,
        "error_reason": state.error_reason.value if state.error_reason else None,
        "error_message": state.error_message,
        "error_guidance": state.error_guidance,
        "controlled_by": state.controlled_by,
        "started_at": state.started_at,
        "command_id": state.command_id,
        "last_updated": state.last_updated,
        "youtube_url": state.youtube_url,
    }

    await r.set(key, json.dumps(data), ex=3600)  # 1 hour TTL

    # Publish state change for UI updates
    await redis_client.publish_event(event_id, "stream_state_change", {
        "vehicle_id": vehicle_id,
        **data,
    })


async def get_available_sources(event_id: str, vehicle_id: str) -> list[StreamSource]:
    """
    Get available stream sources (cameras) for a vehicle.

    Sources come from edge heartbeat data.
    """
    edge_status = await redis_client.get_edge_status(event_id, vehicle_id)

    sources = []

    if not edge_status:
        # Edge offline - return default cameras as unavailable
        for cam in ["chase", "pov", "roof", "front"]:
            sources.append(StreamSource(
                source_id=cam,
                label=_camera_label(cam),
                type="camera",
                available=False,
            ))
        return sources

    # Get cameras from edge heartbeat
    cameras = edge_status.get("cameras", [])
    streaming_camera = edge_status.get("streaming_camera")

    if cameras:
        for cam_info in cameras:
            cam_name = cam_info.get("name", "unknown")
            cam_status = cam_info.get("status", "offline")

            sources.append(StreamSource(
                source_id=cam_name,
                label=_camera_label(cam_name),
                type="camera",
                available=cam_status in ["available", "active", "online"],
                device=cam_info.get("device"),
                last_seen=edge_status.get("heartbeat_ts"),
            ))
    else:
        # No camera info - provide defaults based on edge being online
        for cam in ["chase", "pov", "roof", "front"]:
            sources.append(StreamSource(
                source_id=cam,
                label=_camera_label(cam),
                type="camera",
                available=True,  # Assume available since edge is online
                last_seen=edge_status.get("heartbeat_ts"),
            ))

    return sources


def _camera_label(cam_id: str) -> str:
    """Get human-readable label for camera ID."""
    labels = {
        "chase": "Chase Cam",
        "pov": "Driver POV",
        "roof": "Roof 360",
        "front": "Front Bumper",
        "side": "Side View",
        "rear": "Rear View",
    }
    return labels.get(cam_id, cam_id.title())


async def start_stream(
    event_id: str,
    vehicle_id: str,
    source_id: str,
    controller: str,  # "production" or "pit_crew"
) -> tuple[StreamControlState, Optional[str]]:
    """
    Request to start streaming.

    Args:
        event_id: Event ID
        vehicle_id: Vehicle ID
        source_id: Camera to stream (chase, pov, roof, front)
        controller: Who initiated the request ("production" or "pit_crew")

    Returns:
        Tuple of (new_state, command_id or None)

    Raises:
        ValueError: If source_id is invalid or stream cannot be started
    """
    now = datetime.utcnow()
    now_ms = int(time.time() * 1000)

    # Validate source_id
    valid_sources = {"chase", "pov", "roof", "front", "side", "rear"}
    if source_id not in valid_sources:
        raise ValueError(f"Invalid source_id. Must be one of: {valid_sources}")

    # Get current state
    state = await get_stream_state(event_id, vehicle_id)

    # Check edge connectivity
    edge_status = await redis_client.get_edge_status(event_id, vehicle_id)
    if not edge_status:
        state.state = StreamState.ERROR
        state.error_reason = StreamErrorReason.EDGE_DISCONNECTED
        state.error_message = "Edge device is offline"
        state.error_guidance = "Cannot start stream. Check that the edge device is powered on and connected to the network."
        state.last_updated = now.isoformat()
        await _save_state(event_id, vehicle_id, state)
        return state, None

    # Check if edge has YouTube configured
    if not edge_status.get("youtube_configured"):
        state.state = StreamState.ERROR
        state.error_reason = StreamErrorReason.YOUTUBE_NOT_CONFIGURED
        state.error_message = "YouTube stream key not configured"
        state.error_guidance = "Configure the YouTube stream key on the edge device before starting the stream."
        state.last_updated = now.isoformat()
        await _save_state(event_id, vehicle_id, state)
        return state, None

    # Check if already streaming
    if state.state == StreamState.STREAMING:
        # Already streaming - allow camera switch
        pass
    elif state.state == StreamState.STARTING:
        # Already starting - return current state
        return state, state.command_id

    # Check if requested camera is available
    sources = await get_available_sources(event_id, vehicle_id)
    source = next((s for s in sources if s.source_id == source_id), None)
    if source and not source.available:
        state.state = StreamState.ERROR
        state.error_reason = StreamErrorReason.INVALID_SOURCE
        state.error_message = f"Camera '{source_id}' is not available"
        state.error_guidance = f"Select a different camera. The '{_camera_label(source_id)}' camera device is offline or not connected."
        state.last_updated = now.isoformat()
        await _save_state(event_id, vehicle_id, state)
        return state, None

    # Generate command ID
    command_id = f"cmd_{uuid.uuid4().hex[:12]}"

    logger.info(
        "[STREAM_CONTROL] START_STREAM requested",
        event_id=event_id,
        vehicle_id=vehicle_id,
        source_id=source_id,
        controller=controller,
        command_id=command_id,
    )

    # Transition to STARTING
    state.state = StreamState.STARTING
    state.source_id = source_id
    state.controlled_by = controller
    state.command_id = command_id
    state.error_reason = None
    state.error_message = None
    state.error_guidance = None
    state.last_updated = now.isoformat()
    await _save_state(event_id, vehicle_id, state)

    logger.info(
        "[STREAM_CONTROL] State transition STARTING",
        event_id=event_id,
        vehicle_id=vehicle_id,
        new_state="STARTING",
        command_id=command_id,
    )

    # Send command to edge
    command_payload = {
        "command_id": command_id,
        "command": "start_stream",
        "params": {"camera": source_id},
        "sent_at": now.isoformat(),
        "sender": controller,
    }

    # Store command for correlation
    await redis_client.set_edge_command(event_id, vehicle_id, command_id, {
        **command_payload,
        "status": "pending",
        "vehicle_id": vehicle_id,
    })

    # Publish command to edge
    await redis_client.publish_edge_command(event_id, vehicle_id, command_payload)

    logger.info(
        "[STREAM_CONTROL] Command sent to edge",
        event_id=event_id,
        vehicle_id=vehicle_id,
        command="start_stream",
        command_id=command_id,
        camera=source_id,
    )

    return state, command_id


async def stop_stream(
    event_id: str,
    vehicle_id: str,
    controller: str,  # "production" or "pit_crew"
) -> tuple[StreamControlState, Optional[str]]:
    """
    Request to stop streaming.

    Stop is always allowed regardless of who started the stream.

    Args:
        event_id: Event ID
        vehicle_id: Vehicle ID
        controller: Who initiated the request ("production" or "pit_crew")

    Returns:
        Tuple of (new_state, command_id or None)
    """
    now = datetime.utcnow()

    # Get current state
    state = await get_stream_state(event_id, vehicle_id)

    # If not streaming or starting, nothing to stop
    if state.state not in [StreamState.STREAMING, StreamState.STARTING]:
        # Still try to send stop command in case state is out of sync
        pass

    # Generate command ID
    command_id = f"cmd_{uuid.uuid4().hex[:12]}"

    logger.info(
        "[STREAM_CONTROL] STOP_STREAM requested",
        event_id=event_id,
        vehicle_id=vehicle_id,
        controller=controller,
        command_id=command_id,
        previous_state=state.state.value,
    )

    # Transition to STOPPING
    state.state = StreamState.STOPPING
    state.command_id = command_id
    state.error_reason = None
    state.error_message = None
    state.error_guidance = None
    state.last_updated = now.isoformat()
    await _save_state(event_id, vehicle_id, state)

    logger.info(
        "[STREAM_CONTROL] State transition STOPPING",
        event_id=event_id,
        vehicle_id=vehicle_id,
        new_state="STOPPING",
        command_id=command_id,
    )

    # Send command to edge
    command_payload = {
        "command_id": command_id,
        "command": "stop_stream",
        "params": {},
        "sent_at": now.isoformat(),
        "sender": controller,
    }

    # Store command for correlation
    await redis_client.set_edge_command(event_id, vehicle_id, command_id, {
        **command_payload,
        "status": "pending",
        "vehicle_id": vehicle_id,
    })

    # Publish command to edge
    await redis_client.publish_edge_command(event_id, vehicle_id, command_payload)

    logger.info(
        "[STREAM_CONTROL] Command sent to edge",
        event_id=event_id,
        vehicle_id=vehicle_id,
        command="stop_stream",
        command_id=command_id,
    )

    return state, command_id


async def handle_edge_response(
    event_id: str,
    vehicle_id: str,
    command_id: str,
    status: str,  # "success" or "error"
    message: Optional[str] = None,
    data: Optional[dict] = None,
) -> StreamControlState:
    """
    Handle response from edge device for a command.

    This is called when the edge device ACKs a start/stop command.
    """
    now = datetime.utcnow()
    now_ms = int(time.time() * 1000)

    logger.info(
        "[STREAM_CONTROL] EDGE_RESPONSE received",
        event_id=event_id,
        vehicle_id=vehicle_id,
        command_id=command_id,
        status=status,
        message=message,
    )

    # Get the original command
    command = await redis_client.get_edge_command(event_id, vehicle_id, command_id)

    # Get current state
    state = await get_stream_state(event_id, vehicle_id)

    # Only process if this is the command we're waiting for
    if state.command_id != command_id:
        logger.warning(
            "[STREAM_CONTROL] Stale command response ignored",
            event_id=event_id,
            vehicle_id=vehicle_id,
            received_command_id=command_id,
            expected_command_id=state.command_id,
        )
        return state

    command_type = command.get("command") if command else None
    previous_state = state.state.value

    if status == "success":
        if command_type == "start_stream":
            # Transition to STREAMING
            state.state = StreamState.STREAMING
            state.started_at = now_ms
            state.youtube_url = data.get("youtube_url") if data else None
            state.source_id = data.get("camera") if data else state.source_id
            state.command_id = None
            state.error_reason = None
            state.error_message = None
            state.error_guidance = None

            logger.info(
                "[STREAM_CONTROL] State transition STREAMING (edge ACK success)",
                event_id=event_id,
                vehicle_id=vehicle_id,
                previous_state=previous_state,
                new_state="STREAMING",
                camera=state.source_id,
                youtube_url=state.youtube_url,
            )

        elif command_type == "stop_stream":
            # Transition to IDLE
            state.state = StreamState.IDLE
            state.source_id = None
            state.started_at = None
            state.controlled_by = None
            state.command_id = None
            state.youtube_url = None
            state.error_reason = None
            state.error_message = None
            state.error_guidance = None

            logger.info(
                "[STREAM_CONTROL] State transition IDLE (edge ACK success)",
                event_id=event_id,
                vehicle_id=vehicle_id,
                previous_state=previous_state,
                new_state="IDLE",
            )

    elif status == "error":
        # Transition to ERROR
        state.state = StreamState.ERROR
        state.command_id = None

        # Determine error reason from message
        error_msg = message or "Unknown error"
        if "ffmpeg" in error_msg.lower():
            state.error_reason = StreamErrorReason.FFMPEG_FAILED
            state.error_guidance = "FFmpeg failed to start. Check camera connection and YouTube stream key."
        elif "youtube" in error_msg.lower():
            state.error_reason = StreamErrorReason.YOUTUBE_NOT_CONFIGURED
            state.error_guidance = "Check YouTube stream key configuration on edge device."
        elif "camera" in error_msg.lower() or "device" in error_msg.lower():
            state.error_reason = StreamErrorReason.INVALID_SOURCE
            state.error_guidance = "The selected camera is not available. Try a different camera."
        else:
            state.error_reason = StreamErrorReason.EDGE_REJECTED
            state.error_guidance = "Edge device rejected the command. Check edge logs for details."

        state.error_message = error_msg

        logger.error(
            "[STREAM_CONTROL] State transition ERROR (edge ACK error)",
            event_id=event_id,
            vehicle_id=vehicle_id,
            previous_state=previous_state,
            new_state="ERROR",
            error_reason=state.error_reason.value if state.error_reason else None,
            error_message=error_msg,
        )

    state.last_updated = now.isoformat()
    await _save_state(event_id, vehicle_id, state)

    return state


async def handle_command_timeout(
    event_id: str,
    vehicle_id: str,
    command_id: str,
) -> StreamControlState:
    """
    Handle timeout when edge doesn't respond to a command.

    This is called by the UI after polling expires.
    """
    now = datetime.utcnow()

    logger.warning(
        "[STREAM_CONTROL] COMMAND_TIMEOUT",
        event_id=event_id,
        vehicle_id=vehicle_id,
        command_id=command_id,
    )

    # Get current state
    state = await get_stream_state(event_id, vehicle_id)

    # Only process if this is the command we're waiting for
    if state.command_id != command_id:
        logger.info(
            "[STREAM_CONTROL] Timeout ignored - stale command",
            event_id=event_id,
            vehicle_id=vehicle_id,
            received_command_id=command_id,
            expected_command_id=state.command_id,
        )
        return state

    previous_state = state.state.value

    # Transition to ERROR
    state.state = StreamState.ERROR
    state.error_reason = StreamErrorReason.EDGE_TIMEOUT
    state.error_message = "Edge device did not respond in time"
    state.error_guidance = "The edge device did not acknowledge the command. Check edge connectivity and try again."
    state.command_id = None
    state.last_updated = now.isoformat()

    logger.error(
        "[STREAM_CONTROL] State transition ERROR (timeout)",
        event_id=event_id,
        vehicle_id=vehicle_id,
        previous_state=previous_state,
        new_state="ERROR",
        error_reason="EDGE_TIMEOUT",
    )

    await _save_state(event_id, vehicle_id, state)

    return state


async def retry_from_error(
    event_id: str,
    vehicle_id: str,
) -> StreamControlState:
    """
    Clear error state and return to IDLE or DISCONNECTED based on connectivity.
    """
    now = datetime.utcnow()

    # Check edge connectivity
    edge_status = await redis_client.get_edge_status(event_id, vehicle_id)

    state = await get_stream_state(event_id, vehicle_id)

    if edge_status:
        state.state = StreamState.IDLE
    else:
        state.state = StreamState.DISCONNECTED

    state.error_reason = None
    state.error_message = None
    state.error_guidance = None
    state.command_id = None
    state.last_updated = now.isoformat()

    await _save_state(event_id, vehicle_id, state)

    return state
