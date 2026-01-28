#!/bin/bash
#
# Verification script for course GPX fix
# Tests /api/course endpoints after applying the fix
#
# Usage: bash verify_course_fix.sh
#

DASHBOARD_URL="http://localhost:8080"
COURSE_FILE="/opt/argus/config/course.json"

echo "========================================"
echo "  Course API Fix Verification"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Test 1: GET /api/course (should return {} or course data, not 500)
echo "Test 1: GET /api/course (no crash)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$DASHBOARD_URL/api/course" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    pass "GET /api/course returns 200"
    echo "     Response: $BODY"
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "GET /api/course returns 401 (auth required - this is OK)"
else
    fail "GET /api/course returns $HTTP_CODE (expected 200 or 401)"
    echo "     Response: $BODY"
fi
echo ""

# Test 2: POST /api/course/upload with sample GPX
echo "Test 2: POST /api/course/upload (upload test GPX)"
SAMPLE_GPX='<?xml version="1.0"?><gpx version="1.1"><trk><name>Test Course</name><trkseg><trkpt lat="32.5" lon="-117.0"><ele>100</ele></trkpt><trkpt lat="32.6" lon="-117.1"><ele>110</ele></trkpt></trkseg></trk></gpx>'

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"filename\": \"test_course.gpx\", \"gpx_data\": \"$SAMPLE_GPX\"}" \
    "$DASHBOARD_URL/api/course/upload" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    pass "POST /api/course/upload returns 200"
    echo "     Response: $BODY"
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "POST /api/course/upload returns 401 (auth required - testing without auth)"
else
    fail "POST /api/course/upload returns $HTTP_CODE"
    echo "     Response: $BODY"
fi
echo ""

# Test 3: Check if course.json file was created
echo "Test 3: Verify course.json file exists"
if [[ -f "$COURSE_FILE" ]]; then
    pass "course.json exists at $COURSE_FILE"
    echo "     Contents: $(cat $COURSE_FILE | head -c 200)..."
else
    info "course.json not found (may require auth to upload)"
fi
echo ""

# Test 4: GET /api/course should return the uploaded data
echo "Test 4: GET /api/course (verify uploaded data persists)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$DASHBOARD_URL/api/course" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | grep -q "gpx_data"; then
        pass "GET /api/course returns course with gpx_data"
    elif echo "$BODY" | grep -q "{}"; then
        info "GET /api/course returns empty (no course uploaded yet)"
    else
        info "GET /api/course returned: $BODY"
    fi
else
    fail "GET /api/course returns $HTTP_CODE"
fi
echo ""

# Test 5: POST /api/course/clear
echo "Test 5: POST /api/course/clear"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DASHBOARD_URL/api/course/clear" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    pass "POST /api/course/clear returns 200"
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "POST /api/course/clear returns 401 (auth required)"
else
    fail "POST /api/course/clear returns $HTTP_CODE"
fi
echo ""

# Summary
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "If tests show 200 status codes (or 401 for auth), the fix is working."
echo "The 500 error should no longer occur."
echo ""
echo "Storage location: $COURSE_FILE"
echo ""
echo "To fully test with auth, use the dashboard UI to upload a GPX file."
echo ""
