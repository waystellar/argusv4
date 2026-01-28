#!/bin/bash
#
# Fan Standings Smoke Test
#
# Verifies that the leaderboard endpoint returns registered entrants
# even when no telemetry/checkpoint data exists.
#
# Usage:
#   scripts/fan_standings_smoke.sh                          # Default host
#   scripts/fan_standings_smoke.sh http://192.168.0.19      # Custom host
#   scripts/fan_standings_smoke.sh http://localhost evt_abc  # Custom host + event
#
# Exit codes:
#   0 - Standings endpoint works and returns entrants
#   1 - Issue found

set -euo pipefail

BASE_URL="${1:-http://localhost}"
EVENT_ID="${2:-}"
API_URL="${BASE_URL}/api/v1"
FAIL=0

echo "==============================="
echo "  Argus Fan Standings Smoke Test"
echo "==============================="
echo "  API: ${API_URL}"
echo ""

# 1. If no event ID given, find one
if [ -z "$EVENT_ID" ]; then
    echo "Step 1: Finding an event..."
    EVENTS_JSON=$(curl -sf "${API_URL}/events" 2>/dev/null || echo "")
    if [ -z "$EVENTS_JSON" ]; then
        echo "  FAIL: Could not reach ${API_URL}/events"
        echo "  (Is the API server running?)"
        exit 1
    fi

    EVENT_ID=$(echo "$EVENTS_JSON" | python3 -c "
import sys, json
events = json.load(sys.stdin)
if events:
    # Prefer in_progress, then any
    for e in events:
        if e.get('status') == 'in_progress':
            print(e['event_id'])
            sys.exit(0)
    print(events[0]['event_id'])
else:
    print('')
" 2>/dev/null || echo "")

    if [ -z "$EVENT_ID" ]; then
        echo "  SKIP: No events found. Create an event first."
        echo "==============================="
        echo "  SKIP: No events to test"
        echo "==============================="
        exit 0
    fi
    echo "  Using event: $EVENT_ID"
else
    echo "Step 1: Using provided event: $EVENT_ID"
fi

# 2. Fetch event details
echo ""
echo "Step 2: Fetching event details..."
EVENT_JSON=$(curl -sf "${API_URL}/events/${EVENT_ID}" 2>/dev/null || echo "")
if [ -z "$EVENT_JSON" ]; then
    echo "  FAIL: Could not fetch event ${EVENT_ID}"
    exit 1
fi

VEHICLE_COUNT=$(echo "$EVENT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('vehicle_count',0))" 2>/dev/null || echo "0")
EVENT_NAME=$(echo "$EVENT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name','?'))" 2>/dev/null || echo "?")
echo "  Event: $EVENT_NAME"
echo "  Registered vehicles: $VEHICLE_COUNT"

# 3. Fetch leaderboard
echo ""
echo "Step 3: Fetching leaderboard..."
LB_JSON=$(curl -sf "${API_URL}/events/${EVENT_ID}/leaderboard" 2>/dev/null || echo "")
if [ -z "$LB_JSON" ]; then
    echo "  FAIL: Could not fetch leaderboard for ${EVENT_ID}"
    exit 1
fi

ENTRY_COUNT=$(echo "$LB_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('entries',[])))" 2>/dev/null || echo "0")
echo "  Leaderboard entries: $ENTRY_COUNT"

# 4. Verify entrants appear
echo ""
echo "Step 4: Verifying entrants..."
if [ "$VEHICLE_COUNT" -eq 0 ]; then
    echo "  SKIP: No vehicles registered — nothing to verify"
    echo "  (Register vehicles for the event to test standings)"
elif [ "$ENTRY_COUNT" -eq 0 ]; then
    echo "  FAIL: $VEHICLE_COUNT vehicles registered but 0 entries in leaderboard"
    FAIL=1
elif [ "$ENTRY_COUNT" -ge "$VEHICLE_COUNT" ]; then
    echo "  PASS: All $VEHICLE_COUNT registered vehicles appear in leaderboard ($ENTRY_COUNT entries)"
else
    echo "  WARN: $VEHICLE_COUNT registered but only $ENTRY_COUNT in leaderboard (some may be hidden)"
fi

# 5. Check for "Not Started" entries
if [ "$ENTRY_COUNT" -gt 0 ]; then
    echo ""
    echo "Step 5: Checking for 'Not Started' entries..."
    NOT_STARTED=$(echo "$LB_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ns = [e for e in data.get('entries',[]) if e.get('last_checkpoint') == 0]
print(len(ns))
for e in ns[:3]:
    print(f\"  #{e['vehicle_number']} {e['team_name']} — {e.get('last_checkpoint_name','?')}\")
" 2>/dev/null || echo "0")
    echo "  Not Started entries: $(echo "$NOT_STARTED" | head -1)"
    echo "$NOT_STARTED" | tail -n +2
fi

echo ""
echo "==============================="
if [ $FAIL -eq 0 ]; then
    echo "  PASS: Fan standings smoke test passed"
else
    echo "  FAIL: Fan standings smoke test failed"
fi
echo "==============================="

exit $FAIL
