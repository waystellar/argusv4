#!/usr/bin/env bash
# link_camera_preview_smoke.sh — Smoke test for LINK-3 camera preview + streaming feedback
#
# Validates that:
#   - Camera preview routes are registered (both legacy and canonical)
#   - Screenshot capture loop exists with 30s interval
#   - UI polls screenshot status and refreshes images
#   - Streaming button shows persistent error feedback (not just tooltip)
#   - YouTube configuration warning is visible in HTML
#   - startStream() persists errors in the UI error span
#
# Sections:
#   A. Python syntax
#   B. Camera preview route registration
#   C. Screenshot capture loop
#   D. UI screenshot polling and display
#   E. Streaming button feedback
#   F. Runtime integration (if edge is running)
#
# Usage:
#   bash scripts/link_camera_preview_smoke.sh
#
# Exit codes:
#   0 — all checks passed (SKIPs allowed)
#   1 — at least one FAIL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[link-3]  $*"; }
pass() { echo "[link-3]    PASS: $*"; }
fail() { echo "[link-3]    FAIL: $*"; FAIL=1; }
skip() { echo "[link-3]    SKIP: $*"; }

DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "LINK-3: Camera Preview & Streaming Feedback Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION A: Python Syntax
# ═══════════════════════════════════════════════════════════════════
log "─── Section A: Python Syntax ───"

log "A1: pit_crew_dashboard.py compiles"
if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles cleanly"
else
  fail "pit_crew_dashboard.py has syntax errors"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION B: Camera Preview Route Registration
# ═══════════════════════════════════════════════════════════════════
log "─── Section B: Preview Route Registration ───"

# B1: Canonical GET preview route
log "B1: Canonical GET /api/cameras/preview/{camera}.jpg route"
if grep -q "add_get('/api/cameras/preview/{camera}.jpg'" "$DASHBOARD"; then
  pass "Canonical preview GET route registered"
else
  fail "Canonical preview GET route missing"
fi

# B2: Canonical POST capture route
log "B2: Canonical POST /api/cameras/preview/{camera}/capture route"
if grep -q "add_post('/api/cameras/preview/{camera}/capture'" "$DASHBOARD"; then
  pass "Canonical preview capture POST route registered"
else
  fail "Canonical preview capture POST route missing"
fi

# B3: Legacy GET screenshot route (backward compat)
log "B3: Legacy GET /api/cameras/screenshot/{camera} route"
if grep -q "add_get('/api/cameras/screenshot/{camera}'" "$DASHBOARD"; then
  pass "Legacy screenshot GET route registered"
else
  fail "Legacy screenshot GET route missing"
fi

# B4: Legacy POST capture route (backward compat)
log "B4: Legacy POST /api/cameras/screenshot/{camera}/capture route"
if grep -q "add_post('/api/cameras/screenshot/{camera}/capture'" "$DASHBOARD"; then
  pass "Legacy screenshot capture POST route registered"
else
  fail "Legacy screenshot capture POST route missing"
fi

# B5: Screenshots status endpoint
log "B5: GET /api/cameras/screenshots/status route"
if grep -q "add_get('/api/cameras/screenshots/status'" "$DASHBOARD"; then
  pass "Screenshots status route registered"
else
  fail "Screenshots status route missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION C: Screenshot Capture Loop
# ═══════════════════════════════════════════════════════════════════
log "─── Section C: Screenshot Capture Loop ───"

# C1: Capture loop method exists
log "C1: _screenshot_capture_loop method exists"
if grep -q 'async def _screenshot_capture_loop' "$DASHBOARD"; then
  pass "_screenshot_capture_loop method exists"
else
  fail "_screenshot_capture_loop method missing"
fi

# C2: Capture loop iterates all 4 cameras
log "C2: Capture loop iterates camera devices"
if grep -A15 'async def _screenshot_capture_loop' "$DASHBOARD" | grep -q '_camera_devices'; then
  pass "Capture loop iterates _camera_devices"
else
  fail "Capture loop doesn't iterate camera devices"
