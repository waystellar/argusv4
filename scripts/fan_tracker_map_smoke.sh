#!/usr/bin/env bash
# fan_tracker_map_smoke.sh - Smoke test for FAN-TRACKER-1: Always Show Light Topo Map
#
# MAP-STYLE-1 + MAP-STYLE-2: Maps always use light topo, no CARTO tiles.
# Tile URLs centralized in config/basemap.ts (MAP-STYLE-2).
#
# Validates:
#   1. Map uses topo-only (no CARTO, no layer toggle)
#   2. OpenTopoMap tile URLs configured in basemap config (a/b/c mirrors)
#   3. Background layer for tile fallback (in basemap config)
#   4. CSP img-src permits tile.opentopomap.org
#   5. CSP connect-src permits tile.opentopomap.org
#   6. Map renders unconditionally (no short-circuit on empty positions)
#   7. "No vehicles transmitting" banner shows when positions empty
#   8. GPX/course overlay support (courseGeoJSON prop)
#   9. OverviewTab renders RaceMap without conditional
#  10. TrackerTab has empty state message
#  11. npm run build (if available)
#
# Usage:
#   bash scripts/fan_tracker_map_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[fan-map]  $*"; }
pass() { echo "[fan-map]    PASS: $*"; }
fail() { echo "[fan-map]    FAIL: $*"; FAIL=1; }
skip() { echo "[fan-map]    SKIP: $*"; }

BASEMAP_TS="$REPO_ROOT/web/src/config/basemap.ts"
MAP_TSX="$REPO_ROOT/web/src/components/Map/Map.tsx"
OVERVIEW_TSX="$REPO_ROOT/web/src/components/RaceCenter/OverviewTab.tsx"
TRACKER_TSX="$REPO_ROOT/web/src/components/RaceCenter/TrackerTab.tsx"
NGINX="$REPO_ROOT/web/nginx.conf"

log "FAN-TRACKER-1: Fan Tracker Map Smoke Test"
echo ""

# ── 1. Map uses topo-only (no CARTO, no layer toggle) ─────────
log "Step 1: Map uses topo-only"

if [ -f "$MAP_TSX" ]; then
  # MAP-STYLE-1: No CARTO tiles or layer toggle
  if grep -q "dark_all\|light_all\|basemaps.cartocdn.com" "$MAP_TSX"; then
    fail "CARTO tile references still present (should be topo-only)"
  else
    pass "No CARTO tile references (topo-only)"
  fi

  if grep -qE "type MapLayer|'streets'|setMapLayer" "$MAP_TSX"; then
    fail "Layer toggle still present (should be topo-only)"
  else
    pass "No layer toggle (topo-only)"
  fi
else
  fail "Map.tsx not found"
fi

# ── 2. OpenTopoMap tile URLs configured (basemap config) ──────
log "Step 2: OpenTopoMap tile URLs (config/basemap.ts)"

if [ -f "$BASEMAP_TS" ]; then
  if grep -q 'tile.opentopomap.org' "$BASEMAP_TS"; then
    pass "OpenTopoMap tile URL configured in basemap config"
  else
    fail "OpenTopoMap tile URL missing from basemap config"
  fi

  # Check all three subdomains (a, b, c)
  for sub in a b c; do
    if grep -q "https://${sub}.tile.opentopomap.org" "$BASEMAP_TS"; then
      pass "Subdomain ${sub}.tile.opentopomap.org configured"
    else
      fail "Subdomain ${sub}.tile.opentopomap.org missing"
    fi
  done
else
  fail "config/basemap.ts not found"
fi

# ── 3. Background layer for tile fallback ─────────────────────
log "Step 3: Background layer for tile fallback"

if [ -f "$BASEMAP_TS" ]; then
  if grep -q "'background'" "$BASEMAP_TS" && grep -q '#f2efe9' "$BASEMAP_TS"; then
    pass "Background layer with light fallback color (in basemap config)"
  else
    fail "Background layer or #f2efe9 color missing from basemap config"
  fi
else
  fail "config/basemap.ts not found"
fi

if [ -f "$MAP_TSX" ]; then
  if grep -q "Basemap unavailable" "$MAP_TSX"; then
    pass "Basemap unavailable banner exists"
  else
    fail "Basemap unavailable banner missing"
  fi
fi

# ── 4. CSP img-src permits tile domains ───────────────────────
log "Step 4: CSP img-src permits tile domains"

