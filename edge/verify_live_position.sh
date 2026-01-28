#!/bin/bash
#
# Live Vehicle Position Verification Script
#
# Tests the live position tracking on the course map:
# - Vehicle marker with heading
# - GPS stale detection
# - Course progress calculation
# - Test mode simulation
#
# Usage: bash verify_live_position.sh [DASHBOARD_URL]
#
# Example:
#   bash verify_live_position.sh                          # Uses localhost:8080
#   bash verify_live_position.sh http://192.168.0.18:8080 # Uses edge IP
#

DASHBOARD_URL="${1:-http://localhost:8080}"

echo "========================================"
echo "  Live Vehicle Position Verification"
echo "========================================"
echo ""
echo "Dashboard URL: $DASHBOARD_URL"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# ========================================
# Test 1: Check telemetry includes GPS fields
# ========================================
echo "Test 1: Telemetry API includes GPS fields"
echo "------------------------------------------"
RESPONSE=$(curl -s "$DASHBOARD_URL/api/telemetry/current" 2>&1)

if echo "$RESPONSE" | grep -q '"lat"'; then
    pass "Telemetry includes lat field"
else
    fail "Telemetry missing lat field"
fi

if echo "$RESPONSE" | grep -q '"lon"'; then
    pass "Telemetry includes lon field"
else
    fail "Telemetry missing lon field"
fi

if echo "$RESPONSE" | grep -q '"heading_deg"'; then
    pass "Telemetry includes heading_deg field"
else
    fail "Telemetry missing heading_deg field"
fi

if echo "$RESPONSE" | grep -q '"gps_ts_ms"'; then
    pass "Telemetry includes gps_ts_ms field"
else
    fail "Telemetry missing gps_ts_ms field"
fi

if echo "$RESPONSE" | grep -q '"satellites"'; then
    pass "Telemetry includes satellites field"
else
    fail "Telemetry missing satellites field"
fi

if echo "$RESPONSE" | grep -q '"hdop"'; then
    pass "Telemetry includes hdop field"
else
    fail "Telemetry missing hdop field"
fi
echo ""

# ========================================
# Test 2: Check dashboard HTML includes map
# ========================================
echo "Test 2: Dashboard includes map components"
echo "------------------------------------------"
RESPONSE=$(curl -s "$DASHBOARD_URL/" 2>&1)

if echo "$RESPONSE" | grep -q "courseMap"; then
    pass "Dashboard includes courseMap container"
else
    fail "Dashboard missing courseMap container"
fi

if echo "$RESPONSE" | grep -q "vehicleMarker"; then
    pass "Dashboard includes vehicleMarker reference"
else
    fail "Dashboard missing vehicleMarker reference"
fi

if echo "$RESPONSE" | grep -q "gpsStaleWarning"; then
    pass "Dashboard includes GPS stale warning element"
else
    fail "Dashboard missing GPS stale warning element"
fi

if echo "$RESPONSE" | grep -q "gpsTestModeBtn"; then
    pass "Dashboard includes GPS test mode button"
else
    fail "Dashboard missing GPS test mode button"
fi

if echo "$RESPONSE" | grep -q "courseHeading"; then
    pass "Dashboard includes heading display"
else
    fail "Dashboard missing heading display"
fi
echo ""

# ========================================
# Test 3: Check Leaflet.js is loaded
# ========================================
echo "Test 3: Leaflet.js resources"
echo "-----------------------------"
if echo "$RESPONSE" | grep -q "leaflet.js"; then
    pass "Leaflet.js script included"
else
    fail "Leaflet.js script not included"
fi

if echo "$RESPONSE" | grep -q "leaflet.css"; then
    pass "Leaflet.css stylesheet included"
else
    fail "Leaflet.css stylesheet not included"
fi
echo ""

# ========================================
# Test 4: Check vehicle marker functions
# ========================================
echo "Test 4: Vehicle marker functions"
echo "---------------------------------"
if echo "$RESPONSE" | grep -q "createVehicleMarkerHtml"; then
    pass "createVehicleMarkerHtml function defined"
else
    fail "createVehicleMarkerHtml function missing"
fi

if echo "$RESPONSE" | grep -q "updateCoursePosition"; then
    pass "updateCoursePosition function defined"
else
    fail "updateCoursePosition function missing"
fi

if echo "$RESPONSE" | grep -q "checkGpsStale"; then
    pass "checkGpsStale function defined"
else
    fail "checkGpsStale function missing"
fi
echo ""

# ========================================
# Test 5: Check test mode functions
# ========================================
echo "Test 5: GPS Test Mode functions"
echo "--------------------------------"
if echo "$RESPONSE" | grep -q "toggleGpsTestMode"; then
    pass "toggleGpsTestMode function defined"
else
    fail "toggleGpsTestMode function missing"
fi

if echo "$RESPONSE" | grep -q "runGpsTestTick"; then
    pass "runGpsTestTick function defined"
else
    fail "runGpsTestTick function missing"
fi

if echo "$RESPONSE" | grep -q "gpsTestMode"; then
    pass "gpsTestMode variable defined"
else
    fail "gpsTestMode variable missing"
fi
echo ""

# ========================================
# Summary
# ========================================
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "Architecture:"
echo "  Source: GPS ZMQ stream -> Dashboard -> SSE -> Frontend"
echo "  Update Rate: ~1 Hz (from GPS service)"
echo ""
echo "Features Implemented:"
echo "  ✓ Vehicle marker with heading arrow (rotates with direction)"
echo "  ✓ Speed display on marker (shows mph)"
echo "  ✓ GPS stale detection (5 second threshold)"
echo "  ✓ Stale warning banner (red, pulsing)"
echo "  ✓ Heading display in GPS info section"
echo "  ✓ Course progress calculation (snap to polyline)"
echo "  ✓ Test mode for simulated GPS along course"
echo ""
echo "GPS Data Fields:"
echo "  - lat, lon: Current position"
echo "  - heading_deg: Direction of travel (0-360, 0=North)"
echo "  - gps_ts_ms: Timestamp of last GPS fix"
echo "  - satellites: Number of satellites"
echo "  - hdop: Horizontal accuracy estimate"
echo ""
echo "Test Mode Usage:"
echo "  1. Load a GPX course file"
echo "  2. Click '🧪 Test' button in Current Position card"
echo "  3. Vehicle marker will move along course at ~45 mph"
echo "  4. Click '⏹️ Stop' to end test mode"
echo ""
echo "Manual Verification Checklist:"
echo "  [ ] Load dashboard in browser"
echo "  [ ] Upload a GPX course file"
echo "  [ ] Enable test mode with '🧪 Test' button"
echo "  [ ] Verify vehicle marker appears on map"
echo "  [ ] Verify marker arrow rotates with heading"
echo "  [ ] Verify speed label shows on marker"
echo "  [ ] Verify progress bar updates as vehicle moves"
echo "  [ ] Verify heading degrees update in GPS info"
echo "  [ ] Stop test mode, wait 6+ seconds"
echo "  [ ] Verify GPS STALE warning appears"
echo "  [ ] Verify marker turns red when stale"
echo ""