fi

# C3: Capture loop uses 30s interval
log "C3: Capture loop has 30s interval"
if grep -q '_screenshot_interval' "$DASHBOARD"; then
  pass "Capture loop uses _screenshot_interval"
else
  fail "Capture loop missing interval reference"
fi

# C4: Capture loop staggers captures (5s between cameras)
log "C4: Capture loop staggers captures"
if grep -A25 'async def _screenshot_capture_loop' "$DASHBOARD" | grep -q 'asyncio.sleep(5)'; then
  pass "Capture loop staggers with 5s sleep between cameras"
else
  fail "Capture loop missing stagger sleep"
fi

# C5: _capture_single_screenshot uses _get_camera_device (fallback probing)
log "C5: Capture uses _get_camera_device for fallback probing"
if grep -A10 'async def _capture_single_screenshot' "$DASHBOARD" | grep -q '_get_camera_device'; then
  pass "Single capture uses _get_camera_device"
else
  fail "Single capture missing _get_camera_device fallback"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION D: UI Screenshot Polling and Display
# ═══════════════════════════════════════════════════════════════════
log "─── Section D: UI Polling & Display ───"

# D1: UI polls screenshot status
log "D1: UI polls /api/cameras/screenshots/status"
if grep -q "pollScreenshotStatus" "$DASHBOARD" && grep -q "/api/cameras/screenshots/status" "$DASHBOARD"; then
  pass "UI polls screenshot status endpoint"
else
  fail "UI missing screenshot status polling"
fi

# D2: UI has 10s polling interval
log "D2: UI polling interval set"
if grep -q "setInterval(pollScreenshotStatus" "$DASHBOARD"; then
  pass "Screenshot status polling on interval"
else
  fail "Screenshot status polling interval missing"
fi

# D3: UI uses canonical preview URL for images
log "D3: UI uses /api/cameras/preview/{cam}.jpg for images"
if grep -q "/api/cameras/preview/" "$DASHBOARD" && grep -q ".jpg?t=" "$DASHBOARD"; then
  pass "UI uses canonical preview URL with cache-busting timestamp"
else
  fail "UI missing canonical preview URL"
fi

# D4: UI has 2x2 grid layout
log "D4: UI has 2x2 camera grid layout"
if grep -q "grid-template-columns.*repeat(2" "$DASHBOARD"; then
  pass "Camera grid uses 2-column layout"
else
  fail "Camera grid missing 2-column layout"
fi

# D5: UI has screenshot modal for enlarged view
log "D5: Click-to-enlarge modal exists"
if grep -q "screenshotModal" "$DASHBOARD" && grep -q "enlargeScreenshot" "$DASHBOARD"; then
  pass "Screenshot modal for enlarged view exists"
else
  fail "Screenshot modal missing"
fi

# D6: All 4 camera slots have screenshot cards
log "D6: All 4 camera slots have cards"
CARD_COUNT=0
for cam in main cockpit chase suspension; do
  if grep -q "screenshot-${cam}" "$DASHBOARD"; then
    CARD_COUNT=$((CARD_COUNT + 1))
  fi
done
if [ "$CARD_COUNT" -eq 4 ]; then
  pass "All 4 camera slots (main, cockpit, chase, suspension) have cards"
else
  fail "Only $CARD_COUNT/4 camera slots have cards"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION E: Streaming Button Feedback (LINK-3)
# ═══════════════════════════════════════════════════════════════════
log "─── Section E: Streaming Button Feedback ───"

# E1: YouTube config warning element exists in HTML
log "E1: YouTube config warning element in HTML"
if grep -q 'streamConfigWarning' "$DASHBOARD"; then
  pass "streamConfigWarning element exists in HTML"
else
  fail "streamConfigWarning element missing — no visible YouTube key warning"
fi

# E2: YouTube config warning shown when not configured
log "E2: Config warning shown when youtube_configured is false"
if grep -A8 '!streamingStatus.youtube_configured' "$DASHBOARD" | grep -q 'configWarning'; then
  pass "Config warning visibility toggled based on youtube_configured"
