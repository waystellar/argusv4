#!/bin/bash
#
# Argus Edge Status Aggregator
#
# Single-command readiness signal: OPERATIONAL / DEGRADED / DOWN
# Writes structured JSON to /opt/argus/state/edge_status.json
# and prints a one-line summary to stdout.
#
# "OPERATIONAL" = all Tier 1 checks pass for this invocation.
# "DEGRADED"    = Tier 1 passes but some Tier 2 items are down.
# "DOWN"        = one or more Tier 1 failures.
#
# Tier 1 (must have):
#   - Device provisioned
#   - Dashboard reachable (HTTP 200)
#   - GPS service active
#   - Uplink service active
#   - Config file present
#
# Tier 2 (should have):
#   - CAN setup completed
#   - CAN telemetry service active
#   - ANT+ service active
#   - Video director active
#   - At least one camera
#
# Usage:
#   scripts/edge_status.sh          # prints one-line + writes JSON
#   scripts/edge_status.sh --json   # prints full JSON to stdout
#   scripts/edge_status.sh --quiet  # no stdout, only writes JSON file
#
# Exit codes:
#   0 - OPERATIONAL (Tier 1 all pass)
#   1 - DOWN (Tier 1 failure)
#   2 - DEGRADED (Tier 1 OK, Tier 2 partial)
#
# Created by EDGE-4: Readiness Aggregation

set -u

MODE="summary"
if [[ "${1:-}" == "--json" ]]; then
    MODE="json"
elif [[ "${1:-}" == "--quiet" ]]; then
    MODE="quiet"
fi

STATE_DIR="/opt/argus/state"
STATE_FILE="${STATE_DIR}/edge_status.json"
DASHBOARD_PORT="${ARGUS_DASHBOARD_PORT:-8080}"

# Ensure state directory exists
mkdir -p "$STATE_DIR" 2>/dev/null || true

# ---- Tier 1 Checks ----
T1_FAILS=""
T1_PASS=""

# Provisioned
if [ -f /etc/argus/.provisioned ]; then
    T1_PASS="${T1_PASS}provisioned,"
else
    T1_FAILS="${T1_FAILS}not_provisioned,"
fi

# Config
if [ -s /etc/argus/config.env ]; then
    T1_PASS="${T1_PASS}config_present,"
else
    T1_FAILS="${T1_FAILS}config_missing,"
fi

# Dashboard reachable
if curl -sf -o /dev/null -m 2 "http://localhost:${DASHBOARD_PORT}/" 2>/dev/null; then
    T1_PASS="${T1_PASS}dashboard_reachable,"
else
    T1_FAILS="${T1_FAILS}dashboard_unreachable,"
fi

# GPS service
if systemctl is-active argus-gps > /dev/null 2>&1; then
    T1_PASS="${T1_PASS}gps_active,"
else
    T1_FAILS="${T1_FAILS}gps_down,"
fi

# Uplink service
if systemctl is-active argus-uplink > /dev/null 2>&1; then
    T1_PASS="${T1_PASS}uplink_active,"
else
    T1_FAILS="${T1_FAILS}uplink_down,"
fi

# ---- Tier 2 Checks ----
T2_FAILS=""
T2_PASS=""

# CAN setup
if systemctl is-active argus-can-setup > /dev/null 2>&1; then
    T2_PASS="${T2_PASS}can_setup,"
else
    T2_FAILS="${T2_FAILS}can_setup_inactive,"
fi

# CAN telemetry
if systemctl is-active argus-can > /dev/null 2>&1; then
    T2_PASS="${T2_PASS}can_active,"
else
    T2_FAILS="${T2_FAILS}can_down,"
fi

# ANT+
if systemctl is-active argus-ant > /dev/null 2>&1; then
    T2_PASS="${T2_PASS}ant_active,"
else
    T2_FAILS="${T2_FAILS}ant_down,"
fi

# Video
if systemctl is-active argus-video > /dev/null 2>&1; then
    T2_PASS="${T2_PASS}video_active,"
else
    T2_FAILS="${T2_FAILS}video_down,"
fi

# Cameras
CAMERA_COUNT=$(ls /dev/video* 2>/dev/null | wc -l)
if [ "$CAMERA_COUNT" -ge 1 ]; then
    T2_PASS="${T2_PASS}cameras_detected,"
else
    T2_FAILS="${T2_FAILS}no_cameras,"
fi

# ---- Determine Overall Status ----
NOW_ISO=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')
NOW_EPOCH=$(date +%s)

if [ -z "$T1_FAILS" ]; then
    if [ -z "$T2_FAILS" ]; then
        STATUS="OPERATIONAL"
        EXIT_CODE=0
    else
        STATUS="DEGRADED"
        EXIT_CODE=2
    fi
else
    STATUS="DOWN"
    EXIT_CODE=1
fi

# Remove trailing commas
T1_FAILS="${T1_FAILS%,}"
T1_PASS="${T1_PASS%,}"
T2_FAILS="${T2_FAILS%,}"
T2_PASS="${T2_PASS%,}"

