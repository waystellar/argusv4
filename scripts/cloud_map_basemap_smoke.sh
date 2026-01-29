#!/usr/bin/env bash
# cloud_map_basemap_smoke.sh — Smoke test for MAP-STYLE-1 + MAP-STYLE-2
#
# MAP-STYLE-1: Light Topographic Basemap — all maps use OpenTopoMap,
#              no dark/CARTO tiles, background layer for fallback.
# MAP-STYLE-2: Single-Source Basemap Config — all tile definitions live
#              in config/basemap.ts; map components import from there.
#
# Validates:
#   Centralized Config (config/basemap.ts):
#     1.  basemap.ts exists with tile URLs (a/b/c mirrors)
#     2.  basemap.ts exports buildBasemapStyle function
#     3.  basemap.ts has forceLightMap flag
#     4.  basemap.ts has backgroundColor (#f2efe9)
#     5.  Exactly ONE source file contains hardcoded tile URLs
#   Shared Map Component (Map.tsx):
#     6.  Imports buildBasemapStyle from shared config
#     7.  No hardcoded tile.opentopomap.org URLs
#     8.  No CARTO dark tile URL (dark_all)
#     9.  No CARTO light tile URL (light_all)
#    10.  No theme-driven tile source switching (TILE_SOURCES)
#    11.  No streets/dark layer toggle (MapLayer type removed)
#    12.  Tile error state (tileError) for basemap-unavailable banner
#    13.  "Basemap unavailable" banner text
#    14.  No useThemeStore import for tile switching
#   Admin CourseMap (EventDetail.tsx):
#    15.  Imports buildBasemapStyle from shared config
#    16.  No hardcoded tile.opentopomap.org URLs
#   CSS / Styling:
#    17.  No CSS filter:invert on map containers
#    18.  No forced dark background on map tile containers
#   Built Assets (if web/dist exists):
#    19.  No dark tile URLs in built JS bundles
#    20.  OpenTopoMap URL present in built JS bundles
#
# Usage:
#   bash scripts/cloud_map_basemap_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[map-basemap]  $*"; }
pass() { echo "[map-basemap]    PASS: $*"; }
fail() { echo "[map-basemap]    FAIL: $*"; FAIL=1; }
warn() { echo "[map-basemap]    WARN: $*"; }

BASEMAP_TS="$REPO_ROOT/web/src/config/basemap.ts"
MAP_TSX="$REPO_ROOT/web/src/components/Map/Map.tsx"
EVENT_TSX="$REPO_ROOT/web/src/pages/admin/EventDetail.tsx"
INDEX_CSS="$REPO_ROOT/web/src/index.css"
DIST_DIR="$REPO_ROOT/web/dist"

log "MAP-STYLE-1 + MAP-STYLE-2: Basemap Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# CENTRALIZED CONFIG (config/basemap.ts)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$BASEMAP_TS" ]; then
  fail "config/basemap.ts not found"
  exit 1
fi

# ── 1. Basemap config has tile URLs (a/b/c mirrors) ────────────────
log "Step 1: basemap.ts has OpenTopoMap tile URLs (a/b/c mirrors)"
MIRROR_COUNT=$(grep -c 'tile\.opentopomap\.org' "$BASEMAP_TS" || true)
if [ "$MIRROR_COUNT" -ge 3 ]; then
  pass "OpenTopoMap mirrors present ($MIRROR_COUNT references)"
else
  fail "OpenTopoMap mirrors missing (found $MIRROR_COUNT, need >= 3)"
fi

# ── 2. Exports buildBasemapStyle function ──────────────────────────
log "Step 2: basemap.ts exports buildBasemapStyle"
if grep -q 'export function buildBasemapStyle' "$BASEMAP_TS"; then
  pass "buildBasemapStyle exported"
else
  fail "buildBasemapStyle not exported from basemap.ts"
fi

# ── 3. Has forceLightMap flag ──────────────────────────────────────
log "Step 3: basemap.ts has forceLightMap flag"
if grep -q 'forceLightMap.*true' "$BASEMAP_TS"; then
  pass "forceLightMap: true"
else
  fail "forceLightMap flag missing or not true"
fi

# ── 4. Has backgroundColor (#f2efe9) ──────────────────────────────
log "Step 4: basemap.ts has backgroundColor (#f2efe9)"
if grep -q "backgroundColor.*#f2efe9" "$BASEMAP_TS"; then
  pass "backgroundColor: #f2efe9"