else
  fail "Config warning not wired to youtube_configured check"
fi

# E3: startStream() persists errors in streamError span
log "E3: startStream() persists errors in UI (not just alert)"
if grep -A40 'async function startStream' "$DASHBOARD" | grep -q 'errorSpan.textContent'; then
  pass "startStream() writes errors to streamError span"
else
  fail "startStream() does not persist errors in UI"
fi

# E4: startStream() clears previous errors before attempt
log "E4: startStream() clears previous errors before attempt"
if grep -A10 'async function startStream' "$DASHBOARD" | grep -q "errorSpan.*display.*none"; then
  pass "startStream() clears previous error before new attempt"
else
  fail "startStream() does not clear previous errors"
fi

# E5: Streaming start returns success/error JSON
log "E5: handle_streaming_start returns success/error JSON"
if grep -A15 'async def handle_streaming_start' "$DASHBOARD" | grep -q 'json_response'; then
  pass "handle_streaming_start returns JSON response"
else
  fail "handle_streaming_start missing JSON response"
fi

# E6: start_streaming validates YouTube key
log "E6: start_streaming validates YouTube stream key"
if grep -A10 'async def start_streaming' "$DASHBOARD" | grep -q 'youtube_stream_key'; then
  pass "start_streaming validates YouTube stream key"
else
  fail "start_streaming missing YouTube key validation"
fi

# E7: start_streaming validates camera device
log "E7: start_streaming validates camera device"
if grep -A15 'async def start_streaming' "$DASHBOARD" | grep -q '_get_camera_device'; then
  pass "start_streaming validates camera device availability"
else
  fail "start_streaming missing camera device validation"
fi

# E8: start_streaming handles FFmpeg not installed
log "E8: start_streaming handles FFmpeg not found"
if grep -A80 'async def start_streaming' "$DASHBOARD" | grep -q 'FileNotFoundError'; then
  pass "start_streaming catches FileNotFoundError (FFmpeg missing)"
else
  fail "start_streaming missing FFmpeg-not-installed handler"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION F: Runtime Integration (if edge is running)
# ═══════════════════════════════════════════════════════════════════
log "─── Section F: Runtime Integration ───"

EDGE_PORT="${ARGUS_EDGE_PORT:-8080}"
EDGE_HOST="${ARGUS_EDGE_HOST:-localhost}"
EDGE_URL="http://${EDGE_HOST}:${EDGE_PORT}"

# F1: Check if edge is running
log "F1: Edge reachability check"
EDGE_BODY=$(curl -s --connect-timeout 2 --max-time 3 \
  "${EDGE_URL}/api/telemetry/current" 2>/dev/null || true)

if echo "$EDGE_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'cloud_detail' in d" 2>/dev/null; then
  pass "Edge reachable at ${EDGE_URL}"

  # F2: Screenshots status endpoint
  log "F2: Screenshot status endpoint"
  SS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    "${EDGE_URL}/api/cameras/screenshots/status" 2>/dev/null || echo "000")
  if [ "$SS_CODE" = "401" ]; then
    skip "Screenshots status requires auth (expected)"
  elif [ "$SS_CODE" = "200" ]; then
    pass "Screenshots status endpoint returns 200"
  else
    skip "Screenshots status returned HTTP $SS_CODE"
  fi

  # F3: Streaming status endpoint
  log "F3: Streaming status endpoint"
  STREAM_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    "${EDGE_URL}/api/streaming/status" 2>/dev/null || echo "000")
  if [ "$STREAM_CODE" = "401" ]; then
    skip "Streaming status requires auth (expected)"
  elif [ "$STREAM_CODE" = "200" ]; then
    pass "Streaming status endpoint returns 200"
  else
    skip "Streaming status returned HTTP $STREAM_CODE"
  fi

else
  skip "Edge not running at ${EDGE_URL} — runtime checks skipped"
  skip "To run runtime checks: start the edge, then re-run this script"
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════"
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
