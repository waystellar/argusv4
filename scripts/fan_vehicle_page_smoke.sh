#!/usr/bin/env bash
# fan_vehicle_page_smoke.sh — Smoke test for Fan Vehicle Detail Page
#
# Validates (source-level):
#   1. VehiclePage exists and exports default component
#   2. Route is wired in App.tsx at /events/:eventId/vehicles/:vehicleId
#   3. RaceCenter navigates to VehiclePage on vehicle select
#   4. VehiclePage fetches stream-state from production API
#   5. VehiclePage fetches fan telemetry from production API
#   6. VehiclePage fetches cameras from production API
#   7. VehiclePage has PageHeader with back navigation
#   8. VehiclePage handles no-data gracefully (skeleton, '--', fallback messages)
#   9. Backend endpoints exist (stream-state, telemetry/fan, cameras)
#  10. Web build passes (tsc --noEmit)
#
# Usage:
#   bash scripts/fan_vehicle_page_smoke.sh [EVENT_ID VEHICLE_ID]
#
# EVENT_ID and VEHICLE_ID are optional and used for live API checks.
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
VEHICLE_PAGE="$WEB_DIR/src/pages/VehiclePage.tsx"
APP_TSX="$WEB_DIR/src/App.tsx"
RACE_CENTER="$WEB_DIR/src/components/RaceCenter/RaceCenter.tsx"
PRODUCTION_PY="$REPO_ROOT/cloud/app/routes/production.py"
EVENT_ID="${1:-}"
VEHICLE_ID="${2:-}"
FAIL=0

log()  { echo "[vehicle-page] $*"; }
pass() { echo "[vehicle-page]   PASS: $*"; }
fail() { echo "[vehicle-page]   FAIL: $*"; FAIL=1; }
warn() { echo "[vehicle-page]   WARN: $*"; }

# ── 1. VehiclePage exists ─────────────────────────────────────────
log "Step 1: VehiclePage component"

if [ -f "$VEHICLE_PAGE" ]; then
  if grep -q 'export default function VehiclePage' "$VEHICLE_PAGE"; then
    pass "VehiclePage exports default component"
  else
    fail "VehiclePage missing default export"
  fi

  if grep -q 'useParams' "$VEHICLE_PAGE"; then
    pass "VehiclePage uses useParams for route params"
  else
    fail "VehiclePage missing useParams"
  fi

  if grep -q 'eventId.*vehicleId' "$VEHICLE_PAGE"; then
    pass "VehiclePage destructures eventId and vehicleId"
  else
    fail "VehiclePage missing eventId/vehicleId params"
  fi
else
  fail "VehiclePage.tsx not found"
fi

# ── 2. Route wired in App.tsx ─────────────────────────────────────
log "Step 2: Route configuration"

if [ -f "$APP_TSX" ]; then
  if grep -q 'events/:eventId/vehicles/:vehicleId' "$APP_TSX"; then
    pass "App.tsx has vehicle detail route"
  else
    fail "App.tsx missing vehicle detail route"
  fi

  if grep -q 'VehiclePage' "$APP_TSX"; then
    pass "App.tsx imports VehiclePage"
  else
    fail "App.tsx missing VehiclePage import"
  fi
else
  fail "App.tsx not found"
fi

# ── 3. RaceCenter navigates on vehicle select ─────────────────────
log "Step 3: RaceCenter navigation"

if [ -f "$RACE_CENTER" ]; then
  if grep -q 'navigate.*events.*vehicles' "$RACE_CENTER"; then
    pass "RaceCenter navigates to vehicle detail on select"
  else
    fail "RaceCenter missing vehicle detail navigation"
  fi

  if grep -q 'handleVehicleSelect' "$RACE_CENTER"; then
    pass "RaceCenter has handleVehicleSelect callback"
  else
    fail "RaceCenter missing handleVehicleSelect"
  fi

  if grep -q 'onVehicleSelect.*handleVehicleSelect' "$RACE_CENTER"; then
    pass "RaceCenter passes handleVehicleSelect to tabs"
  else
    fail "RaceCenter missing onVehicleSelect prop"
  fi
fi

