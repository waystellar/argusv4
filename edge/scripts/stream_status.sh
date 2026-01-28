#!/bin/bash
#
# Argus Stream Status
#
# Shows the current YouTube stream supervisor state.
# Reads /opt/argus/state/stream_status.json written by the video director.
#
# Usage:
#   scripts/stream_status.sh          # Human-friendly summary
#   scripts/stream_status.sh --json   # Raw JSON
#
# States:
#   idle     - No stream configured
#   starting - FFmpeg launching
#   active   - Stream healthy
#   error    - FFmpeg exited unexpectedly
#   retrying - Waiting before retry (backoff)
#   paused   - Gave up; manual restart needed
#
# Created by EDGE-6: YouTube Stream Supervisor

set -u

STATUS_FILE="/opt/argus/state/stream_status.json"
MODE="${1:-summary}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ ! -f "$STATUS_FILE" ]]; then
    echo "Stream status file not found: $STATUS_FILE"
    echo "The argus-video service may not have started yet."
    exit 1
fi

# Check staleness
FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$STATUS_FILE" 2>/dev/null || stat -f %m "$STATUS_FILE" 2>/dev/null || echo 0) ))
if [[ $FILE_AGE -gt 60 ]]; then
    echo -e "${YELLOW}WARNING: Status file is ${FILE_AGE}s old (stale)${NC}"
fi

if [[ "$MODE" == "--json" ]]; then
    cat "$STATUS_FILE"
    exit 0
fi

# Parse JSON fields using python3 (available on edge devices)
read_field() {
    python3 -c "import sys,json; d=json.load(open('$STATUS_FILE')); print(d.get('$1',''))" 2>/dev/null
}

STATE=$(read_field state)
CAMERA=$(read_field camera)
PID=$(read_field pid)
RESTART_COUNT=$(read_field restart_count)
TOTAL_RESTARTS=$(read_field total_restarts)
AUTH_FAILS=$(read_field auth_failure_count)
LAST_ERROR=$(read_field last_error)
NEXT_RETRY=$(read_field next_retry_time)
BACKOFF=$(read_field backoff_delay_s)
YT_KEY_SET=$(read_field youtube_key_set)

echo "=============================="
echo "  Argus Stream Status"
echo "=============================="

# State with color
case "$STATE" in
    active)
        echo -e "  State:    ${GREEN}ACTIVE${NC}"
        ;;
    retrying)
        echo -e "  State:    ${YELLOW}RETRYING${NC}"
        ;;
    paused)
        echo -e "  State:    ${RED}PAUSED${NC} (manual restart needed)"
        ;;
    error)
        echo -e "  State:    ${RED}ERROR${NC}"
        ;;
    idle)
        echo -e "  State:    ${CYAN}IDLE${NC}"
        ;;
    starting)
        echo -e "  State:    ${CYAN}STARTING${NC}"
        ;;
    *)
        echo -e "  State:    $STATE"
        ;;
esac

echo "  Camera:   ${CAMERA:-none}"

if [[ -n "$PID" && "$PID" != "None" && "$PID" != "null" ]]; then
    echo "  PID:      $PID"
fi

echo "  YT Key:   $([ "$YT_KEY_SET" = "True" ] && echo 'configured' || echo 'NOT SET')"
echo ""

if [[ "$RESTART_COUNT" -gt 0 || "$TOTAL_RESTARTS" -gt 0 ]]; then
    echo "  Restarts: $RESTART_COUNT consecutive / $TOTAL_RESTARTS total"
fi

if [[ "$AUTH_FAILS" -gt 0 ]]; then
    echo -e "  Auth failures: ${RED}$AUTH_FAILS${NC}"
fi

if [[ "$STATE" == "retrying" && -n "$NEXT_RETRY" && "$NEXT_RETRY" != "None" && "$NEXT_RETRY" != "null" ]]; then
    NOW=$(date +%s)
    RETRY_IN=$(python3 -c "import time; print(max(0, int(float('$NEXT_RETRY') - time.time())))" 2>/dev/null || echo "?")
    echo "  Next retry in: ${RETRY_IN}s (backoff=${BACKOFF}s)"
fi

if [[ -n "$LAST_ERROR" && "$LAST_ERROR" != "" ]]; then
    echo ""
    echo "  Last error:"
    # Truncate to 120 chars for readability
    echo "    ${LAST_ERROR:0:120}"
fi

echo ""
echo "=============================="

# Exit code matches stream health
case "$STATE" in
    active)  exit 0 ;;
    idle)    exit 0 ;;
    paused)  exit 2 ;;
    *)       exit 1 ;;
esac
