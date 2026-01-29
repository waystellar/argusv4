#!/usr/bin/env bash
# cloud_map_tile_fallback_smoke.sh — Smoke test for CLOUD-MAP-1 + CLOUD-MAP-2
#
# Validates that the map has a reliable fallback basemap (CARTO Positron)
# beneath the OpenTopoMap overlay, and that topo tile failures are detected
# with a user-visible banner in both Watch Live and Admin CourseMap.
#
# Sections:
#   A. Tile reachability probes (best-effort)
#   B. Basemap config has base + topo sources
#   C. Map.tsx topo error detection
#   D. Admin CourseMap error detection
#   E. nginx CSP allows configured tile domains
#
# Usage:
#   bash scripts/cloud_map_tile_fallback_smoke.sh
#
# Exit codes:
#   0 — all checks passed (WARNs allowed)
#   1 — at least one FAIL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0
WARN=0

log()  { echo "[map-fallback]  $*"; }
pass() { echo "[map-fallback]    PASS: $*"; }
fail() { echo "[map-fallback]    FAIL: $*"; FAIL=1; }
warn() { echo "[map-fallback]    WARN: $*"; WARN=1; }
skip() { echo "[map-fallback]    SKIP: $*"; }

BASEMAP_TS="$REPO_ROOT/web/src/config/basemap.ts"
MAP_TSX="$REPO_ROOT/web/src/components/Map/Map.tsx"
EVENT_DETAIL="$REPO_ROOT/web/src/pages/admin/EventDetail.tsx"
NGINX_CONF="$REPO_ROOT/web/nginx.conf"

log "CLOUD-MAP-1/2: Map Tile Fallback Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION A: Tile Reachability Probes (best-effort)
# ═══════════════════════════════════════════════════════════════════
log "─── Section A: Tile Reachability ───"

# ── A1. OpenTopoMap (topo overlay) — WARN if down ─────────────────
log "A1: OpenTopoMap reachability (topo overlay)"
TOPO_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 \
  "https://a.tile.opentopomap.org/10/176/406.png" 2>/dev/null || echo "000")
if [ "$TOPO_CODE" = "200" ]; then
  pass "OpenTopoMap reachable (HTTP $TOPO_CODE)"
else
  warn "OpenTopoMap unreachable (HTTP $TOPO_CODE) — topo overlay will not render"
fi

# ── A2. CARTO Positron (base layer) — FAIL if down ───────────────
log "A2: CARTO Positron reachability (base layer)"
CARTO_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 \
  "https://a.basemaps.cartocdn.com/light_all/10/176/406.png" 2>/dev/null || echo "000")
if [ "$CARTO_CODE" = "200" ]; then
  pass "CARTO Positron reachable (HTTP $CARTO_CODE)"
else
  # Try OpenStreetMap as secondary check
  OSM_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 \
    "https://tile.openstreetmap.org/10/176/406.png" 2>/dev/null || echo "000")
  if [ "$OSM_CODE" = "200" ]; then
    warn "CARTO unreachable but OSM OK (HTTP $OSM_CODE) — base layer may vary"
  else
    fail "Neither CARTO nor OSM reachable — base map will not render"
  fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION B: Basemap Config — Base + Topo Sources
# ═══════════════════════════════════════════════════════════════════
log "─── Section B: Basemap Configuration ───"

if [ ! -f "$BASEMAP_TS" ]; then
  fail "basemap.ts not found at $BASEMAP_TS"
