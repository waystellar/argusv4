#!/bin/bash
#
# Argus Edge Readiness Wait
#
# Polls edge_status.sh until OPERATIONAL (Tier 1 all green for
# STABLE_SECS consecutive seconds), or until TIMEOUT.
# Records boot-to-operational timing.
#
# Usage:
#   scripts/edge_readiness_wait.sh [timeout_secs] [stable_secs]
#
# Defaults:
#   timeout  = 180 seconds (3 minutes)
#   stable   = 10 seconds (must hold OPERATIONAL for 10s)
#
# Exit codes:
#   0 - OPERATIONAL (stable)
#   1 - TIMEOUT (never reached stable OPERATIONAL)
#   2 - DEGRADED (Tier 1 OK but Tier 2 issues, after timeout)
#
# Writes boot timing to /opt/argus/state/boot_timing.json
#
# Created by EDGE-4: Readiness Aggregation — Boot Timing

set -u

TIMEOUT="${1:-180}"
STABLE_SECS="${2:-10}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS_SCRIPT="${SCRIPT_DIR}/edge_status.sh"

STATE_DIR="/opt/argus/state"
TIMING_FILE="${STATE_DIR}/boot_timing.json"
mkdir -p "$STATE_DIR" 2>/dev/null || true

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[readiness-wait] $(date '+%H:%M:%S') $*"
}

# Record boot timestamp
BOOT_EPOCH=$(date +%s)

# Try to get actual system boot time (more accurate)
SYSTEM_BOOT_EPOCH=""
if command -v uptime > /dev/null 2>&1; then
    # On Linux, /proc/stat has boot time
    if [ -f /proc/stat ]; then
        SYSTEM_BOOT_EPOCH=$(awk '/^btime/ {print $2}' /proc/stat 2>/dev/null || echo "")
    fi
fi

if [ -n "$SYSTEM_BOOT_EPOCH" ]; then
    BOOT_EPOCH="$SYSTEM_BOOT_EPOCH"
    log "System boot time from /proc/stat: $(date -d "@$BOOT_EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$BOOT_EPOCH")"
else
    log "Using script start time as boot reference: $(date '+%Y-%m-%d %H:%M:%S')"
fi

log "Waiting for OPERATIONAL status (timeout=${TIMEOUT}s, stable=${STABLE_SECS}s)..."

ELAPSED=0
CONSECUTIVE_OK=0
POLL_INTERVAL=3
LAST_STATUS=""
FIRST_OPERATIONAL_EPOCH=""

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Run status check quietly
    STATUS_OUTPUT=$("$STATUS_SCRIPT" 2>/dev/null || echo "DOWN [script error]")
    CURRENT_STATUS=$(echo "$STATUS_OUTPUT" | awk '{print $1}')

    if [ "$CURRENT_STATUS" != "$LAST_STATUS" ]; then
        log "Status: $STATUS_OUTPUT"
        LAST_STATUS="$CURRENT_STATUS"
    fi

    if [ "$CURRENT_STATUS" = "OPERATIONAL" ]; then
        CONSECUTIVE_OK=$((CONSECUTIVE_OK + POLL_INTERVAL))
        if [ -z "$FIRST_OPERATIONAL_EPOCH" ]; then
            FIRST_OPERATIONAL_EPOCH=$(date +%s)
        fi
        if [ $CONSECUTIVE_OK -ge $STABLE_SECS ]; then
            NOW_EPOCH=$(date +%s)
            TIME_TO_OPERATIONAL=$((FIRST_OPERATIONAL_EPOCH - BOOT_EPOCH))
            TIME_TO_STABLE=$((NOW_EPOCH - BOOT_EPOCH))
            log ""
            echo -e "${GREEN}======================================${NC}"
            echo -e "${GREEN}  OPERATIONAL (stable for ${CONSECUTIVE_OK}s)${NC}"
            echo -e "${GREEN}======================================${NC}"
            log "Boot epoch:            $BOOT_EPOCH"
            log "First operational:     $FIRST_OPERATIONAL_EPOCH (+${TIME_TO_OPERATIONAL}s)"
            log "Stable operational:    $NOW_EPOCH (+${TIME_TO_STABLE}s)"

            # Write boot timing
            cat > "$TIMING_FILE" <<ENDJSON
{
  "boot_epoch": ${BOOT_EPOCH},
  "first_operational_epoch": ${FIRST_OPERATIONAL_EPOCH},
  "stable_operational_epoch": ${NOW_EPOCH},
  "time_to_operational_sec": ${TIME_TO_OPERATIONAL},
  "time_to_stable_sec": ${TIME_TO_STABLE},
  "stable_threshold_sec": ${STABLE_SECS},
  "recorded_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')"
}
ENDJSON

            # Also append to boot history log
            HISTORY_FILE="${STATE_DIR}/boot_history.log"
            echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') boot=${BOOT_EPOCH} first_op=+${TIME_TO_OPERATIONAL}s stable=+${TIME_TO_STABLE}s status=OPERATIONAL" >> "$HISTORY_FILE" 2>/dev/null || true

            # Re-run status to update the JSON file with timing
            "$STATUS_SCRIPT" --quiet 2>/dev/null || true

            exit 0
        fi
    else
        # Reset consecutive counter on non-OPERATIONAL
        if [ $CONSECUTIVE_OK -gt 0 ]; then
            log "Status dropped from OPERATIONAL → $CURRENT_STATUS (resetting stable counter)"
        fi
        CONSECUTIVE_OK=0
        FIRST_OPERATIONAL_EPOCH=""
    fi

    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# Timeout reached
NOW_EPOCH=$(date +%s)
TIME_WAITED=$((NOW_EPOCH - BOOT_EPOCH))
log ""

# Get final status
FINAL_OUTPUT=$("$STATUS_SCRIPT" 2>/dev/null || echo "DOWN [script error]")
FINAL_STATUS=$(echo "$FINAL_OUTPUT" | awk '{print $1}')

if [ "$FINAL_STATUS" = "DEGRADED" ]; then
    echo -e "${YELLOW}======================================${NC}"
    echo -e "${YELLOW}  DEGRADED (Tier 1 OK, Tier 2 partial)${NC}"
    echo -e "${YELLOW}======================================${NC}"
    log "Final: $FINAL_OUTPUT"
    EXIT_CODE=2
else
    echo -e "${RED}======================================${NC}"
    echo -e "${RED}  TIMEOUT: Not operational after ${TIMEOUT}s${NC}"
    echo -e "${RED}======================================${NC}"
    log "Final: $FINAL_OUTPUT"
    EXIT_CODE=1
fi

# Write timing even on failure
cat > "$TIMING_FILE" <<ENDJSON
{
  "boot_epoch": ${BOOT_EPOCH},
  "first_operational_epoch": ${FIRST_OPERATIONAL_EPOCH:-0},
  "stable_operational_epoch": 0,
  "time_to_operational_sec": -1,
  "time_to_stable_sec": -1,
  "stable_threshold_sec": ${STABLE_SECS},
  "final_status": "${FINAL_STATUS}",
  "timeout_sec": ${TIMEOUT},
  "recorded_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')"
}
ENDJSON

# Append to boot history log
HISTORY_FILE="${STATE_DIR}/boot_history.log"
echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') boot=${BOOT_EPOCH} waited=${TIME_WAITED}s status=${FINAL_STATUS}" >> "$HISTORY_FILE" 2>/dev/null || true

# Re-run status to update the JSON file with timing
"$STATUS_SCRIPT" --quiet 2>/dev/null || true

exit $EXIT_CODE