# ── 4. VehiclePage fetches stream-state ───────────────────────────
log "Step 4: Stream state fetch"

if [ -f "$VEHICLE_PAGE" ]; then
  if grep -q 'stream-state' "$VEHICLE_PAGE"; then
    pass "VehiclePage fetches stream-state"
  else
    fail "VehiclePage missing stream-state fetch"
  fi

  if grep -q 'RacerStreamState' "$VEHICLE_PAGE"; then
    pass "VehiclePage has RacerStreamState interface"
  else
    fail "VehiclePage missing RacerStreamState type"
  fi

  if grep -q 'is_live' "$VEHICLE_PAGE"; then
    pass "VehiclePage checks is_live status"
  else
    fail "VehiclePage missing is_live check"
  fi
fi

# ── 5. VehiclePage fetches fan telemetry ──────────────────────────
log "Step 5: Fan telemetry fetch"

if [ -f "$VEHICLE_PAGE" ]; then
  if grep -q 'telemetry/fan' "$VEHICLE_PAGE"; then
    pass "VehiclePage fetches fan telemetry"
  else
    fail "VehiclePage missing fan telemetry fetch"
  fi

  if grep -q 'FanTelemetryResponse' "$VEHICLE_PAGE"; then
    pass "VehiclePage has FanTelemetryResponse type"
  else
    fail "VehiclePage missing FanTelemetryResponse type"
  fi

  if grep -q 'fanTelemetry' "$VEHICLE_PAGE"; then
    pass "VehiclePage uses fanTelemetry data"
  else
    fail "VehiclePage missing fanTelemetry usage"
  fi
fi

# ── 6. VehiclePage fetches cameras ────────────────────────────────
log "Step 6: Camera feeds fetch"

if [ -f "$VEHICLE_PAGE" ]; then
  if grep -q '/cameras' "$VEHICLE_PAGE"; then
    pass "VehiclePage fetches cameras endpoint"
  else
    fail "VehiclePage missing cameras fetch"
  fi

  if grep -q 'vehicleCameras' "$VEHICLE_PAGE"; then
    pass "VehiclePage filters cameras for this vehicle"
  else
    fail "VehiclePage missing vehicle camera filter"
  fi
fi

# ── 7. PageHeader with back navigation ────────────────────────────
log "Step 7: PageHeader and back navigation"

if [ -f "$VEHICLE_PAGE" ]; then
  if grep -q 'PageHeader' "$VEHICLE_PAGE"; then
    pass "VehiclePage uses PageHeader"
  else
    fail "VehiclePage missing PageHeader"
  fi

  if grep -q 'backTo' "$VEHICLE_PAGE"; then
    pass "PageHeader has backTo prop"
  else
    fail "PageHeader missing backTo prop"
  fi

  if grep -q 'Back to race' "$VEHICLE_PAGE"; then
    pass "Back button labeled 'Back to race'"
  else
    fail "Back button missing label"
  fi
fi

# ── 8. No-data graceful handling ──────────────────────────────────
log "Step 8: No-data graceful handling"

if [ -f "$VEHICLE_PAGE" ]; then
  # Loading state
  if grep -q 'isInitialLoading' "$VEHICLE_PAGE"; then
    pass "VehiclePage has initial loading state"
  else
    fail "VehiclePage missing initial loading state"
  fi

  # Skeleton components
  if grep -q 'TelemetryTileSkeleton' "$VEHICLE_PAGE"; then
    pass "VehiclePage shows skeleton tiles during loading"
  else
    fail "VehiclePage missing skeleton tiles"
  fi

  if grep -q 'VideoSkeleton' "$VEHICLE_PAGE"; then
    pass "VehiclePage shows video skeleton during loading"
  else
    fail "VehiclePage missing video skeleton"
  fi

  # Fallback values
  if grep -q "'--'" "$VEHICLE_PAGE"; then
    pass "VehiclePage uses '--' for missing telemetry"
  else
    fail "VehiclePage missing '--' fallback"
  fi

  # Stream offline message
  if grep -q 'Stream Offline' "$VEHICLE_PAGE"; then
    pass "VehiclePage shows 'Stream Offline' when not live"
  else
    fail "VehiclePage missing 'Stream Offline' message"
  fi

  # No telemetry message
  if grep -q 'telemetry not available' "$VEHICLE_PAGE"; then
    pass "VehiclePage shows message when no telemetry shared"
  else
    fail "VehiclePage missing no-telemetry message"
  fi