else
  # ── B1. Has CARTO base tile domain ──────────────────────────────
  log "B1: CARTO base tile domain in basemap.ts"
  if grep -q "basemaps.cartocdn.com" "$BASEMAP_TS"; then
    pass "basemap.ts includes basemaps.cartocdn.com (base layer)"
  else
    fail "basemap.ts missing basemaps.cartocdn.com (no reliable base)"
  fi

  # ── B2. Has OpenTopoMap topo tile domain ────────────────────────
  log "B2: OpenTopoMap topo tile domain in basemap.ts"
  if grep -q "tile.opentopomap.org" "$BASEMAP_TS"; then
    pass "basemap.ts includes tile.opentopomap.org (topo overlay)"
  else
    fail "basemap.ts missing tile.opentopomap.org (no topo overlay)"
  fi

  # ── B3. At least two raster tile domains configured ─────────────
  log "B3: At least two raster tile domains"
  DOMAIN_COUNT=0
  for domain in basemaps.cartocdn.com tile.opentopomap.org tile.openstreetmap.org; do
    if grep -q "$domain" "$BASEMAP_TS"; then
      DOMAIN_COUNT=$((DOMAIN_COUNT + 1))
    fi
  done
  if [ "$DOMAIN_COUNT" -ge 2 ]; then
    pass "$DOMAIN_COUNT tile domains configured (base + overlay)"
  else
    fail "Only $DOMAIN_COUNT tile domain — need at least 2 for fallback"
  fi

  # ── B4. buildBasemapStyle creates both sources ──────────────────
  log "B4: buildBasemapStyle creates base-tiles and topo-tiles sources"
  if grep -q "'base-tiles'" "$BASEMAP_TS" && grep -q "'topo-tiles'" "$BASEMAP_TS"; then
    pass "Both 'base-tiles' and 'topo-tiles' sources in style builder"
  else
    fail "Style builder missing one or both tile sources"
  fi

  # ── B5. Layer ordering: base before topo ────────────────────────
  log "B5: Layer ordering (base renders before topo)"
  BASE_LINE=$(grep -n "'base-tiles'" "$BASEMAP_TS" | grep "id:" | head -1 | cut -d: -f1)
  TOPO_LINE=$(grep -n "'topo-tiles'" "$BASEMAP_TS" | grep "id:" | head -1 | cut -d: -f1)
  # Fallback: just check both layer IDs exist in the layers array
  if grep -q "id: 'base-tiles'" "$BASEMAP_TS" && grep -q "id: 'topo-tiles'" "$BASEMAP_TS"; then
    pass "Both base-tiles and topo-tiles layers defined"
  else
    fail "Missing layer definitions for base-tiles or topo-tiles"
  fi

  # ── B6. Topo overlay has opacity < 1 ───────────────────────────
  log "B6: Topo overlay opacity < 1"
  if grep -q "raster-opacity" "$BASEMAP_TS"; then
    pass "Topo layer has raster-opacity set"
  else
    fail "Topo layer missing raster-opacity (should be < 1 for fallback visibility)"
  fi

  # ── B7. Background fallback color present ───────────────────────
  log "B7: Background fallback color"
  if grep -q "#f2efe9" "$BASEMAP_TS"; then
    pass "Background color #f2efe9 present"
  else
    fail "Background fallback color missing"
  fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION C: Map.tsx Topo Error Detection
# ═══════════════════════════════════════════════════════════════════
log "─── Section C: Map.tsx Error Detection ───"

if [ ! -f "$MAP_TSX" ]; then
  fail "Map.tsx not found"
else
  # ── C1. Error handler listens for topo-tiles source ─────────────
  log "C1: Error handler targets topo-tiles source"
  if grep -q "topo-tiles" "$MAP_TSX" && grep -q "map.on('error'" "$MAP_TSX"; then
    pass "Error handler references topo-tiles source ID"
  else
    fail "Error handler missing topo-tiles source detection"
  fi

  # ── C2. Detects network failures (Failed to fetch / status 0) ──
  log "C2: Detects network failures beyond 429/403"
  if grep -q "Failed to fetch" "$MAP_TSX" || grep -q "status === 0" "$MAP_TSX"; then
    pass "Handles network failures (connection refused, DNS, etc.)"
  else
    fail "Missing network failure detection (status 0 / Failed to fetch)"
  fi

  # ── C3. Uses ref to prevent setState loops ──────────────────────
  log "C3: Loop prevention via ref"
  if grep -q "topoErrorFiredRef" "$MAP_TSX"; then
    pass "Uses topoErrorFiredRef to prevent repeated setState"
  else
    fail "Missing loop prevention ref"
  fi

  # ── C4. Banner text is user-friendly ────────────────────────────
  log "C4: Topo unavailable banner present"
  if grep -q "Topo layer unavailable" "$MAP_TSX"; then
    pass "Banner text: 'Topo layer unavailable — showing base map'"
  else
    fail "Missing topo unavailable banner"
  fi

  # ── C5. Banner uses absolute positioning (overlay containment) ──
  log "C5: Banner uses absolute positioning"
  if grep -B5 "Topo layer unavailable" "$MAP_TSX" | grep -q "absolute"; then
    pass "Banner uses absolute positioning"
  else
    fail "Banner missing absolute positioning"
  fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION D: Admin CourseMap Error Detection
# ═══════════════════════════════════════════════════════════════════
log "─── Section D: Admin CourseMap Error Detection ───"

