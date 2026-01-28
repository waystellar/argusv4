#!/bin/bash
# Argus v4 - Stream Control State Diagnostic Script
# Dumps current state of streaming control system for debugging
#
# Usage: ./scripts/dump_stream_control_state.sh [event_id] [vehicle_id]
#
# Output is written to both stdout and artifacts/logs/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${PROJECT_ROOT}/artifacts/logs"
LOG_FILE="${LOG_DIR}/${TIMESTAMP}_dump_stream_state.txt"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Redis connection (from environment or default)
REDIS_URL="${REDIS_URL:-redis://localhost:6379}"

# API URL (from environment or default)
API_URL="${API_URL:-http://localhost:8000}"

# Admin token (from environment)
ADMIN_TOKEN="${ADMIN_TOKEN:-}"

# Function to log to both stdout and file
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

log_section() {
    log ""
    log "============================================================"
    log "$1"
    log "============================================================"
}

# Start logging
log "=== Argus Stream Control State Dump ==="
log "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log "Log file: $LOG_FILE"
log ""
log "Environment (names only, no secrets):"
log "  REDIS_URL: ${REDIS_URL:+set}"
log "  API_URL: $API_URL"
log "  ADMIN_TOKEN: ${ADMIN_TOKEN:+set}"

# Parse arguments
EVENT_ID="${1:-}"
VEHICLE_ID="${2:-}"

if [ -z "$EVENT_ID" ]; then
    log ""
    log "No event_id provided. Listing all events..."
    log_section "ACTIVE EVENTS"

    # Try to get events from API
    if [ -n "$ADMIN_TOKEN" ]; then
        EVENTS_RESPONSE=$(curl -sf "${API_URL}/api/v1/events" 2>/dev/null || echo "API_ERROR")
        if [ "$EVENTS_RESPONSE" != "API_ERROR" ]; then
            echo "$EVENTS_RESPONSE" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$EVENTS_RESPONSE"
        else
            log "Failed to fetch events from API"
        fi
    else
        log "ADMIN_TOKEN not set - cannot query API"
    fi

    log ""
    log "Usage: $0 <event_id> [vehicle_id]"
    log ""
    log "Log saved to: $LOG_FILE"
    exit 0
fi

log ""
log "Event ID: $EVENT_ID"
log "Vehicle ID: ${VEHICLE_ID:-all}"

# Check if redis-cli is available
if ! command -v redis-cli &> /dev/null; then
    log ""
    log "WARNING: redis-cli not found. Skipping Redis queries."
    REDIS_AVAILABLE=false
else
    REDIS_AVAILABLE=true
fi

# Extract Redis host/port from URL
REDIS_HOST=$(echo "$REDIS_URL" | sed -E 's|redis://([^:]+).*|\1|')
REDIS_PORT=$(echo "$REDIS_URL" | sed -E 's|redis://[^:]+:([0-9]+).*|\1|')
REDIS_PORT="${REDIS_PORT:-6379}"

redis_cmd() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
}

# Dump Redis state
if [ "$REDIS_AVAILABLE" = true ]; then
    log_section "REDIS: Edge Statuses (edge:{event_id}:{vehicle_id})"

    if [ -n "$VEHICLE_ID" ]; then
        # Single vehicle
        EDGE_STATUS=$(redis_cmd GET "edge:${EVENT_ID}:${VEHICLE_ID}")
        if [ -n "$EDGE_STATUS" ]; then
            log "Vehicle: $VEHICLE_ID"
            echo "$EDGE_STATUS" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$EDGE_STATUS"
        else
            log "No edge status found for vehicle $VEHICLE_ID"
        fi
    else
        # All vehicles in event
        EDGE_SET=$(redis_cmd SMEMBERS "edges:${EVENT_ID}")
        if [ -n "$EDGE_SET" ]; then
            for vid in $EDGE_SET; do
                log ""
                log "Vehicle: $vid"
                EDGE_STATUS=$(redis_cmd GET "edge:${EVENT_ID}:${vid}")
                if [ -n "$EDGE_STATUS" ]; then
                    echo "$EDGE_STATUS" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$EDGE_STATUS"
                else
                    log "  (no status data)"
                fi
            done
        else
            log "No edges registered for event $EVENT_ID"
        fi
    fi

    log_section "REDIS: Active Camera States (active_camera:{event_id}:{vehicle_id})"

    if [ -n "$VEHICLE_ID" ]; then
        CAMERA_STATE=$(redis_cmd GET "active_camera:${EVENT_ID}:${VEHICLE_ID}")
        if [ -n "$CAMERA_STATE" ]; then
            log "Vehicle: $VEHICLE_ID"
            echo "$CAMERA_STATE" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$CAMERA_STATE"
        else
            log "No active camera state for vehicle $VEHICLE_ID"
        fi
    else
        # List all active_camera keys for event
        CAMERA_KEYS=$(redis_cmd KEYS "active_camera:${EVENT_ID}:*")
        if [ -n "$CAMERA_KEYS" ]; then
            for key in $CAMERA_KEYS; do
                vid=$(echo "$key" | sed "s|active_camera:${EVENT_ID}:||")
                log ""
                log "Vehicle: $vid"
                CAMERA_STATE=$(redis_cmd GET "$key")
                echo "$CAMERA_STATE" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$CAMERA_STATE"
            done
        else
            log "No active camera states for event $EVENT_ID"
        fi
    fi

    log_section "REDIS: Stream Control States (stream_state:{event_id}:{vehicle_id})"

    if [ -n "$VEHICLE_ID" ]; then
        STREAM_STATE=$(redis_cmd GET "stream_state:${EVENT_ID}:${VEHICLE_ID}")
        if [ -n "$STREAM_STATE" ]; then
            log "Vehicle: $VEHICLE_ID"
            echo "$STREAM_STATE" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$STREAM_STATE"
        else
            log "No stream state for vehicle $VEHICLE_ID (not using new state machine)"
        fi
    else
        STREAM_KEYS=$(redis_cmd KEYS "stream_state:${EVENT_ID}:*")
        if [ -n "$STREAM_KEYS" ]; then
            for key in $STREAM_KEYS; do
                vid=$(echo "$key" | sed "s|stream_state:${EVENT_ID}:||")
                log ""
                log "Vehicle: $vid"
                STREAM_STATE=$(redis_cmd GET "$key")
                echo "$STREAM_STATE" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$STREAM_STATE"
            done
        else
            log "No stream states for event $EVENT_ID (not using new state machine)"
        fi
    fi

    log_section "REDIS: Pending Commands (cmd:{event_id}:{vehicle_id}:*)"

    CMD_KEYS=$(redis_cmd KEYS "cmd:${EVENT_ID}:*")
    if [ -n "$CMD_KEYS" ]; then
        for key in $CMD_KEYS; do
            log ""
            log "Key: $key"
            CMD_DATA=$(redis_cmd GET "$key")
            echo "$CMD_DATA" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$CMD_DATA"
            TTL=$(redis_cmd TTL "$key")
            log "  TTL: ${TTL}s"
        done
    else
        log "No pending commands"
    fi

    log_section "REDIS: Last Seen Timestamps (lastseen:{event_id})"

    LASTSEEN=$(redis_cmd HGETALL "lastseen:${EVENT_ID}")
    if [ -n "$LASTSEEN" ]; then
        log "$LASTSEEN"
    else
        log "No last-seen data"
    fi
