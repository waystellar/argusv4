#!/usr/bin/env bash
# fan_map_topo_smoke.sh — Smoke test for Fan Watch Live topo layer
#
# MAP-STYLE-1 + MAP-STYLE-2: Maps always use light topo basemap.
# CARTO dark/light tiles and layer toggle removed.
# Tile URLs centralized in config/basemap.ts (MAP-STYLE-2).
#
# Validates:
#   1. Web frontend builds (tsc + vite build via Docker)
#   2. Basemap config has topo tile source (OpenTopoMap a/b/c mirrors)
#   3. Map.tsx uses topo-only (no CARTO, no layer toggle)
#   4. CSP includes tile.opentopomap.org in img-src and connect-src
#   5. OpenTopoMap tile server reachable
#   6. Background layer for tile fallback (in basemap config)
#
# Usage:
#   bash scripts/fan_map_topo_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
BASEMAP_TS="$WEB_DIR/src/config/basemap.ts"
MAP_FILE="$WEB_DIR/src/components/Map/Map.tsx"
NGINX_CONF="$WEB_DIR/nginx.conf"
FAIL=0

log()  { echo "[map-topo] $*"; }
pass() { echo "[map-topo]   PASS: $*"; }
fail() { echo "[map-topo]   FAIL: $*"; FAIL=1; }
warn() { echo "[map-topo]   WARN: $*"; }

# ── 1. Build check ────────────────────────────────────────────────
log "Step 1: Web frontend build"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$WEB_DIR":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit && ./node_modules/.bin/vite build" \
      > /tmp/map_topo_build.log 2>&1; then
    pass "tsc --noEmit + vite build"
  else
    fail "Build failed. Last 20 lines:"
    tail -20 /tmp/map_topo_build.log
  fi
else
  # Try local node
  if [ -f "$WEB_DIR/node_modules/.bin/tsc" ]; then
    if (cd "$WEB_DIR" && npx tsc --noEmit > /tmp/map_topo_build.log 2>&1); then
      pass "tsc --noEmit (local)"
    else
      fail "TypeScript check failed. Last 20 lines:"
      tail -20 /tmp/map_topo_build.log
    fi
  else
    warn "Neither Docker nor local node_modules available — skipping build check"
  fi
fi

# ── 2. Basemap config has topo tile source ────────────────────────
log "Step 2: Topo tile source (config/basemap.ts)"

if [ -f "$BASEMAP_TS" ]; then
  if grep -q "tile.opentopomap.org" "$BASEMAP_TS"; then
    pass "basemap.ts references tile.opentopomap.org"
  else
    fail "basemap.ts missing tile.opentopomap.org"
  fi

  if grep -q "opentopomap.org.*{z}.*{x}.*{y}" "$BASEMAP_TS"; then
    pass "basemap.ts has OpenTopoMap tile URL template"
  else
    fail "basemap.ts missing OpenTopoMap tile URL template"
  fi

  if grep -q "opentopomap.org" "$BASEMAP_TS" && grep -q "CC-BY-SA" "$BASEMAP_TS"; then
    pass "basemap.ts has OpenTopoMap attribution"
  else
    fail "basemap.ts missing OpenTopoMap attribution"
  fi

  # Check all three mirror subdomains
  for sub in a b c; do
    if grep -q "https://${sub}.tile.opentopomap.org" "$BASEMAP_TS"; then
      pass "Mirror ${sub}.tile.opentopomap.org present"
    else
      fail "Mirror ${sub}.tile.opentopomap.org missing"
    fi
  done
else
  fail "config/basemap.ts not found"
fi

# ── 3. Topo-only (no CARTO, no layer toggle) ────────────────────
log "Step 3: Topo-only checks"