if [ -f "$NGINX" ]; then
  CSP_LINE=$(grep 'add_header Content-Security-Policy "' "$NGINX" | awk '{ print length, $0 }' | sort -rn | head -1 | cut -d' ' -f2-)

  if [ -z "$CSP_LINE" ]; then
    fail "No CSP found in nginx.conf"
  else
    IMG_SRC=$(echo "$CSP_LINE" | grep -oE "img-src[^;]*" | head -1)

    if echo "$IMG_SRC" | grep -q 'tile.opentopomap.org'; then
      pass "CSP img-src includes tile.opentopomap.org"
    else
      fail "CSP img-src missing tile.opentopomap.org"
    fi

    if echo "$IMG_SRC" | grep -q '\*\.tile\.opentopomap\.org'; then
      pass "CSP img-src includes *.tile.opentopomap.org"
    else
      fail "CSP img-src missing *.tile.opentopomap.org"
    fi
  fi
else
  fail "nginx.conf not found"
fi

# ── 5. CSP connect-src permits tile domains ───────────────────
log "Step 5: CSP connect-src permits tile domains"

if [ -f "$NGINX" ]; then
  CONNECT_SRC=$(echo "$CSP_LINE" | grep -oE "connect-src[^;]*" | head -1)

  if echo "$CONNECT_SRC" | grep -q 'tile.opentopomap.org'; then
    pass "CSP connect-src includes tile.opentopomap.org"
  else
    fail "CSP connect-src missing tile.opentopomap.org"
  fi

  if echo "$CONNECT_SRC" | grep -q '\*\.tile\.opentopomap\.org'; then
    pass "CSP connect-src includes *.tile.opentopomap.org"
  else
    fail "CSP connect-src missing *.tile.opentopomap.org"
  fi
fi

# ── 6. Map renders unconditionally ────────────────────────────
log "Step 6: Map renders unconditionally (no short-circuit)"

if [ -f "$MAP_TSX" ]; then
  # The map JSX return should NOT be wrapped in positions.length > 0 check
  # Verify the return block has the map container div
  if grep -q 'ref={containerRef}' "$MAP_TSX"; then
    pass "Map container renders unconditionally"
  else
    fail "Map container not found"
  fi
fi

if [ -f "$OVERVIEW_TSX" ]; then
  # OverviewTab renders RaceMap without conditional on positions
  if grep -q '<RaceMap' "$OVERVIEW_TSX"; then
    pass "OverviewTab renders RaceMap"
  else
    fail "OverviewTab missing RaceMap"
  fi

  # Verify RaceMap is NOT inside a positions.length > 0 conditional
  # (it should always render)
  if grep -B2 '<RaceMap' "$OVERVIEW_TSX" | grep -q 'positions.length > 0'; then
    fail "RaceMap is conditionally rendered on positions.length"
  else
    pass "RaceMap renders regardless of positions count"
  fi
fi

# ── 7. No vehicles banner on empty map ────────────────────────
log "Step 7: No vehicles transmitting banner"

if [ -f "$OVERVIEW_TSX" ]; then
  if grep -q 'No vehicles transmitting' "$OVERVIEW_TSX"; then
    pass "OverviewTab has 'No vehicles transmitting' banner"
  else
    fail "Missing 'No vehicles transmitting' banner"
  fi

  if grep -q 'positions.length === 0' "$OVERVIEW_TSX"; then
    pass "Banner shows when positions.length === 0"
  else
    fail "Banner not conditional on empty positions"
  fi

  # Verify FAN-TRACKER-1 marker
  if grep -q 'FAN-TRACKER-1' "$OVERVIEW_TSX"; then
    pass "FAN-TRACKER-1 marker present in OverviewTab"
  else
    fail "FAN-TRACKER-1 marker missing"
  fi
fi

# ── 8. Course GeoJSON overlay support ─────────────────────────
log "Step 8: GPX/Course overlay support"

if [ -f "$MAP_TSX" ]; then
  if grep -q 'courseGeoJSON' "$MAP_TSX"; then
    pass "Map accepts courseGeoJSON prop"
  else
    fail "Map missing courseGeoJSON prop"
  fi

  if grep -q 'course-line' "$MAP_TSX"; then
    pass "Course line layer exists"
  else
    fail "Course line layer missing"
  fi
fi

# ── 9. TrackerTab empty state ─────────────────────────────────
log "Step 9: TrackerTab empty state"

if [ -f "$TRACKER_TSX" ]; then
  if grep -q 'Waiting for vehicles' "$TRACKER_TSX"; then
    pass "TrackerTab has empty state message"
  else
    fail "TrackerTab missing empty state"
  fi
fi

# ── 10. npm run build ─────────────────────────────────────────
log "Step 10: npm run build"

if command -v npm &>/dev/null; then
  if cd "$REPO_ROOT/web" && npm run build 2>&1; then
    pass "npm run build succeeded"
  else
    fail "npm run build failed"
  fi
else
  skip "npm not available — skipping build"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
