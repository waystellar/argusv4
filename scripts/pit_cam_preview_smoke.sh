#!/usr/bin/env bash
# pit_cam_preview_smoke.sh — Smoke test for PIT-CAM-PREVIEW-B
#
# Validates that the Pit Crew Dashboard camera preview system uses
# canonical names, fallback device probing, async subprocess, and
# stable /api/cameras/preview/ endpoints.
#
# Validates:
#   pit_crew_dashboard.py:
#     1.  _get_camera_device uses _normalize_camera_slot for canonical names
#     2.  _get_camera_device fallback map uses canonical keys (main/cockpit/chase/suspension)
#     3.  No legacy names (pov/roof/front) in _get_camera_device fallback map
#     4.  _capture_single_screenshot calls _get_camera_device (not raw dict lookup)
#     5.  _capture_single_screenshot uses asyncio.create_subprocess_exec (non-blocking)
#     6.  _capture_single_screenshot skips cameras that are streaming
#     7.  _screenshot_capture_loop uses _get_camera_device for probing
#     8.  Capture interval is 30 seconds (not 60)
#     9.  /api/cameras/preview/{camera}.jpg route registered
#    10.  /api/cameras/preview/{camera}/capture route registered
#    11.  Frontend JS uses /api/cameras/preview/ for thumbnail src
#    12.  Frontend JS uses /api/cameras/preview/ for manual capture fetch
#    13.  Frontend JS uses /api/cameras/preview/ for enlarge modal
#    14.  Status response uses /api/cameras/preview/ URL
#    15.  No remaining /api/cameras/screenshot/ references in frontend JS
#
# Usage:
#   bash scripts/pit_cam_preview_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[pit-cam]  $*"; }
pass() { echo "[pit-cam]    PASS: $*"; }
fail() { echo "[pit-cam]    FAIL: $*"; FAIL=1; }

DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "PIT-CAM-PREVIEW-B: Camera Preview Smoke Test"
echo ""