if [ -f "$MAP_FILE" ]; then
  # MAP-STYLE-1: No CARTO tiles
  if grep -q "dark_all\|light_all\|basemaps.cartocdn.com" "$MAP_FILE"; then
    fail "CARTO tile references still present (should be topo-only)"
  else
    pass "No CARTO tile references (topo-only)"
  fi

  # MAP-STYLE-1: No MapLayer type or streets toggle
  if grep -qE "type MapLayer|'streets'|setMapLayer" "$MAP_FILE"; then
    fail "Layer toggle still present (should be topo-only)"
  else
    pass "No layer toggle (topo-only)"
  fi

  # MAP-STYLE-1: No theme-driven tile switching
  if grep -q "TILE_SOURCES\|useThemeStore" "$MAP_FILE"; then
    fail "Theme-driven tile switching still present"
  else
    pass "No theme-driven tile switching"
  fi
fi

# ── 4. CSP includes topo domain ────────────────────────────────────
log "Step 4: CSP checks"

if [ -f "$NGINX_CONF" ]; then
  CSP_LINE=$(grep -i "content-security-policy" "$NGINX_CONF" 2>/dev/null || echo "")

  if echo "$CSP_LINE" | grep -q "img-src[^;]*tile.opentopomap.org"; then
    pass "CSP img-src includes tile.opentopomap.org"
  else
    fail "CSP img-src MISSING tile.opentopomap.org"
  fi

  if echo "$CSP_LINE" | grep -q 'img-src[^;]*\*\.tile\.opentopomap\.org'; then
    pass "CSP img-src includes *.tile.opentopomap.org"
  else
    fail "CSP img-src MISSING *.tile.opentopomap.org"
  fi

  if echo "$CSP_LINE" | grep -q "connect-src[^;]*tile.opentopomap.org"; then
    pass "CSP connect-src includes tile.opentopomap.org"
  else
    fail "CSP connect-src MISSING tile.opentopomap.org"
  fi

  if echo "$CSP_LINE" | grep -q 'connect-src[^;]*\*\.tile\.opentopomap\.org'; then
    pass "CSP connect-src includes *.tile.opentopomap.org"
  else
    fail "CSP connect-src MISSING *.tile.opentopomap.org"
  fi
else
  fail "nginx.conf not found"
fi

# ── 5. OpenTopoMap tile reachability ───────────────────────────────
log "Step 5: OpenTopoMap tile reachability"

TOPO_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "User-Agent: ArgusSmoke/1.0" \
  "https://a.tile.opentopomap.org/0/0/0.png" 2>/dev/null || echo "000")
if [ "$TOPO_CODE" = "200" ] || [ "$TOPO_CODE" = "304" ]; then
  pass "OpenTopoMap tile reachable (HTTP $TOPO_CODE)"
else
  warn "OpenTopoMap tile returned HTTP $TOPO_CODE (may be rate-limited)"
fi

TOPO_B_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "User-Agent: ArgusSmoke/1.0" \
  "https://b.tile.opentopomap.org/0/0/0.png" 2>/dev/null || echo "000")
if [ "$TOPO_B_CODE" = "200" ] || [ "$TOPO_B_CODE" = "304" ]; then
  pass "OpenTopoMap subdomain b reachable (HTTP $TOPO_B_CODE)"
else
  warn "OpenTopoMap subdomain b returned HTTP $TOPO_B_CODE"
fi

# ── 6. Background layer for tile fallback ──────────────────────────
log "Step 6: Background layer checks"

if [ -f "$BASEMAP_TS" ]; then
  if grep -q "'background'" "$BASEMAP_TS" && grep -q '#f2efe9' "$BASEMAP_TS"; then
    pass "Background layer with light fallback color (in basemap config)"
  else
    fail "Background layer or #f2efe9 color missing from basemap config"
  fi
else
  fail "config/basemap.ts not found"
fi

if [ -f "$MAP_FILE" ]; then
  # CLOUD-MAP-2: Banner text changed to "Topo layer unavailable"
  if grep -q "Topo layer unavailable" "$MAP_FILE"; then
    pass "Topo layer unavailable banner exists"
  else
    fail "Topo layer unavailable banner missing"
  fi
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
