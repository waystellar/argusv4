#!/usr/bin/env bash
# fan_vehicle_detail_smoke.sh - Smoke test for FAN-VEHICLE-1: Vehicle Detail View
#
# Validates (source-level):
#   1. VehiclePage.tsx has id="vehicleTelemetry"
#   2. VehiclePage.tsx has id="vehicleCourseMap"
#   3. Map component is imported
#   4. 60-second throttle interval for map position updates
#   5. YouTubeEmbed component is still used (video kept)
#   6. SSE telemetry hook is used (useEventStream)
#   7. TypeScript check passes (tsc --noEmit)
#
# Usage:
#   bash scripts/fan_vehicle_detail_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VEHICLE_PAGE="$REPO_ROOT/web/src/pages/VehiclePage.tsx"

FAIL=0

log()  { echo "[fan-vehicle-detail]  $*"; }
pass() { echo "[fan-vehicle-detail]    PASS: $*"; }
fail() { echo "[fan-vehicle-detail]    FAIL: $*"; FAIL=1; }

# ── 1. VehiclePage.tsx has id="vehicleTelemetry" ─────────────────────
log "Step 1: VehiclePage has id='vehicleTelemetry'"

if [ -f "$VEHICLE_PAGE" ]; then
  if grep -q 'id="vehicleTelemetry"' "$VEHICLE_PAGE"; then
    pass "id='vehicleTelemetry' found"
  else
    fail "id='vehicleTelemetry' not found"
  fi
else
  fail "VehiclePage.tsx not found at $VEHICLE_PAGE"
fi

# ── 2. VehiclePage.tsx has id="vehicleCourseMap" ─────────────────────
log "Step 2: VehiclePage has id='vehicleCourseMap'"

if grep -q 'id="vehicleCourseMap"' "$VEHICLE_PAGE"; then
  pass "id='vehicleCourseMap' found"
else
  fail "id='vehicleCourseMap' not found"
fi

# ── 3. Map component is imported ─────────────────────────────────────
log "Step 3: Map component is imported"

if grep -q "import Map from" "$VEHICLE_PAGE"; then
  pass "Map component imported"
else
  fail "Map component import not found"
fi

# ── 4. 60-second throttle interval for map updates ───────────────────
log "Step 4: 60-second throttle interval for map position"

if grep -q '60000' "$VEHICLE_PAGE" && grep -q 'mapPosition' "$VEHICLE_PAGE"; then
  pass "60-second throttle interval (60000ms) with mapPosition found"
else
  fail "60-second throttle interval not found"
fi

# ── 5. YouTubeEmbed component is used (video kept) ───────────────────
log "Step 5: YouTubeEmbed component is used (video kept)"

if grep -q 'YouTubeEmbed' "$VEHICLE_PAGE" && grep -q '<YouTubeEmbed' "$VEHICLE_PAGE"; then
  pass "YouTubeEmbed component used"
else
  fail "YouTubeEmbed component not found (video may have been removed)"
fi

# ── 6. SSE telemetry hook is used ────────────────────────────────────
log "Step 6: useEventStream hook is used for SSE telemetry"

if grep -q 'useEventStream' "$VEHICLE_PAGE"; then
  pass "useEventStream hook found"
else
  fail "useEventStream hook not found"
fi

# ── 7. Map renders with courseGeoJSON ────────────────────────────────
log "Step 7: Map receives courseGeoJSON prop"

if grep -q 'courseGeoJSON=' "$VEHICLE_PAGE"; then
  pass "courseGeoJSON prop passed to Map"
else
  fail "courseGeoJSON prop not found"
fi

# ── 8. TypeScript check ──────────────────────────────────────────────
log "Step 8: TypeScript check (tsc --noEmit)"

if command -v npm >/dev/null 2>&1; then
  if (cd "$REPO_ROOT/web" && npx tsc --noEmit) > /tmp/fan_vehicle_detail_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed"
    tail -20 /tmp/fan_vehicle_detail_build.log
  fi
else
  echo "[fan-vehicle-detail]    SKIP: npm not available"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
