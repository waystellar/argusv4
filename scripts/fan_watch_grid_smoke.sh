#!/usr/bin/env bash
# fan_watch_grid_smoke.sh - Smoke test for FAN-WATCH-1: Truck Tile Grid
#
# Validates (source-level):
#   1. WatchTab.tsx does NOT contain "select a camera" text
#   2. WatchTab.tsx renders a grid container with id="watchGrid"
#   3. TruckTile renders banner with team_name and vehicle_number
#   4. Thumbnail uses i.ytimg.com/vi/.../hqdefault.jpg pattern
#   5. Click navigates to /events/:eventId/vehicles/:vehicleId
#   6. CSP in nginx.conf includes i.ytimg.com in img-src
#   7. Responsive grid uses auto-fit/minmax pattern
#   8. TypeScript check passes (tsc --noEmit)
#
# Usage:
#   bash scripts/fan_watch_grid_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WATCH_TAB="$REPO_ROOT/web/src/components/RaceCenter/WatchTab.tsx"
NGINX="$REPO_ROOT/web/nginx.conf"

FAIL=0

log()  { echo "[fan-watch-grid]  $*"; }
pass() { echo "[fan-watch-grid]    PASS: $*"; }
fail() { echo "[fan-watch-grid]    FAIL: $*"; FAIL=1; }

# ── 1. WatchTab.tsx does NOT contain "select a camera" ──────────────
log "Step 1: WatchTab does NOT contain 'select a camera' text"

if [ -f "$WATCH_TAB" ]; then
  # Case-insensitive search for "select a camera"
  if grep -qi 'select a camera' "$WATCH_TAB"; then
    fail "WatchTab.tsx still contains 'select a camera' text"
  else
    pass "WatchTab.tsx does NOT contain 'select a camera' text"
  fi
else
  fail "WatchTab.tsx not found at $WATCH_TAB"
fi

# ── 2. WatchTab.tsx renders grid with id="watchGrid" ────────────────
log "Step 2: WatchTab renders grid container with id='watchGrid'"

if grep -q 'id="watchGrid"' "$WATCH_TAB"; then
  pass "Grid container with id='watchGrid' exists"
else
  fail "Grid container with id='watchGrid' not found"
fi

# ── 3. TruckTile renders banner with team_name and vehicle_number ───
log "Step 3: TruckTile banner shows team_name and vehicle_number"

if grep -q 'data-testid="truck-tile-banner"' "$WATCH_TAB"; then
  pass "TruckTile banner has data-testid='truck-tile-banner'"
else
  fail "TruckTile banner data-testid not found"
fi

if grep -q 'feed.team_name' "$WATCH_TAB" && grep -q 'feed.vehicle_number' "$WATCH_TAB"; then
  pass "Banner renders team_name and vehicle_number"
else
  fail "Banner missing team_name or vehicle_number"
fi

# ── 4. Thumbnail uses i.ytimg.com/vi/.../hqdefault.jpg pattern ──────
log "Step 4: Thumbnail uses i.ytimg.com/vi/.../hqdefault.jpg"

if grep -q 'i.ytimg.com/vi/' "$WATCH_TAB" && grep -q 'hqdefault.jpg' "$WATCH_TAB"; then
  pass "Thumbnail URL pattern: i.ytimg.com/vi/.../hqdefault.jpg"
else
  fail "Thumbnail URL pattern not found"
fi

# ── 5. Click navigates to /events/:eventId/vehicles/:vehicleId ──────
log "Step 5: Tile click navigates to vehicle detail page"

if grep -q 'useNavigate' "$WATCH_TAB" && grep -q '/events/.*eventId.*vehicles/.*vehicleId' "$WATCH_TAB"; then
  pass "Navigation to /events/:eventId/vehicles/:vehicleId found"
else
  fail "Navigation pattern not found"
fi

# ── 6. CSP includes i.ytimg.com in img-src ──────────────────────────
log "Step 6: CSP includes i.ytimg.com in img-src"

if [ -f "$NGINX" ]; then
  # Get the main SPA CSP (the longest CSP line, which is in the location / block)
  CSP_LINE=$(grep 'add_header Content-Security-Policy' "$NGINX" | awk '{ print length, $0 }' | sort -rn | head -1 | cut -d' ' -f2-)
  if echo "$CSP_LINE" | grep -q 'img-src.*i.ytimg.com'; then
    pass "CSP img-src includes i.ytimg.com"
  else
    fail "CSP img-src missing i.ytimg.com"
  fi
else
  fail "nginx.conf not found"
fi

# ── 7. Responsive grid uses auto-fit/minmax ─────────────────────────
log "Step 7: Responsive grid uses auto-fit/minmax"

if grep -q 'auto-fit' "$WATCH_TAB" && grep -q 'minmax' "$WATCH_TAB"; then
  pass "Grid uses auto-fit and minmax for responsive layout"
else
  fail "Responsive grid pattern (auto-fit/minmax) not found"
fi

# ── 8. 60-second thumbnail refresh mechanism ────────────────────────
log "Step 8: 60-second thumbnail refresh mechanism"

if grep -q '60000' "$WATCH_TAB" && grep -q 'thumbnailRefreshKey' "$WATCH_TAB"; then
  pass "60-second thumbnail refresh mechanism found"
else
  fail "Thumbnail refresh mechanism not found"
fi

# ── 9. TypeScript check ─────────────────────────────────────────────
log "Step 9: TypeScript check (tsc --noEmit)"

if command -v npm >/dev/null 2>&1; then
  if (cd "$REPO_ROOT/web" && npx tsc --noEmit) > /tmp/fan_watch_grid_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed"
    tail -20 /tmp/fan_watch_grid_build.log
  fi
else
  echo "[fan-watch-grid]    SKIP: npm not available"
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
