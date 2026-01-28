#!/usr/bin/env bash
# fan_map_theme_smoke.sh — Smoke test for map theme defaults
#
# Validates:
#   1. Web frontend builds (tsc + vite build via Docker)
#   2. Default theme is 'system' (not hardcoded 'dark')
#   3. Sunlight tile source is CARTO light (not dark_all)
#   4. dark_all is NOT the default for Watch Live (only used when resolved dark)
#   5. CARTO light tiles are reachable
#   6. CSP permits basemaps.cartocdn.com for both light and dark
#
# Usage:
#   bash scripts/fan_map_theme_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
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
  # The Zustand store initial state should default to 'system'
  if grep -q "theme: 'system'" "$THEME_FILE" 2>/dev/null; then
    pass "Default theme is 'system' (auto light/dark)"
  else
    fail "Default theme is NOT 'system'"
  fi

  # resolvedTheme should use getSystemTheme() not hardcoded 'dark'
  if grep -q "resolvedTheme: getSystemTheme()" "$THEME_FILE" 2>/dev/null; then
    pass "resolvedTheme defaults to getSystemTheme()"
  else
    fail "resolvedTheme does not default to getSystemTheme()"
  fi

  # Fallback should also use getSystemTheme()
  if grep -q "applyTheme(getSystemTheme())" "$THEME_FILE" 2>/dev/null; then
    pass "Fallback uses getSystemTheme()"
  else
    fail "Fallback does not use getSystemTheme()"
  fi

  # getSystemTheme should return 'sunlight' during daytime
  if grep -q "isDaytime.*sunlight.*dark\|return isDaytime.*sunlight" "$THEME_FILE" 2>/dev/null; then
    pass "getSystemTheme uses time-of-day heuristic"
  else
    fail "getSystemTheme missing daytime logic"
  fi
else
  fail "themeStore.ts not found"
fi

# ── 3. Sunlight tile source is CARTO light ─────────────────────────
log "Step 3: Tile source checks"

if [ -f "$MAP_FILE" ]; then
  # Sunlight should use light_all, not dark_all
  if grep -q "light_all" "$MAP_FILE" 2>/dev/null; then
    pass "Map.tsx has CARTO light_all tiles"
  else
    fail "Map.tsx missing CARTO light_all tiles"
  fi

  # Both tile sources should be basemaps.cartocdn.com
  TILE_LINES=$(grep '{z}/{x}/{y}' "$MAP_FILE" 2>/dev/null)
  DARK_TILE=$(echo "$TILE_LINES" | grep "dark_all" || echo "")
  LIGHT_TILE=$(echo "$TILE_LINES" | grep "light_all" || echo "")

  if [ -n "$DARK_TILE" ] && [ -n "$LIGHT_TILE" ]; then
    pass "Both dark_all and light_all tile sources present"
  else
    fail "Missing dark_all or light_all tile source"
  fi

  # Both should use basemaps.cartocdn.com
  NON_CARTO=$(echo "$TILE_LINES" | grep -v "basemaps.cartocdn.com" || echo "")
  if [ -z "$NON_CARTO" ]; then
    pass "All tile sources use basemaps.cartocdn.com"
  else
    warn "Some tile sources use non-CARTO domains"
  fi
else
  fail "Map.tsx not found"
fi

# ── 4. dark_all is NOT the sole/default tile ───────────────────────
log "Step 4: Default tile is not dark_all"

if [ -f "$MAP_FILE" ]; then
  # The sunlight entry must NOT point to dark_all
  # Check the sunlight block specifically
  SUNLIGHT_BLOCK=$(awk '/sunlight:/{found=1} found{print; if(/\}/) exit}' "$MAP_FILE" 2>/dev/null)
  if echo "$SUNLIGHT_BLOCK" | grep -q "dark_all"; then
    fail "Sunlight tile source still uses dark_all"
  else
    pass "Sunlight tile source does not use dark_all"
  fi
fi

# ── 5. CARTO light tiles reachable ─────────────────────────────────
log "Step 5: CARTO light tile reachability"

LIGHT_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  "https://basemaps.cartocdn.com/light_all/0/0/0.png" 2>/dev/null || echo "000")
if [ "$LIGHT_CODE" = "200" ] || [ "$LIGHT_CODE" = "304" ]; then
  pass "CARTO light_all tile reachable (HTTP $LIGHT_CODE)"
else
  fail "CARTO light_all tile returned HTTP $LIGHT_CODE"
fi

DARK_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  "https://basemaps.cartocdn.com/dark_all/0/0/0.png" 2>/dev/null || echo "000")
if [ "$DARK_CODE" = "200" ] || [ "$DARK_CODE" = "304" ]; then
  pass "CARTO dark_all tile reachable (HTTP $DARK_CODE)"
else
  fail "CARTO dark_all tile returned HTTP $DARK_CODE"
fi

# ── 6. CSP permits basemaps.cartocdn.com ───────────────────────────
log "Step 6: CSP coverage"

if [ -f "$NGINX_CONF" ]; then
  CSP_LINE=$(grep -i "content-security-policy" "$NGINX_CONF" 2>/dev/null || echo "")
  if echo "$CSP_LINE" | grep -q "basemaps.cartocdn.com"; then
    pass "CSP permits basemaps.cartocdn.com (covers both light and dark)"
  else
    fail "CSP missing basemaps.cartocdn.com"
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
