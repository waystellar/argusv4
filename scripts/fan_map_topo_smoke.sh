#!/usr/bin/env bash
# fan_map_topo_smoke.sh — Smoke test for Fan Watch Live topo layer
#
# Validates:
#   1. Web frontend builds (tsc + vite build via Docker)
#   2. Map.tsx has topo tile source (OpenTopoMap)
#   3. Map.tsx has layer toggle support (topo/streets)
#   4. CSP includes tile.opentopomap.org in img-src and connect-src
#   5. OpenTopoMap tile server reachable
#   6. Existing basemap sources preserved (CARTO dark/light)
#
# Usage:
#   bash scripts/fan_map_topo_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
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

# ── 2. Map.tsx has topo tile source ────────────────────────────────
log "Step 2: Topo tile source"

if [ -f "$MAP_FILE" ]; then
  # Check for OpenTopoMap tile URL
  if grep -q "tile.opentopomap.org" "$MAP_FILE"; then
    pass "Map.tsx references tile.opentopomap.org"
  else
    fail "Map.tsx missing tile.opentopomap.org"
  fi

  # Check for topo tile URL pattern with z/x/y
  if grep -q "opentopomap.org.*{z}.*{x}.*{y}" "$MAP_FILE"; then
    pass "Map.tsx has OpenTopoMap tile URL template"
  else
    fail "Map.tsx missing OpenTopoMap tile URL template"
  fi

  # Check for OpenTopoMap attribution
  if grep -q "opentopomap.org" "$MAP_FILE" && grep -q "CC-BY-SA" "$MAP_FILE"; then
    pass "Map.tsx has OpenTopoMap attribution"
  else
    fail "Map.tsx missing OpenTopoMap attribution"
  fi
else
  fail "Map.tsx not found"
fi

# ── 3. Layer toggle support ────────────────────────────────────────
log "Step 3: Layer toggle"

if [ -f "$MAP_FILE" ]; then
  # Check for layer type definition
  if grep -q "topo.*streets\|MapLayer" "$MAP_FILE"; then
    pass "Map.tsx has layer type (topo/streets)"
  else
    fail "Map.tsx missing layer type"
  fi

  # Check for layer state
  if grep -q "mapLayer\|setMapLayer" "$MAP_FILE"; then
    pass "Map.tsx has layer state management"
  else
    fail "Map.tsx missing layer state"
  fi

  # Check topo is default
  if grep -q "useState.*'topo'" "$MAP_FILE"; then
    pass "Default layer is topo"
  else
    fail "Default layer is NOT topo"
  fi

  # Check for toggle UI
  if grep -q "Topo" "$MAP_FILE" && grep -q "Streets" "$MAP_FILE"; then
    pass "Map.tsx has Topo/Streets toggle labels"
  else
    fail "Map.tsx missing toggle labels"
  fi
fi

# ── 4. CSP includes topo domain ────────────────────────────────────
log "Step 4: CSP checks"

if [ -f "$NGINX_CONF" ]; then
  CSP_LINE=$(grep -i "content-security-policy" "$NGINX_CONF" 2>/dev/null || echo "")

  # img-src must include opentopomap
  if echo "$CSP_LINE" | grep -q "img-src[^;]*tile.opentopomap.org"; then
    pass "CSP img-src includes tile.opentopomap.org"
  else
    fail "CSP img-src MISSING tile.opentopomap.org"
  fi

  # img-src must include wildcard for subdomains
  if echo "$CSP_LINE" | grep -q 'img-src[^;]*\*\.tile\.opentopomap\.org'; then
    pass "CSP img-src includes *.tile.opentopomap.org"
  else
    fail "CSP img-src MISSING *.tile.opentopomap.org"
  fi

  # connect-src must include opentopomap
  if echo "$CSP_LINE" | grep -q "connect-src[^;]*tile.opentopomap.org"; then
    pass "CSP connect-src includes tile.opentopomap.org"
  else
    fail "CSP connect-src MISSING tile.opentopomap.org"
  fi

  # connect-src must include wildcard for subdomains
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

# Test tile fetch (zoom 0, x 0, y 0 — single world tile)
TOPO_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "User-Agent: ArgusSmoke/1.0" \
  "https://a.tile.opentopomap.org/0/0/0.png" 2>/dev/null || echo "000")
if [ "$TOPO_CODE" = "200" ] || [ "$TOPO_CODE" = "304" ]; then
  pass "OpenTopoMap tile reachable (HTTP $TOPO_CODE)"
else
  warn "OpenTopoMap tile returned HTTP $TOPO_CODE (may be rate-limited)"
fi

# Also test subdomain b
TOPO_B_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "User-Agent: ArgusSmoke/1.0" \
  "https://b.tile.opentopomap.org/0/0/0.png" 2>/dev/null || echo "000")
if [ "$TOPO_B_CODE" = "200" ] || [ "$TOPO_B_CODE" = "304" ]; then
  pass "OpenTopoMap subdomain b reachable (HTTP $TOPO_B_CODE)"
else
  warn "OpenTopoMap subdomain b returned HTTP $TOPO_B_CODE"
fi

# ── 6. Existing basemaps preserved ─────────────────────────────────
log "Step 6: Existing basemaps preserved"

if [ -f "$MAP_FILE" ]; then
  if grep -q "dark_all" "$MAP_FILE"; then
    pass "CARTO dark_all tiles preserved"
  else
    fail "CARTO dark_all tiles missing"
  fi

  if grep -q "light_all" "$MAP_FILE"; then
    pass "CARTO light_all tiles preserved"
  else
    fail "CARTO light_all tiles missing"
  fi

  if grep -q "basemaps.cartocdn.com" "$MAP_FILE"; then
    pass "basemaps.cartocdn.com domain preserved"
  else
    fail "basemaps.cartocdn.com domain missing"
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