# Build JSON (portable — no jq dependency)
# Convert comma-separated to JSON array
to_json_array() {
    local items="$1"
    if [ -z "$items" ]; then
        echo "[]"
        return
    fi
    local result="["
    local first=true
    IFS=',' read -ra PARTS <<< "$items"
    for part in "${PARTS[@]}"; do
        if $first; then
            first=false
        else
            result="${result},"
        fi
        result="${result}\"${part}\""
    done
    result="${result}]"
    echo "$result"
}

# Note: JSON arrays built after EDGE-5 disk check (below)

# EDGE-6: Read stream supervisor state
STREAM_STATE="unknown"
STREAM_STATUS_FILE="${STATE_DIR}/stream_status.json"
if [ -f "$STREAM_STATUS_FILE" ]; then
    STREAM_STATE=$(python3 -c "import json; print(json.load(open('$STREAM_STATUS_FILE')).get('state','unknown'))" 2>/dev/null || echo "unknown")
fi

# Read previous status for transition tracking
PREV_STATUS=""
if [ -f "$STATE_FILE" ]; then
    PREV_STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('status',''))" 2>/dev/null || echo "")
fi

# Read boot timing if available
BOOT_TS=""
TIME_TO_OPERATIONAL=""
BOOT_TIMING_FILE="${STATE_DIR}/boot_timing.json"
if [ -f "$BOOT_TIMING_FILE" ]; then
    BOOT_TS=$(python3 -c "import json; print(json.load(open('$BOOT_TIMING_FILE')).get('boot_epoch',''))" 2>/dev/null || echo "")
    TIME_TO_OPERATIONAL=$(python3 -c "import json; print(json.load(open('$BOOT_TIMING_FILE')).get('time_to_operational_sec',''))" 2>/dev/null || echo "")
fi

# EDGE-5: Disk usage percentage
DISK_PCT=$(df /opt/argus 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
DISK_PCT="${DISK_PCT:-0}"
# Critical disk = Tier 1 failure
if [ "$DISK_PCT" -ge 95 ] 2>/dev/null; then
    if [ -n "$T1_FAILS" ]; then
        T1_FAILS="${T1_FAILS},disk_critical"
    else
        T1_FAILS="disk_critical"
    fi
fi

# EDGE-5: Queue depth and byte size from state file
QUEUE_DEPTH=0
QUEUE_MB="0.0"
QUEUE_STATUS_FILE="${STATE_DIR}/queue_status.json"
if [ -f "$QUEUE_STATUS_FILE" ]; then
    QUEUE_DEPTH=$(python3 -c "import json; print(json.load(open('$QUEUE_STATUS_FILE')).get('depth',0))" 2>/dev/null || echo "0")
    QUEUE_MB=$(python3 -c "import json; print(json.load(open('$QUEUE_STATUS_FILE')).get('db_mb',0))" 2>/dev/null || echo "0.0")
fi

# Re-evaluate status after EDGE-5 disk check
# (T1_FAILS may have changed if disk_critical was added)
if [ -z "$T1_FAILS" ]; then
    if [ -z "$T2_FAILS" ]; then
        STATUS="OPERATIONAL"
        EXIT_CODE=0
    else
        STATUS="DEGRADED"
        EXIT_CODE=2
    fi
else
    STATUS="DOWN"
    EXIT_CODE=1
fi

# Remove trailing commas (re-run after EDGE-5 additions)
T1_FAILS="${T1_FAILS%,}"
T1_PASS="${T1_PASS%,}"
T2_FAILS="${T2_FAILS%,}"
T2_PASS="${T2_PASS%,}"

T1_FAILS_JSON=$(to_json_array "$T1_FAILS")
T1_PASS_JSON=$(to_json_array "$T1_PASS")
T2_FAILS_JSON=$(to_json_array "$T2_FAILS")
T2_PASS_JSON=$(to_json_array "$T2_PASS")

JSON=$(cat <<ENDJSON
{
  "status": "${STATUS}",
  "timestamp": "${NOW_ISO}",
  "epoch": ${NOW_EPOCH},
  "tier1": {
    "pass": ${T1_PASS_JSON},
    "fail": ${T1_FAILS_JSON}
  },
  "tier2": {
    "pass": ${T2_PASS_JSON},
    "fail": ${T2_FAILS_JSON}
  },
  "cameras_detected": ${CAMERA_COUNT},
  "stream_state": "${STREAM_STATE}",
  "disk_pct": ${DISK_PCT},
  "queue_depth": ${QUEUE_DEPTH},
  "queue_mb": ${QUEUE_MB},
  "previous_status": "${PREV_STATUS}",
  "boot_epoch": "${BOOT_TS}",
  "time_to_operational_sec": "${TIME_TO_OPERATIONAL}"
}
ENDJSON
)

# Write JSON to state file
echo "$JSON" > "$STATE_FILE" 2>/dev/null || true

# Output
case "$MODE" in
    json)
        echo "$JSON"
        ;;
    summary)
        REASON=""
        if [ "$STATUS" = "DOWN" ]; then
            REASON=" [Tier 1 failures: ${T1_FAILS}]"
        elif [ "$STATUS" = "DEGRADED" ]; then
            REASON=" [Tier 2 degraded: ${T2_FAILS}]"
        fi
        echo "${STATUS}${REASON}"
        ;;
    quiet)
        # No output
        ;;
esac

exit $EXIT_CODE