else
  fail "backgroundColor #f2efe9 missing from basemap.ts"
fi

# ── 5. Exactly ONE source file has hardcoded tile URLs ─────────────
log "Step 5: Single source of truth for tile URLs"
TILE_FILES=$(grep -rl 'tile\.opentopomap\.org' "$REPO_ROOT/web/src/" 2>/dev/null || true)
TILE_FILE_COUNT=$(echo "$TILE_FILES" | grep -c '.' 2>/dev/null || true)
if [ "$TILE_FILE_COUNT" -eq 1 ]; then
  pass "Exactly 1 file contains tile URLs: $(basename "$TILE_FILES")"
elif [ "$TILE_FILE_COUNT" -eq 0 ]; then
  fail "No source files contain tile URLs"
else
  fail "Multiple files contain tile URLs ($TILE_FILE_COUNT files):"
  echo "$TILE_FILES" | while read -r f; do echo "    $(echo "$f" | sed "s|$REPO_ROOT/||")"; done
fi

# ═══════════════════════════════════════════════════════════════════
# SHARED MAP COMPONENT (Map.tsx)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$MAP_TSX" ]; then
  fail "Map.tsx not found"
  exit 1
fi

# ── 6. Map.tsx imports buildBasemapStyle ───────────────────────────
log "Step 6: Map.tsx imports buildBasemapStyle from shared config"
if grep -q "import.*buildBasemapStyle.*from.*config/basemap" "$MAP_TSX"; then
  pass "Map.tsx imports buildBasemapStyle"
else
  fail "Map.tsx does not import buildBasemapStyle from config/basemap"
fi

# ── 7. No hardcoded tile URLs in Map.tsx ──────────────────────────
log "Step 7: No hardcoded tile URLs in Map.tsx"
if grep -q 'tile\.opentopomap\.org' "$MAP_TSX"; then
  fail "Map.tsx still has hardcoded tile URLs (should use shared config)"
else
  pass "No hardcoded tile URLs in Map.tsx"
fi

# ── 8. No CARTO dark tile URL ─────────────────────────────────────
log "Step 8: No CARTO dark tile URL (dark_all)"
if grep -q 'dark_all' "$MAP_TSX"; then
  fail "CARTO dark tile URL found in Map.tsx"
else
  pass "No CARTO dark tiles"
fi

# ── 9. No CARTO light tile URL ────────────────────────────────────
log "Step 9: No CARTO light tile URL (light_all) — topo only"
if grep -q 'light_all' "$MAP_TSX"; then
  fail "CARTO light tile URL found in Map.tsx"
else
  pass "No CARTO light tiles (topo only)"
fi

# ── 10. No theme-driven tile source switching ─────────────────────
log "Step 10: No theme-driven TILE_SOURCES object"
if grep -q 'TILE_SOURCES' "$MAP_TSX"; then
  fail "TILE_SOURCES still present in Map.tsx"
else
  pass "No TILE_SOURCES object"
fi

# ── 11. No streets/dark layer toggle ─────────────────────────────
log "Step 11: No MapLayer type or streets toggle"
if grep -qE "type MapLayer|'streets'" "$MAP_TSX"; then
  fail "MapLayer type or streets reference found"
else
  pass "No MapLayer/streets toggle"
fi

# ── 12. Tile error state ──────────────────────────────────────────
log "Step 12: Tile error state for basemap-unavailable banner"
if grep -q 'tileError' "$MAP_TSX"; then
  pass "tileError state exists"
else
  fail "tileError state missing"
fi

# ── 13. Basemap unavailable banner text ───────────────────────────
log "Step 13: Basemap unavailable banner text"
if grep -q 'Basemap unavailable' "$MAP_TSX"; then
  pass "Basemap unavailable banner exists"
else
  fail "Basemap unavailable banner missing"
fi

# ── 14. No useThemeStore import for tile switching ────────────────
log "Step 14: No useThemeStore import for tile switching"
if grep -q 'useThemeStore' "$MAP_TSX"; then
  fail "useThemeStore still imported in Map.tsx"
else
  pass "No useThemeStore import"
fi

# ═══════════════════════════════════════════════════════════════════
# ADMIN COURSEMAP (EventDetail.tsx)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$EVENT_TSX" ]; then
  fail "EventDetail.tsx not found"
  exit 1
