#!/usr/bin/env bash
# edge_camera_preview_smoke.sh - Smoke test for Edge Camera Preview Grid
#
# EDGE-CAM-1: Validates that camera 2x2 grid thumbnails work end-to-end.
#
# Validates:
#   Slot Naming Consistency:
#     1.  JS updateCameraDisplay uses canonical slot names
#     2.  JS refreshAllScreenshots uses canonical slot names
#     3.  HTML grid tile IDs use canonical names (main, cockpit, chase, suspension)
#     4.  No JS arrays with legacy camera names (pov, roof, front)
#   Screenshot Endpoints:
#     5.  GET /api/cameras/screenshot/{camera} route registered
#     6.  GET /api/cameras/screenshots/status route registered
#     7.  POST /api/cameras/screenshot/{camera}/capture route registered
#   Handler Normalization:
#     8.  handle_camera_screenshot normalizes slot name
#     9.  handle_capture_screenshot normalizes slot name
#    10.  _normalize_camera_slot function exists
#    11.  _camera_aliases maps legacy names to canonical
#   Grid UI:
#    12.  screenshot-img-main element exists in HTML
#    13.  screenshot-img-cockpit element exists in HTML
#    14.  screenshot-img-chase element exists in HTML
#    15.  screenshot-img-suspension element exists in HTML
#    16.  pollScreenshotStatus function exists
#    17.  captureScreenshot function calls correct endpoint
#    18.  enlargeScreenshot function exists (detail view)
#   Refresh Logic:
#    19.  Screenshot polling interval exists (setInterval)
#    20.  _screenshot_capture_loop background task registered
#   Syntax:
#    21.  Python syntax compiles
#
# Usage:
#   bash scripts/edge_camera_preview_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[edge-cam]  $*"; }
pass() { echo "[edge-cam]    PASS: $*"; }
fail() { echo "[edge-cam]    FAIL: $*"; FAIL=1; }

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "EDGE-CAM-1: Edge Camera Preview Grid Smoke Test"
echo ""

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# Note: DASHBOARD_HTML is too large for shell variable; grep the file directly

# ═══════════════════════════════════════════════════════════════════
# SLOT NAMING CONSISTENCY
# ═══════════════════════════════════════════════════════════════════

# ── 1. JS updateCameraDisplay uses canonical slots ───────────────
log "Step 1: updateCameraDisplay uses canonical slot names"
UPDATE_CAM_LINE=$(grep "main.*cockpit.*chase.*suspension.*forEach" "$PIT_DASH" || true)
if [ -n "$UPDATE_CAM_LINE" ]; then
  pass "updateCameraDisplay iterates canonical names"
else
  fail "updateCameraDisplay does not use canonical names"
fi

# ── 2. JS refreshAllScreenshots uses canonical slots ─────────────
log "Step 2: refreshAllScreenshots uses canonical slot names"
REFRESH_LINE=$(grep "main.*cockpit.*chase.*suspension" "$PIT_DASH" | grep -v "forEach" | grep -v "_camera_status\|_camera_devices\|cameraStatus\|cameraMappings\|valid_cameras\|CANONICAL" | head -1 || true)
if [ -n "$REFRESH_LINE" ]; then
  pass "refreshAllScreenshots uses canonical names"
else
  # Alternative: check the for-of loop directly
  if grep -q "for (const cam of \['main', 'cockpit', 'chase', 'suspension'\])" "$PIT_DASH"; then
    pass "refreshAllScreenshots uses canonical names"
  else
    fail "refreshAllScreenshots does not use canonical names"
  fi
fi

# ── 3. HTML grid tile IDs use canonical names ────────────────────
log "Step 3: HTML grid tile IDs use canonical names"
TILES_OK=true
for slot in main cockpit chase suspension; do
  if grep -q "id=\"screenshot-${slot}\"" "$PIT_DASH"; then
    pass "Tile ID screenshot-${slot} exists"
  else
    fail "Missing tile ID screenshot-${slot}"
    TILES_OK=false
  fi
done

# ── 4. No JS arrays with legacy camera names ────────────────────
log "Step 4: No JS arrays with legacy camera names"
# Check JS forEach/for-of arrays don't use pov/roof/front
if grep -E "forEach|for \(const" "$PIT_DASH" | grep -v "^#\|^.*#\|legacy\|alias\|normalize\|valid_cameras\|all_valid" | grep -qE "'pov'|'roof'|'front'" 2>/dev/null; then
  fail "JS arrays still reference legacy camera names"
else
  pass "No legacy camera names in JS iteration arrays"
fi

# ═══════════════════════════════════════════════════════════════════
# SCREENSHOT ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

# ── 5. GET /api/cameras/screenshot/{camera} route ────────────────
log "Step 5: GET /api/cameras/screenshot/{camera} route registered"
if grep -q "add_get.*/api/cameras/screenshot/{camera}.*handle_camera_screenshot" "$PIT_DASH"; then
  pass "GET screenshot route registered"
else
  fail "GET screenshot route missing"
fi

# ── 6. GET /api/cameras/screenshots/status route ─────────────────
log "Step 6: GET /api/cameras/screenshots/status route registered"
if grep -q "add_get.*/api/cameras/screenshots/status.*handle_screenshots_status" "$PIT_DASH"; then
  pass "GET screenshots status route registered"
