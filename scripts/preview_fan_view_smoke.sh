#!/usr/bin/env bash
# preview_fan_view_smoke.sh — Smoke test for TEAM-2: Preview Fan View End-to-End
#
# Validates (source-level) the full chain from Team Dashboard "Preview Fan View"
# through the cloud data contract to the Fan VehiclePage video rendering.
#
# Steps:
#   1. Preview Fan View link in TeamDashboard opens correct route
#   2. Preview Fan View opens in new tab (target=_blank)
#   3. CameraFeedResponse has embed_url field
#   4. CameraFeedResponse has type field
#   5. CameraFeedResponse has featured field
#   6. Cloud _youtube_embed_url helper exists
#   7. Cloud cameras endpoint populates embed_url
#   8. Cloud cameras endpoint checks featured_camera_state
#   9. VehiclePage fetches stream-state endpoint
#  10. VehiclePage fetches cameras endpoint
#  11. VehiclePage uses server embed_url (serverEmbedUrl)
#  12. VehiclePage extracts videoId from embed URL
#  13. VehiclePage falls back to youtube_url extraction
#  14. VehiclePage renders YouTubeEmbed when videoId exists
#  15. VehiclePage shows "Stream Offline" fallback
#  16. Camera switcher shows featured indicator
#  17. YouTube live/ URL pattern supported in regex
#  18. Python syntax check: production.py
#  19. TypeScript build check (if node available)
#
# Usage:
#   bash scripts/preview_fan_view_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TD="$REPO_ROOT/web/src/pages/TeamDashboard.tsx"
VP="$REPO_ROOT/web/src/pages/VehiclePage.tsx"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
FAIL=0

log()  { echo "[fan-view-smoke]  $*"; }
pass() { echo "[fan-view-smoke]    PASS: $*"; }
fail() { echo "[fan-view-smoke]    FAIL: $*"; FAIL=1; }
warn() { echo "[fan-view-smoke]    WARN: $*"; }

# ── 1. Preview Fan View link route ────────────────────────────────
log "Step 1: Preview Fan View link route"

if [ -f "$TD" ]; then
  if grep -q '/events/.*vehicles/' "$TD" && grep -q 'Preview Fan View' "$TD"; then
    pass "Preview Fan View links to /events/{eventId}/vehicles/{vehicleId}"
  else
    fail "Preview Fan View link missing or wrong route"
  fi
else
  fail "TeamDashboard.tsx not found"
fi

# ── 2. Opens in new tab ──────────────────────────────────────────
log "Step 2: Opens in new tab"

if [ -f "$TD" ]; then
  if grep -q 'target="_blank"' "$TD" && grep -q 'rel="noopener noreferrer"' "$TD"; then
    pass "Preview Fan View opens in new tab with security attrs"
  else
    fail "Missing target=_blank or noopener noreferrer"
  fi
fi

# ── 3. CameraFeedResponse has embed_url ──────────────────────────
log "Step 3: CameraFeedResponse embed_url field"

if [ -f "$PROD_PY" ]; then
  if grep -A 10 "class CameraFeedResponse" "$PROD_PY" | grep -q "embed_url"; then
    pass "CameraFeedResponse has embed_url field"
  else
    fail "CameraFeedResponse missing embed_url"
  fi
fi

# ── 4. CameraFeedResponse has type field ─────────────────────────
log "Step 4: CameraFeedResponse type field"

if [ -f "$PROD_PY" ]; then
  if grep -A 10 "class CameraFeedResponse" "$PROD_PY" | grep -q 'type.*youtube'; then
    pass "CameraFeedResponse has type field (default: youtube)"
  else
    fail "CameraFeedResponse missing type field"
  fi
fi

# ── 5. CameraFeedResponse has featured field ─────────────────────
log "Step 5: CameraFeedResponse featured field"

if [ -f "$PROD_PY" ]; then
  if grep -A 12 "class CameraFeedResponse" "$PROD_PY" | grep -q "featured.*bool"; then
    pass "CameraFeedResponse has featured bool field"
  else
    fail "CameraFeedResponse missing featured field"
  fi
fi

# ── 6. _youtube_embed_url helper ─────────────────────────────────
log "Step 6: _youtube_embed_url helper function"

if [ -f "$PROD_PY" ]; then
  if grep -q "def _youtube_embed_url" "$PROD_PY"; then
    pass "_youtube_embed_url helper function exists"
  else
    fail "_youtube_embed_url helper missing"
  fi

  if grep -q "_YOUTUBE_ID_RE" "$PROD_PY"; then
    pass "Shared YouTube ID regex defined"
  else
    fail "YouTube ID regex missing"
  fi
fi

# ── 7. Cameras endpoint populates embed_url ──────────────────────
log "Step 7: Cameras endpoint populates embed_url"

if [ -f "$PROD_PY" ]; then
  if grep -A 120 "async def list_available_cameras" "$PROD_PY" | grep -q "embed_url=_youtube_embed_url"; then
    pass "Cameras endpoint computes embed_url server-side"
  else
    fail "Cameras endpoint not populating embed_url"
  fi
fi

# ── 8. Cameras endpoint checks featured state ───────────────────
log "Step 8: Cameras endpoint checks featured_camera_state"

if [ -f "$PROD_PY" ]; then
  if grep -A 120 "async def list_available_cameras" "$PROD_PY" | grep -q "get_featured_camera_state"; then
    pass "Cameras endpoint reads featured_camera_state"
  else
    fail "Cameras endpoint not checking featured state"
  fi

  if grep -A 120 "async def list_available_cameras" "$PROD_PY" | grep -q "feed.featured = True"; then
    pass "Cameras endpoint marks featured feeds"
  else
    fail "Cameras endpoint not marking featured feeds"
  fi
