"""
Server-Sent Events (SSE) streaming for real-time updates.

Supports field-level permission filtering based on viewer access:
- public: Free fans (see public fields only)
- premium: Premium subscribers (see public + premium fields)
- team: Team members (see everything except hidden fields)

FIXED: Database session scope - generator now creates its own session
to prevent InvalidRequestError when FastAPI closes the endpoint session.

PR-1 SECURITY FIX: Access level is now computed server-side from auth headers,
NOT from client-controlled query parameters.
"""
import asyncio
import json
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sse_starlette.sse import EventSourceResponse

from app.database import get_session, get_session_context
from app.models import Event
from app import redis_client
from app.config import get_settings
from app.services.permission_filter import filter_position_for_viewer
from app.services.auth import get_viewer_access

settings = get_settings()
router = APIRouter(prefix="/api/v1/events", tags=["stream"])


async def event_generator(
    request: Request,
    event_id: str,
    viewer_access: str,
    last_event_id: Optional[int] = None,
):
    """
    Generator that yields SSE events for a given race event.
    Subscribes to Redis pub/sub and forwards messages to client.

    FIXED: Creates its own database session to prevent session scope issues.
    The previous implementation received db session from endpoint, which would
    be closed by FastAPI while the generator was still running.

    Gap 3: Supports Last-Event-ID replay. If last_event_id is provided,
    replays buffered events before switching to live pub/sub.

    Args:
        request: FastAPI request object
        event_id: Event ID to stream
        viewer_access: "public", "premium", or "team"
        last_event_id: Last received SSE event ID for replay (Gap 3)
    """
    # Send initial connected event
    yield {
        "event": "connected",
        "data": json.dumps({
            "event_id": event_id,
            "server_time": datetime.utcnow().isoformat(),
            "access_level": viewer_access,
        }),
    }

    # FIXED: Create dedicated session for this generator's lifetime
    # This session will remain valid for the entire SSE connection
    async with get_session_context() as db:
        # Gap 3: If reconnecting with Last-Event-ID, try replay before snapshot
        replayed = False
        if last_event_id is not None:
            replay_events = await redis_client.get_replay_events(event_id, last_event_id)
            if replay_events:
                # Replay missed events with their original IDs
                for entry in replay_events:
                    event_data = entry["data"]
                    event_type = entry["type"]

                    # Apply same filtering as live events
                    if event_type == "position":
                        hidden = await redis_client.get_visible_vehicles(event_id)
                        vid = event_data.get("vehicle_id")
                        if vid in hidden:
                            continue
                        event_data = await filter_position_for_viewer(
                            event_data, event_id, viewer_access, db,
                        )

                    yield {
                        "event": event_type,
                        "data": json.dumps(event_data),
                        "id": str(entry["seq"]),
                    }
                replayed = True

        if not replayed:
            # Send current positions as snapshot (filtered by permissions)
            positions = await redis_client.get_latest_positions(event_id)
            hidden = await redis_client.get_visible_vehicles(event_id)

            visible_positions = []
            for vid, pos in positions.items():
                if vid in hidden:
                    continue
                # Apply field-level filtering
                filtered_pos = await filter_position_for_viewer(
                    {**pos, "vehicle_id": vid},
                    event_id,
                    viewer_access,
                    db,
                )
                visible_positions.append(filtered_pos)

            yield {
                "event": "snapshot",
                "data": json.dumps({"vehicles": visible_positions}),
            }

        # Subscribe to Redis channel
        async with redis_client.subscribe_to_event(event_id) as pubsub:
            # FIXED: Periodically refresh hidden vehicles cache
            last_hidden_refresh = asyncio.get_event_loop().time()
            HIDDEN_REFRESH_INTERVAL = 30  # seconds

            while True:
                # Check if client disconnected
                if await request.is_disconnected():
                    break

                try:
                    # FIXED: Refresh hidden vehicles cache periodically
                    current_time = asyncio.get_event_loop().time()
                    if current_time - last_hidden_refresh > HIDDEN_REFRESH_INTERVAL:
                        hidden = await redis_client.get_visible_vehicles(event_id)
                        last_hidden_refresh = current_time

                    # Wait for message with timeout (for keepalive)
                    message = await asyncio.wait_for(
                        pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0),
                        timeout=settings.sse_keepalive_s,
                    )

                    if message and message["type"] == "message":
                        data = json.loads(message["data"])
                        event_type = data.get("type", "message")
                        event_data = data.get("data", {})
                        # Gap 3: Extract sequence ID from published message
                        seq_id = data.get("seq")

                        # Handle visibility update events - refresh hidden cache immediately
                        if event_type == "permission":
                            hidden = await redis_client.get_visible_vehicles(event_id)

                        # Filter hidden vehicles for position events
                        if event_type == "position":
                            vid = event_data.get("vehicle_id")
                            if vid in hidden:
                                continue

                            # Apply field-level filtering
                            event_data = await filter_position_for_viewer(
                                event_data,
                                event_id,
                                viewer_access,
                                db,
                            )

                        sse_event = {
                            "event": event_type,
                            "data": json.dumps(event_data),
                        }
                        # Gap 3: Include event ID for Last-Event-ID tracking
                        if seq_id is not None:
                            sse_event["id"] = str(seq_id)
                        yield sse_event
                    else:
                        # PR-2 UX: Send heartbeat event with server timestamp
                        # Allows frontend to track latency and connection health
                        yield {
                            "event": "heartbeat",
                            "data": json.dumps({
                                "server_ts": datetime.utcnow().isoformat(),
                                "ts_ms": int(datetime.utcnow().timestamp() * 1000),
                            }),
                        }

                except asyncio.TimeoutError:
                    # PR-2 UX: Send heartbeat event instead of comment on timeout
                    yield {
                        "event": "heartbeat",
                        "data": json.dumps({
                            "server_ts": datetime.utcnow().isoformat(),
                            "ts_ms": int(datetime.utcnow().timestamp() * 1000),
                        }),
                    }

                except Exception as e:
                    # On error, log and wait before retrying
                    # Don't crash the stream for transient errors
                    await asyncio.sleep(1)


