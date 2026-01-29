#!/usr/bin/env bash
# team_preview_fan_view_smoke.sh — Smoke test for TEAM-EDGE-2: Preview Fan View link
#
# Validates (source-level):
#   1. TeamDashboard renders "Preview Fan View" text
#   2. Link target is /events/{event_id}/vehicles/{vehicle_id} (vehicle page route)
#   3. Link opens in new tab (target="_blank")
#   4. Link has noopener noreferrer for security
#   5. Link is guarded by event_id && visible
#   6. Router has matching /events/:eventId/vehicles/:vehicleId route
#   7. VehiclePage reads eventId and vehicleId from URL params
#   8. DashboardData interface has event_id and vehicle_id fields
#
# Usage:
#   bash scripts/team_preview_fan_view_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEAM_DASH="$REPO_ROOT/web/src/pages/TeamDashboard.tsx"
APP_TSX="$REPO_ROOT/web/src/App.tsx"
VEHICLE_PAGE="$REPO_ROOT/web/src/pages/VehiclePage.tsx"
FAIL=0

log()  { echo "[preview-fan-view]  $*"; }
pass() { echo "[preview-fan-view]    PASS: $*"; }
fail() { echo "[preview-fan-view]    FAIL: $*"; FAIL=1; }

# ── 1. Preview Fan View text ──────────────────────────────────
log "Step 1: Preview Fan View link rendered"

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'Preview Fan View' "$TEAM_DASH"; then
    pass "TeamDashboard has 'Preview Fan View' text"
  else
    fail "TeamDashboard missing 'Preview Fan View' text"
  fi
else
  fail "TeamDashboard.tsx not found"
fi

# ── 2. Link uses correct route format ────────────────────────
log "Step 2: Link target is /events/{event_id}/vehicles/{vehicle_id}"

if [ -f "$TEAM_DASH" ]; then
  if grep -q '/events/\${data.event_id}/vehicles/\${data.vehicle_id}' "$TEAM_DASH"; then
    pass "Link uses /events/\${data.event_id}/vehicles/\${data.vehicle_id}"
  else
    fail "Link does not use correct route format"
  fi
fi

# ── 3. Opens in new tab ──────────────────────────────────────
log "Step 3: Link opens in new tab"

if [ -f "$TEAM_DASH" ]; then
  if grep -B 15 'Preview Fan View' "$TEAM_DASH" | grep -q 'target="_blank"'; then
    pass "Link has target=\"_blank\""
  else
    fail "Link missing target=\"_blank\""
  fi
fi

# ── 4. Security: noopener noreferrer ─────────────────────────
log "Step 4: Link has security attributes"

if [ -f "$TEAM_DASH" ]; then
  if grep -B 15 'Preview Fan View' "$TEAM_DASH" | grep -q 'noopener noreferrer'; then
    pass "Link has rel=\"noopener noreferrer\""
  else
    fail "Link missing noopener noreferrer"
  fi
fi

# ── 5. Guard: event_id && visible ─────────────────────────────
log "Step 5: Link guarded by event_id && visible"

if [ -f "$TEAM_DASH" ]; then
  if grep -B 20 'Preview Fan View' "$TEAM_DASH" | grep -q 'data.event_id && data.visible'; then
    pass "Link guarded by data.event_id && data.visible"
  else
    fail "Link missing event_id && visible guard"
  fi
fi

# ── 6. Router has matching route ──────────────────────────────
log "Step 6: Router has /events/:eventId/vehicles/:vehicleId route"

if [ -f "$APP_TSX" ]; then
  if grep -q '/events/:eventId/vehicles/:vehicleId' "$APP_TSX"; then
    pass "App.tsx has matching route"
  else
    fail "App.tsx missing /events/:eventId/vehicles/:vehicleId route"
  fi

  if grep -q 'VehiclePage' "$APP_TSX"; then
    pass "Route maps to VehiclePage component"
  else
    fail "Route does not map to VehiclePage"
  fi
else
  fail "App.tsx not found"
fi

# ── 7. VehiclePage reads params ───────────────────────────────
log "Step 7: VehiclePage reads eventId and vehicleId from URL"

if [ -f "$VEHICLE_PAGE" ]; then
  if grep -q 'useParams' "$VEHICLE_PAGE"; then
    pass "VehiclePage uses useParams"
  else
    fail "VehiclePage missing useParams"
  fi

  if grep -q 'eventId' "$VEHICLE_PAGE" && grep -q 'vehicleId' "$VEHICLE_PAGE"; then
    pass "VehiclePage reads eventId and vehicleId"
  else
    fail "VehiclePage missing eventId or vehicleId param"
  fi
else
  fail "VehiclePage.tsx not found"
fi

# ── 8. DashboardData has required fields ──────────────────────
log "Step 8: DashboardData interface has event_id and vehicle_id"

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'event_id: string' "$TEAM_DASH"; then
    pass "DashboardData has event_id field"
  else
    fail "DashboardData missing event_id"
  fi

  if grep -q 'vehicle_id: string' "$TEAM_DASH"; then
    pass "DashboardData has vehicle_id field"
  else
    fail "DashboardData missing vehicle_id"
  fi
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