fi

# ── 9. VehiclePage fetches stream-state ──────────────────────────
log "Step 9: VehiclePage fetches stream-state"

if [ -f "$VP" ]; then
  if grep -q "stream-state" "$VP"; then
    pass "VehiclePage fetches stream-state endpoint"
  else
    fail "VehiclePage missing stream-state fetch"
  fi

  if grep -q "refetchInterval: 5000" "$VP"; then
    pass "Stream state polls every 5s"
  else
    fail "Stream state poll interval wrong"
  fi
fi

# ── 10. VehiclePage fetches cameras ──────────────────────────────
log "Step 10: VehiclePage fetches cameras"

if [ -f "$VP" ]; then
  if grep -q "/cameras" "$VP"; then
    pass "VehiclePage fetches cameras endpoint"
  else
    fail "VehiclePage missing cameras fetch"
  fi

  if grep -q "vehicleCameras" "$VP"; then
    pass "Filters cameras by vehicle_id"
  else
    fail "Not filtering cameras by vehicle"
  fi
fi

# ── 11. VehiclePage uses server embed_url ────────────────────────
log "Step 11: VehiclePage uses server-computed embed_url"

if [ -f "$VP" ]; then
  if grep -q "serverEmbedUrl" "$VP"; then
    pass "serverEmbedUrl variable exists"
  else
    fail "serverEmbedUrl missing"
  fi

  if grep -q "currentCamera?.embed_url" "$VP"; then
    pass "Falls back to camera embed_url"
  else
    fail "Not using camera embed_url"
  fi
fi

# ── 12. VehiclePage extracts videoId from embed URL ──────────────
log "Step 12: VehiclePage extracts videoId from embed URL"

if [ -f "$VP" ]; then
  if grep -q 'embedMatch.*embed' "$VP"; then
    pass "Extracts video ID from embed URL format"
  else
    fail "Not extracting video ID from embed URL"
  fi
fi

# ── 13. VehiclePage falls back to youtube_url extraction ─────────
log "Step 13: Client-side video ID extraction fallback"

if [ -f "$VP" ]; then
  if grep -q "extractVideoId" "$VP"; then
    pass "extractVideoId function exists as fallback"
  else
    fail "extractVideoId fallback missing"
  fi

  if grep -q 'youtu\\.' "$VP" || grep -q "youtu.be" "$VP"; then
    pass "Handles youtu.be short URLs"
  else
    fail "Missing youtu.be support"
  fi
fi

# ── 14. VehiclePage renders YouTubeEmbed ─────────────────────────
log "Step 14: YouTubeEmbed renders when videoId exists"

if [ -f "$VP" ]; then
  if grep -q "videoId ?" "$VP" || grep -q "videoId}" "$VP"; then
    pass "YouTubeEmbed conditionally rendered with videoId"
  else
    fail "YouTubeEmbed not conditional on videoId"
  fi

  if grep -q "<YouTubeEmbed" "$VP"; then
    pass "YouTubeEmbed component used"
  else
    fail "YouTubeEmbed component missing"
  fi
fi

# ── 15. Stream Offline fallback ──────────────────────────────────
log "Step 15: Stream Offline fallback"

if [ -f "$VP" ]; then
  if grep -q "Stream Offline" "$VP"; then
    pass "Stream Offline message shown when no video"
  else
    fail "Stream Offline fallback missing"
  fi

  if grep -q "not currently streaming" "$VP"; then
    pass "Helpful offline message for fans"
  else
    fail "Missing helpful offline message"
  fi
fi

# ── 16. Camera switcher featured indicator ───────────────────────
log "Step 16: Camera switcher shows featured indicator"

if [ -f "$VP" ]; then
  if grep -q "cam.featured" "$VP"; then
    pass "Camera switcher checks featured flag"
  else
    fail "Camera switcher not using featured flag"
  fi

  if grep -q 'title="Featured"' "$VP"; then
    pass "Featured indicator has title tooltip"
  else
    fail "Featured indicator missing tooltip"
  fi
fi

# ── 17. YouTube live/ URL pattern ────────────────────────────────
log "Step 17: YouTube live/ URL pattern supported"

if [ -f "$PROD_PY" ]; then
  if grep -q "live/" "$PROD_PY"; then
    pass "Cloud regex handles youtube.com/live/ URLs"
  else
    fail "Cloud regex missing live/ pattern"
  fi
fi

if [ -f "$VP" ]; then
  if grep -q 'live' "$VP" && grep -q 'embed.*v.*watch.*live' "$VP"; then
    pass "Fan page regex handles youtube.com/live/ URLs"
  else
    fail "Fan page regex missing live/ pattern"
  fi
fi

# ── 18. Python syntax check ──────────────────────────────────────
log "Step 18: Python syntax (production.py)"

if python3 -c "import py_compile; py_compile.compile('$PROD_PY', doraise=True)" 2>/dev/null; then
  pass "production.py syntax valid"
else
  fail "production.py syntax error"
fi

# ── 19. TypeScript build check ───────────────────────────────────
log "Step 19: TypeScript build check"

if command -v node >/dev/null 2>&1; then
  if [ -f "$REPO_ROOT/web/package.json" ]; then
    if (cd "$REPO_ROOT/web" && npx tsc --noEmit 2>&1); then
      pass "TypeScript build passes"
    else
      fail "TypeScript build errors"
    fi
  else
    warn "web/package.json not found"
  fi
else
  warn "Node.js not available — skipping tsc check (source-level checks above substitute)"
fi

# ── Summary ──────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