fi

# ── 9. Backend endpoints exist ────────────────────────────────────
log "Step 9: Backend production endpoints"

if [ -f "$PRODUCTION_PY" ]; then
  if grep -q 'vehicles/{vehicle_id}/stream-state' "$PRODUCTION_PY"; then
    pass "production.py has vehicle stream-state endpoint"
  else
    fail "production.py missing vehicle stream-state endpoint"
  fi

  if grep -q 'vehicles/{vehicle_id}/telemetry/fan' "$PRODUCTION_PY"; then
    pass "production.py has fan telemetry endpoint"
  else
    fail "production.py missing fan telemetry endpoint"
  fi

  if grep -q '/cameras' "$PRODUCTION_PY"; then
    pass "production.py has cameras endpoint"
  else
    fail "production.py missing cameras endpoint"
  fi

  if grep -q 'RacerStreamState' "$PRODUCTION_PY"; then
    pass "production.py has RacerStreamState model"
  else
    fail "production.py missing RacerStreamState model"
  fi

  if grep -q 'FanTelemetryResponse' "$PRODUCTION_PY"; then
    pass "production.py has FanTelemetryResponse model"
  else
    fail "production.py missing FanTelemetryResponse model"
  fi

  if grep -q 'CameraFeedResponse' "$PRODUCTION_PY"; then
    pass "production.py has CameraFeedResponse model"
  else
    fail "production.py missing CameraFeedResponse model"
  fi
else
  fail "production.py not found"
fi

# ── 10. Live API check (optional) ─────────────────────────────────
if [ -n "$EVENT_ID" ] && [ -n "$VEHICLE_ID" ]; then
  log "Step 10: Live API check (event: $EVENT_ID, vehicle: $VEHICLE_ID)"

  API_URL="${API_BASE:-http://localhost:8000}/api/v1/production"

  # Stream state
  RESP=$(curl -sf "$API_URL/events/${EVENT_ID}/vehicles/${VEHICLE_ID}/stream-state" 2>/dev/null || echo "")
  if [ -n "$RESP" ]; then
    if echo "$RESP" | grep -q '"vehicle_id"'; then
      pass "stream-state API returns vehicle_id"
    else
      fail "stream-state API missing vehicle_id"
    fi
    if echo "$RESP" | grep -q '"is_live"'; then
      pass "stream-state API returns is_live"
    else
      fail "stream-state API missing is_live"
    fi
  else
    warn "Could not reach stream-state API (server may not be running)"
  fi

  # Fan telemetry
  RESP=$(curl -sf "$API_URL/events/${EVENT_ID}/vehicles/${VEHICLE_ID}/telemetry/fan" 2>/dev/null || echo "")
  if [ -n "$RESP" ]; then
    if echo "$RESP" | grep -q '"vehicle_id"'; then
      pass "fan telemetry API returns vehicle_id"
    else
      fail "fan telemetry API missing vehicle_id"
    fi
  else
    warn "Could not reach fan telemetry API (server may not be running)"
  fi

  # Cameras
  RESP=$(curl -sf "$API_URL/events/${EVENT_ID}/cameras" 2>/dev/null || echo "")
  if [ -n "$RESP" ]; then
    # Response should be an array (even if empty)
    if echo "$RESP" | grep -qE '^\['; then
      pass "cameras API returns array"
    else
      fail "cameras API does not return array"
    fi
  else
    warn "Could not reach cameras API (server may not be running)"
  fi
else
  log "Step 10: Live API check (skipped — no EVENT_ID/VEHICLE_ID provided)"
fi

# ── 11. Build check ──────────────────────────────────────────────
log "Step 11: Web build"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$WEB_DIR":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit" \
      > /tmp/fan_vehicle_page_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed. Last 20 lines:"
    tail -20 /tmp/fan_vehicle_page_build.log
  fi
else
  warn "Docker not available — skipping build check"
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