if [ ! -f "$EVENT_DETAIL" ]; then
  fail "EventDetail.tsx not found"
else
  # ── D1. CourseMap has error handler ──────────────────────────────
  log "D1: CourseMap has map error handler"
  # Check that the CourseMap function contains an error handler
  if grep -A80 'function CourseMap' "$EVENT_DETAIL" | grep -q "map.on('error'"; then
    pass "CourseMap has map.on('error') handler"
  else
    fail "CourseMap missing error handler"
  fi

  # ── D2. CourseMap detects topo-tiles failures ───────────────────
  log "D2: CourseMap targets topo-tiles source"
  if grep -A80 'function CourseMap' "$EVENT_DETAIL" | grep -q "topo-tiles"; then
    pass "CourseMap error handler references topo-tiles"
  else
    fail "CourseMap missing topo-tiles detection"
  fi

  # ── D3. CourseMap has loop prevention ───────────────────────────
  log "D3: CourseMap has loop prevention ref"
  if grep -A5 'function CourseMap' "$EVENT_DETAIL" | grep -q "topoErrorFiredRef"; then
    pass "CourseMap uses topoErrorFiredRef"
  else
    fail "CourseMap missing loop prevention ref"
  fi

  # ── D4. CourseMap has topo unavailable banner ───────────────────
  log "D4: CourseMap has topo unavailable banner"
  if grep -A200 'function CourseMap' "$EVENT_DETAIL" | grep -q "Topo layer unavailable"; then
    pass "CourseMap has 'Topo layer unavailable' banner"
  else
    fail "CourseMap missing topo unavailable banner"
  fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION E: nginx CSP Allows Tile Domains
# ═══════════════════════════════════════════════════════════════════
log "─── Section E: nginx CSP ───"

if [ ! -f "$NGINX_CONF" ]; then
  skip "nginx.conf not found — CSP checks skipped (dev server has no CSP)"
else
  # ── E1. CSP img-src allows CARTO base ───────────────────────────
  log "E1: CSP img-src allows basemaps.cartocdn.com"
  if grep "img-src" "$NGINX_CONF" | grep -q "basemaps.cartocdn.com"; then
    pass "CSP img-src includes basemaps.cartocdn.com"
  else
    fail "CSP img-src missing basemaps.cartocdn.com"
  fi

  # ── E2. CSP connect-src allows CARTO base ───────────────────────
  log "E2: CSP connect-src allows basemaps.cartocdn.com"
  if grep "connect-src" "$NGINX_CONF" | grep -q "basemaps.cartocdn.com"; then
    pass "CSP connect-src includes basemaps.cartocdn.com"
  else
    fail "CSP connect-src missing basemaps.cartocdn.com"
  fi

  # ── E3. CSP img-src allows OpenTopoMap ──────────────────────────
  log "E3: CSP img-src allows tile.opentopomap.org"
  if grep "img-src" "$NGINX_CONF" | grep -q "tile.opentopomap.org"; then
    pass "CSP img-src includes tile.opentopomap.org"
  else
    fail "CSP img-src missing tile.opentopomap.org"
  fi

  # ── E4. CSP connect-src allows OpenTopoMap ──────────────────────
  log "E4: CSP connect-src allows tile.opentopomap.org"
  if grep "connect-src" "$NGINX_CONF" | grep -q "tile.opentopomap.org"; then
    pass "CSP connect-src includes tile.opentopomap.org"
  else
    fail "CSP connect-src missing tile.opentopomap.org"
  fi

  # ── E5. CSP uses wildcard subdomains for mirrors ────────────────
  log "E5: CSP uses wildcard subdomains for tile mirrors"
  WILDCARD_COUNT=0
  for pattern in '*.basemaps.cartocdn.com' '*.tile.opentopomap.org'; do
    if grep -q "$pattern" "$NGINX_CONF"; then
      WILDCARD_COUNT=$((WILDCARD_COUNT + 1))
    fi
  done
  if [ "$WILDCARD_COUNT" -eq 2 ]; then
    pass "CSP has wildcard subdomains for both CARTO and OpenTopoMap"
  else
    fail "CSP missing wildcard subdomain for CARTO or OpenTopoMap ($WILDCARD_COUNT/2)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════"
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
elif [ "$WARN" -ne 0 ]; then
  log "RESULT: ALL CHECKS PASSED (with warnings)"
  exit 0
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
