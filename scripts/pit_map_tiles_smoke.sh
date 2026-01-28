#!/usr/bin/env bash
# pit_map_tiles_smoke.sh — Smoke test for Pit Crew Map basemap (PIT-2)
#
# Validates:
#   1. Dark basemap (dark_all) is removed
#   2. Light topo basemap (OpenTopoMap) is configured as default
#   3. Light street fallback (CartoCDN Voyager) is available
#   4. Basemap toggle control exists
#   5. Course overlay colors are high-contrast
#   6. Vehicle marker has drop-shadow for visibility on light map
#   7. Tile provider is reachable (HEAD request)
#   8. Python syntax check
#
# Usage:
#   bash scripts/pit_map_tiles_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[pit-map] $*"; }
pass() { echo "[pit-map]   PASS: $*"; }
fail() { echo "[pit-map]   FAIL: $*"; FAIL=1; }
warn() { echo "[pit-map]   WARN: $*"; }

# ── 1. Dark basemap removed ──────────────────────────────────────
log "Step 1: Dark basemap removed"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'dark_all' "$DASHBOARD"; then
    fail "Dashboard still uses dark_all basemap"
  else
    pass "No dark_all basemap reference"
  fi

  if grep -q 'dark_nolabels' "$DASHBOARD"; then
    fail "Dashboard uses dark_nolabels basemap"
  else
    pass "No dark_nolabels basemap reference"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. Light topo basemap configured ─────────────────────────────
log "Step 2: Light topo basemap (OpenTopoMap)"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'opentopomap.org' "$DASHBOARD"; then
    pass "OpenTopoMap tile URL configured"
  else
    fail "OpenTopoMap tile URL missing"
  fi

  if grep -q "currentBasemapKey = 'topo'" "$DASHBOARD"; then
    pass "Topo is the default basemap"
  else
    fail "Topo is not the default basemap"
  fi
fi

# ── 3. Light street fallback ─────────────────────────────────────
log "Step 3: Light street fallback (CartoCDN Voyager)"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'cartocdn.com/voyager' "$DASHBOARD"; then
    pass "CartoCDN Voyager tile URL configured as fallback"
  else
    fail "CartoCDN Voyager fallback missing"
  fi
fi

# ── 4. Basemap toggle control ────────────────────────────────────
log "Step 4: Basemap toggle"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'basemapToggle' "$DASHBOARD"; then
    pass "Basemap toggle control exists"
  else
    fail "Basemap toggle control missing"
  fi

  if grep -q 'basemapToggleBtn' "$DASHBOARD"; then
    pass "Toggle button element exists"
  else
    fail "Toggle button missing"
  fi

  # Toggle switches between topo and street
  if grep -q "topo.*street" "$DASHBOARD"; then
    pass "Toggle switches between topo and street"
  else
    fail "Toggle does not switch styles"
  fi
fi

# ── 5. Course overlay contrast ───────────────────────────────────
log "Step 5: Course overlay high-contrast colors"

if [ -f "$DASHBOARD" ]; then
  # Course path color (blue)
  if grep -q "color: '#3b82f6'" "$DASHBOARD"; then
    pass "Course path uses high-contrast blue (#3b82f6)"
  else
    fail "Course path color missing or changed"
  fi

  # Start marker (green)
  if grep -q "'#22c55e'" "$DASHBOARD"; then
    pass "Start marker uses green (#22c55e)"
  else
    fail "Start marker color missing"
  fi

  # Finish marker (red)
  if grep -q "'#ef4444'" "$DASHBOARD"; then
    pass "Finish marker uses red (#ef4444)"
  else
    fail "Finish marker color missing"
  fi
fi

# ── 6. Vehicle marker shadow ─────────────────────────────────────
log "Step 6: Vehicle marker visibility on light map"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'drop-shadow' "$DASHBOARD"; then
    pass "Vehicle marker has drop-shadow"
  else
    fail "Vehicle marker missing drop-shadow"
  fi

  if grep -q "stroke=\"white\"" "$DASHBOARD"; then
    pass "Vehicle marker has white stroke"
  else
    fail "Vehicle marker missing white stroke"
  fi
fi

# ── 7. Tile provider reachability ─────────────────────────────────
log "Step 7: Tile provider reachability"

# Try to fetch a single tile from OpenTopoMap (zoom 1, tile 0/0)
TOPO_URL="https://a.tile.opentopomap.org/1/0/0.png"
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 10 "$TOPO_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
  pass "OpenTopoMap tile reachable (HTTP $HTTP_CODE)"
else
  warn "OpenTopoMap tile returned HTTP $HTTP_CODE (may be offline or rate-limited)"
fi

# Try CartoCDN Voyager fallback
VOYAGER_URL="https://a.basemaps.cartocdn.com/voyager/1/0/0.png"
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 10 "$VOYAGER_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
  pass "CartoCDN Voyager tile reachable (HTTP $HTTP_CODE)"
else
  warn "CartoCDN Voyager tile returned HTTP $HTTP_CODE (may be offline)"
fi

# ── 8. Python syntax check ────────────────────────────────────────
log "Step 8: Python syntax"

if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "Python syntax valid"
else
  fail "Python syntax error"
fi

# ── Summary ────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