@router.get("/{event_id}/stream")
async def stream_event(
    event_id: str,
    request: Request,
    db: AsyncSession = Depends(get_session),
    lastEventId: Optional[str] = None,
):
    """
    SSE endpoint for real-time event updates.

    PR-1 SECURITY FIX: Access level is computed server-side from auth headers.
    - X-Admin-Token: team access (admin can see everything except hidden)
    - X-Team-Token or X-Truck-Token: team access (if registered for this event)
    - Authorization: Bearer <token>: premium access (if valid subscription)
    - No auth headers: public access

    Event types:
    - connected: Initial connection acknowledgement (includes access_level)
    - snapshot: All current vehicle positions (filtered by access level)
    - position: Single vehicle position update (filtered by access level)
    - checkpoint: Vehicle crossed a checkpoint
    - permission: Vehicle visibility changed
    - heartbeat: Server timestamp for latency tracking (PR-2 UX)

    Gap 3: Supports Last-Event-ID for replay on reconnect.
    Pass ?lastEventId=<id> to replay missed events instead of full snapshot.
    Also reads the standard Last-Event-ID header set by EventSource API.

    Telemetry fields are filtered based on team permission settings:
    - public: GPS position, speed, heading, RPM, gear
    - premium: + throttle, coolant temp
    - team: + oil pressure, fuel pressure, heart rate

    Clients should use EventSource API with automatic reconnection.
    """
    # Validate event exists (uses endpoint session which is fine here)
    result = await db.execute(select(Event).where(Event.event_id == event_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Event not found")

    # PR-1 SECURITY FIX: Compute access level from auth headers, NOT query param
    viewer_access = await get_viewer_access(event_id, request, db)

    # Gap 3: Resolve Last-Event-ID from query param or standard header
    last_event_id: Optional[int] = None
    raw_id = lastEventId or request.headers.get("last-event-id")
    if raw_id:
        try:
            last_event_id = int(raw_id)
        except (ValueError, TypeError):
            pass  # Invalid ID, fall through to full snapshot

    # FIXED: Don't pass db to generator - it creates its own session
    return EventSourceResponse(
        event_generator(request, event_id, viewer_access, last_event_id=last_event_id),
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",  # Disable nginx buffering
        },
    )