fi

# ── 15. EventDetail.tsx imports buildBasemapStyle ─────────────────
log "Step 15: EventDetail.tsx imports buildBasemapStyle from shared config"
if grep -q "import.*buildBasemapStyle.*from.*config/basemap" "$EVENT_TSX"; then
  pass "EventDetail.tsx imports buildBasemapStyle"
else
  fail "EventDetail.tsx does not import buildBasemapStyle from config/basemap"
fi

# ── 16. No hardcoded tile URLs in EventDetail.tsx ─────────────────
log "Step 16: No hardcoded tile URLs in EventDetail.tsx"
if grep -q 'tile\.opentopomap\.org' "$EVENT_TSX"; then
  fail "EventDetail.tsx still has hardcoded tile URLs (should use shared config)"
else
  pass "No hardcoded tile URLs in EventDetail.tsx"
fi

# ═══════════════════════════════════════════════════════════════════
# CSS / STYLING
# ═══════════════════════════════════════════════════════════════════

# ── 17. No CSS filter:invert on map containers ────────────────────
log "Step 17: No CSS filter:invert on map containers"
if [ -f "$INDEX_CSS" ]; then
  if grep -qE 'filter:\s*invert|filter:.*invert' "$INDEX_CSS"; then
    fail "CSS filter:invert found in index.css"
  else
    pass "No CSS invert filters"
  fi
else
  warn "index.css not found"
fi

# ── 18. No forced dark background on map tile containers ──────────
log "Step 18: No forced dark bg on map tile pane"
ALL_CSS_DARK=0
for f in "$MAP_TSX" "$INDEX_CSS"; do
  if [ -f "$f" ] && grep -qE 'maplibregl.*background.*#[0-2]|\.maplibregl.*bg-black|\.maplibregl.*bg-neutral-9' "$f"; then
    ALL_CSS_DARK=1
  fi
done
if [ "$ALL_CSS_DARK" -eq 1 ]; then
  fail "Forced dark background on map tile container"
else
  pass "No forced dark background on map tile container"
fi

# ═══════════════════════════════════════════════════════════════════
# BUILT ASSETS (if web/dist exists)
# ═══════════════════════════════════════════════════════════════════

# ── 19. No dark tile URLs in built JS bundles ──────────────────────
log "Step 19: No dark tile URLs in built JS bundles"
if [ -d "$DIST_DIR" ]; then
  INDEX_HTML="$REPO_ROOT/web/index.html"
  DIST_AGE=$(stat -f %m "$DIST_DIR/index.html" 2>/dev/null || echo 0)
  SRC_AGE=$(stat -f %m "$INDEX_HTML" 2>/dev/null || echo 0)
  if [ "$DIST_AGE" -lt "$SRC_AGE" ]; then
    warn "web/dist is stale — run 'npm run build' to rebuild"
  else
    DARK_HITS=$(find "$DIST_DIR" -name '*.js' -print0 | xargs -0 grep -l 'dark_all' 2>/dev/null || true)
    if [ -n "$DARK_HITS" ]; then
      fail "Built JS bundles contain dark tile URLs:"
      echo "$DARK_HITS"
    else
      pass "No dark tile URLs in built bundles"
    fi
  fi
else
  warn "web/dist not found — skipping built asset scan"
fi

# ── 20. OpenTopoMap URL in built JS bundles ────────────────────────
log "Step 20: OpenTopoMap URL in built JS bundles"
if [ -d "$DIST_DIR" ]; then
  DIST_AGE=$(stat -f %m "$DIST_DIR/index.html" 2>/dev/null || echo 0)
  SRC_AGE=$(stat -f %m "$REPO_ROOT/web/index.html" 2>/dev/null || echo 0)
  if [ "$DIST_AGE" -lt "$SRC_AGE" ]; then
    warn "web/dist is stale — skipping"
  else
    TOPO_HITS=$(find "$DIST_DIR" -name '*.js' -print0 | xargs -0 grep -l 'opentopomap' 2>/dev/null || true)
    if [ -n "$TOPO_HITS" ]; then
      pass "OpenTopoMap URL found in built bundles"
    else
      fail "OpenTopoMap URL missing from built bundles"
    fi
  fi
else
  warn "web/dist not found — skipping built asset scan"
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
