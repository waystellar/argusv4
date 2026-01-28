#!/bin/bash
#
# GPX Course Persistence Verification Script
#
# Tests that course data persists correctly on the edge device
# and is accessible from multiple devices (mobile + desktop).
#
# Usage: bash verify_gpx_persistence.sh [DASHBOARD_URL]
#
# Example:
#   bash verify_gpx_persistence.sh                          # Uses localhost:8080
#   bash verify_gpx_persistence.sh http://192.168.0.18:8080 # Uses edge IP
#

DASHBOARD_URL="${1:-http://localhost:8080}"
COURSE_FILE="/opt/argus/config/course.json"

echo "========================================"
echo "  GPX Course Persistence Verification"
echo "========================================"
echo ""
echo "Dashboard URL: $DASHBOARD_URL"
echo "Storage File: $COURSE_FILE"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Sample GPX for testing
SAMPLE_GPX='<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="ArgusTest">
  <trk>
    <name>Test Course</name>
    <trkseg>
      <trkpt lat="33.7490" lon="-117.8732"><ele>100</ele></trkpt>
      <trkpt lat="33.7500" lon="-117.8740"><ele>105</ele></trkpt>
      <trkpt lat="33.7510" lon="-117.8750"><ele>110</ele></trkpt>
      <trkpt lat="33.7520" lon="-117.8760"><ele>115</ele></trkpt>
    </trkseg>
  </trk>
</gpx>'

# ========================================
# Test 1: Clear any existing course
# ========================================
echo "Test 1: Clear existing course"
echo "-----------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DASHBOARD_URL/api/course/clear" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    pass "POST /api/course/clear returns 200"
else
    fail "POST /api/course/clear returns $HTTP_CODE"
    echo "     Response: $BODY"
fi
echo ""

# ========================================
# Test 2: Verify course is cleared
# ========================================
echo "Test 2: Verify course is cleared"
echo "---------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" "$DASHBOARD_URL/api/course" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | grep -q "gpx_data"; then
        fail "Course still contains gpx_data after clear"
    else
        pass "GET /api/course returns empty object (course cleared)"
    fi
else
    fail "GET /api/course returns $HTTP_CODE"
fi
echo ""

# ========================================
# Test 3: Upload test course
# ========================================
echo "Test 3: Upload test GPX course"
echo "-------------------------------"
PAYLOAD=$(jq -n --arg fn "test_course.gpx" --arg gpx "$SAMPLE_GPX" '{filename: $fn, gpx_data: $gpx}')
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$DASHBOARD_URL/api/course/upload" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | grep -q '"success":true'; then
        pass "POST /api/course/upload returns success"
    else
        fail "POST /api/course/upload response: $BODY"
    fi
else
    fail "POST /api/course/upload returns $HTTP_CODE"
    echo "     Response: $BODY"
fi
echo ""

# ========================================
# Test 4: Verify course.json file exists
# ========================================
echo "Test 4: Verify course.json file exists"
echo "---------------------------------------"
if [[ -f "$COURSE_FILE" ]]; then
    pass "course.json exists at $COURSE_FILE"
    CONTENTS=$(cat "$COURSE_FILE" | head -c 200)
    echo "     Contents (first 200 chars): $CONTENTS..."

    # Check file has required fields
    if cat "$COURSE_FILE" | jq -e '.filename' > /dev/null 2>&1; then
        pass "course.json has 'filename' field"
    else
        fail "course.json missing 'filename' field"
    fi

    if cat "$COURSE_FILE" | jq -e '.gpx_data' > /dev/null 2>&1; then
        pass "course.json has 'gpx_data' field"
    else
        fail "course.json missing 'gpx_data' field"
    fi

    if cat "$COURSE_FILE" | jq -e '.uploaded_at' > /dev/null 2>&1; then
        pass "course.json has 'uploaded_at' timestamp"
    else
        fail "course.json missing 'uploaded_at' timestamp"
    fi
else
    fail "course.json not found at $COURSE_FILE"
    info "This may indicate a permissions issue or wrong config directory"
fi
echo ""

# ========================================
# Test 5: GET /api/course returns uploaded data
# ========================================
echo "Test 5: GET /api/course returns uploaded data"
echo "----------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" "$DASHBOARD_URL/api/course" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | grep -q "test_course.gpx"; then
        pass "GET /api/course returns uploaded filename"
    else
        fail "GET /api/course missing expected filename"
    fi

    if echo "$BODY" | grep -q "Test Course"; then
        pass "GET /api/course contains GPX content"
    else
        fail "GET /api/course missing expected GPX content"
    fi

    if echo "$BODY" | grep -q "uploaded_at"; then
        pass "GET /api/course includes upload timestamp"
    else
        fail "GET /api/course missing upload timestamp"
    fi
else
    fail "GET /api/course returns $HTTP_CODE"
fi
echo ""

# ========================================
# Test 6: Simulate "different device" access
# ========================================
echo "Test 6: Simulate different device (new session)"
echo "------------------------------------------------"
info "Fetching course without any cookies (like a new device would)"
RESPONSE=$(curl -s -w "\n%{http_code}" --no-keepalive -H "Cookie: " "$DASHBOARD_URL/api/course" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | grep -q "gpx_data"; then
        pass "Course accessible without session/cookies (cross-device works)"
    else
        fail "Course empty when accessed without cookies"
    fi
elif [[ "$HTTP_CODE" == "401" ]]; then
    fail "Course requires authentication (401) - cross-device will NOT work"
    info "Fix: Remove auth requirement from /api/course endpoints"
else
    fail "Unexpected status $HTTP_CODE"
fi
echo ""

# ========================================
# Summary
# ========================================
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "Persistence Model: Per-truck (local file on edge device)"
echo "Storage Location: $COURSE_FILE"
echo "Auth Required: NO (accessible from any device on network)"
echo ""
echo "To test cross-device persistence:"
echo "  1. On mobile: Upload GPX via $DASHBOARD_URL"
echo "  2. On desktop: Navigate to $DASHBOARD_URL"
echo "  3. Course should load automatically on desktop"
echo ""
echo "If course not appearing on second device:"
echo "  - Check that both devices hit the SAME edge IP"
echo "  - Check browser console for errors (F12 -> Console)"
echo "  - Verify: curl $DASHBOARD_URL/api/course"
echo ""