fi

# Dump API state if admin token is available
if [ -n "$ADMIN_TOKEN" ]; then
    log_section "API: Edge Status List (/production/events/{event_id}/edge-status)"

    EDGE_STATUS_RESP=$(curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
        "${API_URL}/api/v1/production/events/${EVENT_ID}/edge-status" 2>/dev/null || echo "API_ERROR")

    if [ "$EDGE_STATUS_RESP" != "API_ERROR" ]; then
        echo "$EDGE_STATUS_RESP" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$EDGE_STATUS_RESP"
    else
        log "Failed to fetch edge status from API (check auth token)"
    fi

    log_section "API: Stream States (/production/events/{event_id}/stream-states)"

    STREAM_STATES_RESP=$(curl -sf \
        "${API_URL}/api/v1/production/events/${EVENT_ID}/stream-states" 2>/dev/null || echo "API_ERROR")

    if [ "$STREAM_STATES_RESP" != "API_ERROR" ]; then
        echo "$STREAM_STATES_RESP" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$STREAM_STATES_RESP"
    else
        log "Failed to fetch stream states from API"
    fi

    log_section "API: Cameras List (/production/events/{event_id}/cameras)"

    CAMERAS_RESP=$(curl -sf \
        "${API_URL}/api/v1/production/events/${EVENT_ID}/cameras" 2>/dev/null || echo "API_ERROR")

    if [ "$CAMERAS_RESP" != "API_ERROR" ]; then
        echo "$CAMERAS_RESP" | python3 -m json.tool 2>/dev/null | tee -a "$LOG_FILE" || log "$CAMERAS_RESP"
    else
        log "Failed to fetch cameras from API"
    fi
else
    log ""
    log "ADMIN_TOKEN not set - skipping authenticated API endpoints"
fi

log_section "SUMMARY"

NOW_MS=$(date +%s%3N 2>/dev/null || python3 -c "import time; print(int(time.time()*1000))")

# Calculate stale threshold (30 seconds)
STALE_THRESHOLD=30000

if [ "$REDIS_AVAILABLE" = true ]; then
    EDGE_SET=$(redis_cmd SMEMBERS "edges:${EVENT_ID}")
    ONLINE_COUNT=0
    STREAMING_COUNT=0

    for vid in $EDGE_SET; do
        EDGE_STATUS=$(redis_cmd GET "edge:${EVENT_ID}:${vid}")
        if [ -n "$EDGE_STATUS" ]; then
            ONLINE_COUNT=$((ONLINE_COUNT + 1))

            # Check if streaming
            IS_STREAMING=$(echo "$EDGE_STATUS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('streaming_status',''))" 2>/dev/null || echo "")
            if [ "$IS_STREAMING" = "live" ]; then
                STREAMING_COUNT=$((STREAMING_COUNT + 1))
            fi
        fi
    done

    log "Edges online (recent heartbeat): $ONLINE_COUNT"
    log "Edges streaming: $STREAMING_COUNT"
fi

log ""
log "=== Dump Complete ==="
log "Log saved to: $LOG_FILE"
