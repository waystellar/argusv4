#!/usr/bin/env bash
# fan_map_theme_smoke.sh — Smoke test for map theme defaults
#
# MAP-STYLE-1 + MAP-STYLE-2: Maps always use light topo basemap regardless
# of UI theme. CARTO dark/light tiles removed. Tile URLs centralized in
# config/basemap.ts (MAP-STYLE-2). This test verifies that:
#   1. Web frontend builds (tsc + vite build via Docker)
#   2. Default theme is 'system' (themeStore still exists for UI)
#   3. Map uses OpenTopoMap (no CARTO tiles, no theme-driven switching)
#   4. OpenTopoMap tiles are reachable
#   5. CSP permits tile.opentopomap.org
#
# Usage:
#   bash scripts/fan_map_theme_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
BASEMAP_TS="$WEB_DIR/src/config/basemap.ts"
MAP_FILE="$WEB_DIR/src/components/Map/Map.tsx"
THEME_FILE="$WEB_DIR/src/stores/themeStore.ts"
NGINX_CONF="$WEB_DIR/nginx.conf"
FAIL=0

log()  { echo "[map-theme] $*"; }
pass() { echo "[map-theme]   PASS: $*"; }
fail() { echo "[map-theme]   FAIL: $*"; FAIL=1; }
warn() { echo "[map-theme]   WARN: $*"; }

# ── 1. Build check ────────────────────────────────────────────────
log "Step 1: Web frontend build (Docker)"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$WEB_DIR":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit && ./node_modules/.bin/vite build" \
      > /tmp/map_theme_build.log 2>&1; then
    pass "tsc --noEmit + vite build"
  else
    fail "Build failed. Last 20 lines:"
    tail -20 /tmp/map_theme_build.log
  fi
else
  warn "Docker not available — skipping build check"
fi

# ── 2. Default theme is 'system' ──────────────────────────────────
log "Step 2: Default theme checks"

if [ -f "$THEME_FILE" ]; then
  if grep -q "theme: 'system'" "$THEME_FILE" 2>/dev/null; then
    pass "Default theme is 'system' (auto light/dark)"
  else
    fail "Default theme is NOT 'system'"
  fi

  if grep -q "resolvedTheme: getSystemTheme()" "$THEME_FILE" 2>/dev/null; then
    pass "resolvedTheme defaults to getSystemTheme()"
  else
    fail "resolvedTheme does not default to getSystemTheme()"
  fi

  if grep -q "applyTheme(getSystemTheme())" "$THEME_FILE" 2>/dev/null; then
    pass "Fallback uses getSystemTheme()"
  else
    fail "Fallback does not use getSystemTheme()"
  fi

  if grep -q "isDaytime.*sunlight.*dark\|return isDaytime.*sunlight" "$THEME_FILE" 2>/dev/null; then
    pass "getSystemTheme uses time-of-day heuristic"
  else
    fail "getSystemTheme missing daytime logic"
  fi
else
  fail "themeStore.ts not found"
fi

# ── 3. Map uses OpenTopoMap only (no CARTO, no theme switching) ───
log "Step 3: Map tile source checks"

# MAP-STYLE-2: Tile URLs are in centralized config
if [ -f "$BASEMAP_TS" ]; then
  if grep -q "tile.opentopomap.org" "$BASEMAP_TS"; then
    pass "Basemap config uses OpenTopoMap tiles"
  else
    fail "Basemap config missing OpenTopoMap tiles"
  fi

  if grep -q "background-color.*#f2efe9\|backgroundColor.*#f2efe9\|'background'" "$BASEMAP_TS"; then
    pass "Basemap config has light background layer for tile fallback"
  else
    fail "Basemap config missing light background layer"
  fi
else
  fail "config/basemap.ts not found"
fi

if [ -f "$MAP_FILE" ]; then
  # MAP-STYLE-1: Must NOT have CARTO tiles (removed)
  if grep -q "dark_all\|light_all\|basemaps.cartocdn.com" "$MAP_FILE"; then
    fail "Map.tsx still has CARTO tile references (should be topo-only)"
  else
    pass "No CARTO tile references in Map.tsx (topo-only)"
  fi

  # MAP-STYLE-1: Must NOT have theme-driven tile switching
  if grep -q "TILE_SOURCES\|useThemeStore" "$MAP_FILE"; then
    fail "Map.tsx still has theme-driven tile switching"
  else
    pass "No theme-driven tile switching in Map.tsx"
  fi

  # MAP-STYLE-2: Must import from shared config
  if grep -q "import.*buildBasemapStyle.*from.*config/basemap" "$MAP_FILE"; then
    pass "Map.tsx imports from shared basemap config"
  else
    fail "Map.tsx does not import from shared basemap config"
  fi
else
  fail "Map.tsx not found"
fi

# ── 4. OpenTopoMap tiles reachable ─────────────────────────────────
log "Step 4: OpenTopoMap tile reachability"

TOPO_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "User-Agent: ArgusSmoke/1.0" \
  "https://a.tile.opentopomap.org/0/0/0.png" 2>/dev/null || echo "000")
if [ "$TOPO_CODE" = "200" ] || [ "$TOPO_CODE" = "304" ]; then
  pass "OpenTopoMap tile reachable (HTTP $TOPO_CODE)"
else
  warn "OpenTopoMap tile returned HTTP $TOPO_CODE (may be rate-limited)"
fi

# ── 5. CSP permits tile.opentopomap.org ───────────────────────────
log "Step 5: CSP coverage"

if [ -f "$NGINX_CONF" ]; then
  CSP_LINE=$(grep -i "content-security-policy" "$NGINX_CONF" 2>/dev/null || echo "")
  if echo "$CSP_LINE" | grep -q "tile.opentopomap.org"; then
    pass "CSP permits tile.opentopomap.org"
  else
    fail "CSP missing tile.opentopomap.org"
  fi
else
  warn "nginx.conf not found — skipping CSP check"
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
