#!/bin/bash
# Argus v4 - Smoke Test Script
# Quick validation of core functionality

set -e

API_URL="${API_URL:-http://localhost:8000}"
WEB_URL="${WEB_URL:-http://localhost:5173}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
WARNINGS=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

echo "=== Argus v4 Smoke Tests ==="
echo "API: $API_URL"
echo "Web: $WEB_URL"
echo ""

# API Health Check
echo "--- API Tests ---"
if curl -sf "${API_URL}/health" > /dev/null 2>&1; then
    pass "API health endpoint"
else
    fail "API health endpoint unreachable"
fi

# Events endpoint
if curl -sf "${API_URL}/api/v1/events" > /dev/null 2>&1; then
    pass "Events list endpoint"
else
    fail "Events list endpoint"
fi

# Check for active events
EVENTS=$(curl -sf "${API_URL}/api/v1/events" 2>/dev/null || echo "[]")
EVENT_COUNT=$(echo "$EVENTS" | grep -o '"event_id"' | wc -l)
if [ "$EVENT_COUNT" -gt 0 ]; then
    pass "Found $EVENT_COUNT event(s)"

    # Get first event ID for further tests
    EVENT_ID=$(echo "$EVENTS" | grep -o '"event_id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -n "$EVENT_ID" ]; then
        # Test positions endpoint
        if curl -sf "${API_URL}/api/v1/events/${EVENT_ID}/positions/latest" > /dev/null 2>&1; then
            pass "Positions endpoint for event $EVENT_ID"
        else
            fail "Positions endpoint for event $EVENT_ID"
        fi

        # Test leaderboard endpoint
        if curl -sf "${API_URL}/api/v1/events/${EVENT_ID}/leaderboard" > /dev/null 2>&1; then
            pass "Leaderboard endpoint for event $EVENT_ID"
        else
            fail "Leaderboard endpoint for event $EVENT_ID"
        fi

        # Test SSE stream (just check if it accepts connection)
        if timeout 2 curl -sf "${API_URL}/api/v1/events/${EVENT_ID}/stream" > /dev/null 2>&1; then
            pass "SSE stream endpoint"
        else
            # SSE may timeout, that's OK
            warn "SSE stream timeout (may be normal)"
        fi
    fi
else
    warn "No events found - some tests skipped"
fi

# Web Frontend
echo ""
echo "--- Web Tests ---"
if curl -sf "${WEB_URL}" > /dev/null 2>&1; then
    pass "Web frontend accessible"
else
    fail "Web frontend unreachable"
fi

# Check for key frontend routes
for route in "/events" "/control-room" "/team"; do
    if curl -sf "${WEB_URL}${route}" > /dev/null 2>&1; then
        pass "Route ${route}"
    else
        warn "Route ${route} may require auth or doesn't exist"
    fi
done

# Edge device tests (if running on edge)
echo ""
echo "--- Edge Tests ---"
if systemctl is-active --quiet argus-gps 2>/dev/null; then
    pass "argus-gps service running"
else
    warn "argus-gps not running (not on edge device?)"
fi

if systemctl is-active --quiet argus-uplink 2>/dev/null; then
    pass "argus-uplink service running"
else
    warn "argus-uplink not running"
fi

if systemctl is-active --quiet argus-dashboard 2>/dev/null; then
    pass "argus-dashboard service running"
else
    warn "argus-dashboard not running"
fi

# GPS device check
if [ -e /dev/argus_gps ]; then
    pass "GPS device symlink exists"
else
    warn "GPS device symlink not found"
fi

# Summary
echo ""
echo "=== Summary ==="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Some tests failed. Check logs for details."
    exit 1
fi

echo ""
echo "Smoke tests completed."