if [ ! -f "$DASHBOARD" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# _get_camera_device — Canonical names + fallback probing
# ═══════════════════════════════════════════════════════════════════

# ── 1. Uses _normalize_camera_slot ────────────────────────────────
log "Step 1: _get_camera_device uses _normalize_camera_slot"
if grep -A10 'def _get_camera_device' "$DASHBOARD" | grep -q '_normalize_camera_slot'; then
  pass "_get_camera_device calls _normalize_camera_slot"
else
  fail "_get_camera_device missing _normalize_camera_slot call"
fi

# ── 2. Fallback map uses canonical keys ───────────────────────────
log "Step 2: Fallback map uses canonical camera names"
CANONICAL_COUNT=0
for name in main cockpit chase suspension; do
  if grep -A20 'def _get_camera_device' "$DASHBOARD" | grep -q "\"$name\":"; then
    CANONICAL_COUNT=$((CANONICAL_COUNT + 1))
  fi
done
if [ "$CANONICAL_COUNT" -eq 4 ]; then
  pass "All 4 canonical names in fallback map (main/cockpit/chase/suspension)"
else
  fail "Only $CANONICAL_COUNT/4 canonical names in fallback map"
fi

# ── 3. No legacy names in fallback map ────────────────────────────
log "Step 3: No legacy names in _get_camera_device fallback map"
# Extract just the alt_devices dict (lines between def _get_camera_device and next def)
if grep -A20 'def _get_camera_device' "$DASHBOARD" | grep -E '"(pov|roof|front|rear)":' | grep -qv '#'; then
  fail "Legacy names (pov/roof/front/rear) found in fallback map"
else
  pass "No legacy names in fallback map"
fi

# ═══════════════════════════════════════════════════════════════════
# _capture_single_screenshot — Device probing + async + streaming guard
# ═══════════════════════════════════════════════════════════════════

# ── 4. Calls _get_camera_device ───────────────────────────────────
log "Step 4: _capture_single_screenshot calls _get_camera_device"
if grep -A15 'def _capture_single_screenshot' "$DASHBOARD" | grep -q '_get_camera_device'; then
  pass "_capture_single_screenshot uses _get_camera_device"
else
  fail "_capture_single_screenshot missing _get_camera_device call"
fi

# ── 5. Uses asyncio.create_subprocess_exec ────────────────────────
log "Step 5: _capture_single_screenshot uses async subprocess"
if grep -A80 'def _capture_single_screenshot' "$DASHBOARD" | grep -q 'asyncio.create_subprocess_exec'; then
  pass "Uses asyncio.create_subprocess_exec (non-blocking)"
else
  fail "Missing asyncio.create_subprocess_exec (still blocking?)"
fi

# ── 6. Skips cameras that are streaming ───────────────────────────
log "Step 6: _capture_single_screenshot skips streaming cameras"
if grep -A30 'def _capture_single_screenshot' "$DASHBOARD" | grep -q 'busy (streaming)'; then
  pass "Skips cameras that are busy streaming"
else
  fail "Missing streaming exclusion check"
fi

# ═══════════════════════════════════════════════════════════════════
# _screenshot_capture_loop — Uses _get_camera_device
# ═══════════════════════════════════════════════════════════════════

# ── 7. Capture loop uses _get_camera_device ───────────────────────
log "Step 7: _screenshot_capture_loop uses _get_camera_device"
if grep -A30 'def _screenshot_capture_loop' "$DASHBOARD" | grep -q '_get_camera_device'; then
  pass "_screenshot_capture_loop uses _get_camera_device for probing"
else
  fail "_screenshot_capture_loop missing _get_camera_device call"
fi

# ── 8. Interval is 30 seconds ────────────────────────────────────
log "Step 8: Capture interval is 30 seconds"
if grep -q '_screenshot_interval = 30' "$DASHBOARD"; then
  pass "Capture interval is 30 seconds"
else
  fail "Capture interval is not 30 seconds"
fi

# ═══════════════════════════════════════════════════════════════════
# Route registration — /api/cameras/preview/ endpoints
# ═══════════════════════════════════════════════════════════════════

# ── 9. GET /api/cameras/preview/{camera}.jpg route ────────────────
log "Step 9: Preview GET route registered"
if grep -q "'/api/cameras/preview/{camera}.jpg'" "$DASHBOARD"; then
  pass "GET /api/cameras/preview/{camera}.jpg route registered"
else
  fail "GET /api/cameras/preview/{camera}.jpg route missing"
fi

# ── 10. POST /api/cameras/preview/{camera}/capture route ──────────
log "Step 10: Preview POST capture route registered"
if grep -q "'/api/cameras/preview/{camera}/capture'" "$DASHBOARD"; then
  pass "POST /api/cameras/preview/{camera}/capture route registered"
else
  fail "POST /api/cameras/preview/{camera}/capture route missing"
fi

# ═══════════════════════════════════════════════════════════════════
# Frontend JS — Uses /api/cameras/preview/ paths
# ═══════════════════════════════════════════════════════════════════

# ── 11. Thumbnail src uses preview path ───────────────────────────
log "Step 11: Frontend thumbnail uses /api/cameras/preview/ path"
if grep -q "/api/cameras/preview/.*\.jpg" "$DASHBOARD" | head -1 && grep "img.src" "$DASHBOARD" | grep -q "/api/cameras/preview/"; then
  pass "Thumbnail img.src uses /api/cameras/preview/"
else
  # Direct check for the actual line
  if grep -q "img.src = '/api/cameras/preview/' + cam" "$DASHBOARD"; then
    pass "Thumbnail img.src uses /api/cameras/preview/"
  else
    fail "Thumbnail img.src not using /api/cameras/preview/"
  fi
fi

# ── 12. Manual capture uses preview path ──────────────────────────
log "Step 12: Frontend manual capture uses /api/cameras/preview/ path"
if grep -q "'/api/cameras/preview/' + camera + '/capture'" "$DASHBOARD"; then
  pass "Manual capture fetch uses /api/cameras/preview/"
else
  fail "Manual capture fetch not using /api/cameras/preview/"
fi

# ── 13. Enlarge modal uses preview path ───────────────────────────
log "Step 13: Frontend enlarge modal uses /api/cameras/preview/ path"
# The enlarge modal sets img.src with Date.now() cache buster
if grep "/api/cameras/preview/.*Date.now" "$DASHBOARD" | grep -q 'img.src'; then
  pass "Enlarge modal uses /api/cameras/preview/"
else
  fail "Enlarge modal not using /api/cameras/preview/"
fi

# ── 14. Status response uses preview URL ──────────────────────────
log "Step 14: Status response uses /api/cameras/preview/ URL"
if grep -q "'/api/cameras/preview/" "$DASHBOARD" | head -1 && grep 'screenshot_url' "$DASHBOARD" | grep -q '/api/cameras/preview/'; then
  pass "Status response screenshot_url uses /api/cameras/preview/"
else
  # Direct check
  if grep -q "screenshot_url.*preview" "$DASHBOARD"; then
    pass "Status response screenshot_url uses /api/cameras/preview/"
  else
    fail "Status response screenshot_url not using /api/cameras/preview/"
  fi
fi

# ── 15. No stale /api/cameras/screenshot/ in frontend JS ─────────
log "Step 15: No stale /api/cameras/screenshot/ references in frontend JS"
# Frontend JS is inline in the Python file - check for old paths in JS string contexts
if grep "'/api/cameras/screenshot/" "$DASHBOARD" | grep -v "add_get\|add_post\|handle_" | grep -qv '#'; then
  fail "Stale /api/cameras/screenshot/ reference found in frontend JS"
else
  pass "No stale /api/cameras/screenshot/ references in frontend JS"
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