else
  fail "GET screenshots status route missing"
fi

# ── 7. POST /api/cameras/screenshot/{camera}/capture route ───────
log "Step 7: POST /api/cameras/screenshot/{camera}/capture route registered"
if grep -q "add_post.*/api/cameras/screenshot/{camera}/capture.*handle_capture_screenshot" "$PIT_DASH"; then
  pass "POST capture route registered"
else
  fail "POST capture route missing"
fi

# ═══════════════════════════════════════════════════════════════════
# HANDLER NORMALIZATION
# ═══════════════════════════════════════════════════════════════════

# ── 8. handle_camera_screenshot normalizes slot ──────────────────
log "Step 8: handle_camera_screenshot normalizes slot name"
SCREENSHOT_HANDLER=$(sed -n '/async def handle_camera_screenshot/,/^    async def /p' "$PIT_DASH")
if echo "$SCREENSHOT_HANDLER" | grep -q '_normalize_camera_slot'; then
  pass "handle_camera_screenshot normalizes slot"
else
  fail "handle_camera_screenshot missing slot normalization"
fi

# ── 9. handle_capture_screenshot normalizes slot ─────────────────
log "Step 9: handle_capture_screenshot normalizes slot name"
CAPTURE_HANDLER=$(sed -n '/async def handle_capture_screenshot/,/^    async def /p' "$PIT_DASH")
if echo "$CAPTURE_HANDLER" | grep -q '_normalize_camera_slot'; then
  pass "handle_capture_screenshot normalizes slot"
else
  fail "handle_capture_screenshot missing slot normalization"
fi

# ── 10. _normalize_camera_slot function exists ───────────────────
log "Step 10: _normalize_camera_slot function exists"
if grep -q 'def _normalize_camera_slot' "$PIT_DASH"; then
  pass "_normalize_camera_slot function exists"
else
  fail "_normalize_camera_slot function missing"
fi

# ── 11. _camera_aliases maps legacy names ────────────────────────
log "Step 11: _camera_aliases maps legacy names to canonical"
ALIASES_OK=true
for legacy in pov roof front; do
  if grep -q "\"$legacy\"" "$PIT_DASH"; then
    true  # alias exists
  else
    fail "Missing alias for $legacy"
    ALIASES_OK=false
  fi
done
if $ALIASES_OK; then
  pass "Legacy aliases defined for pov, roof, front"
fi

# ═══════════════════════════════════════════════════════════════════
# GRID UI
# ═══════════════════════════════════════════════════════════════════

# ── 12-15. Screenshot img elements exist ─────────────────────────
STEP=12
for slot in main cockpit chase suspension; do
  log "Step $STEP: screenshot-img-${slot} element exists"
  if grep -q "id=\"screenshot-img-${slot}\"" "$PIT_DASH"; then
    pass "screenshot-img-${slot} element exists"
  else
    fail "screenshot-img-${slot} element missing"
  fi
  STEP=$((STEP + 1))
done

# ── 16. pollScreenshotStatus function exists ─────────────────────
log "Step 16: pollScreenshotStatus function exists"
if grep -q 'function pollScreenshotStatus' "$PIT_DASH"; then
  pass "pollScreenshotStatus function exists"
else
  fail "pollScreenshotStatus function missing"
fi

# ── 17. captureScreenshot calls correct endpoint ─────────────────
log "Step 17: captureScreenshot calls correct endpoint"
if grep -q "/api/cameras/screenshot/.*capture" "$PIT_DASH"; then
  pass "captureScreenshot calls /api/cameras/screenshot/{cam}/capture"
else
  fail "captureScreenshot calls wrong endpoint"
fi

# ── 18. enlargeScreenshot function exists ────────────────────────
log "Step 18: enlargeScreenshot function exists"
if grep -q 'function enlargeScreenshot' "$PIT_DASH"; then
  pass "enlargeScreenshot function exists"
else
  fail "enlargeScreenshot function missing"
fi

# ═══════════════════════════════════════════════════════════════════
# REFRESH LOGIC
# ═══════════════════════════════════════════════════════════════════

# ── 19. Screenshot polling interval exists ───────────────────────
log "Step 19: Screenshot polling interval exists"
if grep -q 'setInterval.*pollScreenshotStatus\|pollScreenshotStatus.*setInterval' "$PIT_DASH"; then
  pass "Screenshot polling interval set"
else
  fail "Screenshot polling interval missing"
fi

# ── 20. _screenshot_capture_loop background task ─────────────────
log "Step 20: _screenshot_capture_loop background task registered"
if grep -q 'create_task.*_screenshot_capture_loop' "$PIT_DASH"; then
  pass "_screenshot_capture_loop registered as asyncio task"
else
  fail "_screenshot_capture_loop not registered"
fi

# ═══════════════════════════════════════════════════════════════════
# SYNTAX
# ═══════════════════════════════════════════════════════════════════

# ── 21. Python syntax compiles ───────────────────────────────────
log "Step 21: Python syntax compiles"
if python3 -c "import ast; ast.parse(open('$PIT_DASH').read())" 2>/dev/null; then
  pass "Python syntax OK"
else
  fail "Python syntax error"
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
