#!/usr/bin/env bash
# prod_control_room_ui_smoke.sh — Smoke test for PROD-2: Control Room Featured Camera UI
#
# Validates (source-level):
#   1. FeaturedCameraStatus interface defined
#   2. setFeaturedCamera mutation exists and calls featured-camera API
#   3. Camera tile onClick wired to setFeaturedCamera (not old switchCamera)
#   4. Per-vehicle state tracking (featuredCameraStates)
#   5. Optimistic pending state on click
#   6. Polling for pending vehicle states
#   7. Auto-clear transient states (success/failed/timeout)
#   8. "Switching…" UI state on pending camera
#   9. "Featured" badge on active camera
#  10. Error display with retry action
#  11. On Air shows "SWITCHING…" badge when pending
#  12. On Air shows camera label (or "unknown" fallback)
#  13. Keyboard shortcuts use setFeaturedCamera
#  14. Per-truck isolation (vehicleId in mutation)
#  15. Legacy switchCamera mutation removed from usage
#  16. TypeScript build check (if node available)
#
# Usage:
#   bash scripts/prod_control_room_ui_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CR="$REPO_ROOT/web/src/pages/ControlRoom.tsx"
FAIL=0

log()  { echo "[prod-cr-ui] $*"; }
pass() { echo "[prod-cr-ui]   PASS: $*"; }
fail() { echo "[prod-cr-ui]   FAIL: $*"; FAIL=1; }
warn() { echo "[prod-cr-ui]   WARN: $*"; }

# ── 1. FeaturedCameraStatus interface ─────────────────────────
log "Step 1: FeaturedCameraStatus interface"

if [ -f "$CR" ]; then
  if grep -q "interface FeaturedCameraStatus" "$CR"; then
    pass "FeaturedCameraStatus interface defined"
  else
    fail "FeaturedCameraStatus interface missing"
  fi

  if grep -q "desired_camera:" "$CR" && grep -q "active_camera:" "$CR"; then
    pass "Interface has desired_camera and active_camera fields"
  else
    fail "Interface missing desired/active camera fields"
  fi

  if grep -q "'idle' | 'pending' | 'success' | 'failed' | 'timeout'" "$CR"; then
    pass "Interface has full status union type"
  else
    fail "Status union type missing"
  fi
else
  fail "ControlRoom.tsx not found"
fi

# ── 2. setFeaturedCamera mutation ─────────────────────────────
log "Step 2: setFeaturedCamera mutation"

if [ -f "$CR" ]; then
  if grep -q "const setFeaturedCamera = useMutation" "$CR"; then
    pass "setFeaturedCamera mutation defined"
  else
    fail "setFeaturedCamera mutation missing"
  fi

  if grep -q "vehicles/.*featured-camera" "$CR"; then
    pass "Mutation calls per-vehicle featured-camera endpoint"
  else
    fail "Per-vehicle featured-camera endpoint call missing"
  fi

  if grep -q "camera_id: cameraId" "$CR"; then
    pass "Mutation sends camera_id in body"
  else
    fail "camera_id not sent in body"
  fi

  if grep -q "method: 'POST'" "$CR"; then
    pass "Uses POST method"
  else
    fail "Not using POST method"
  fi
fi

# ── 3. Camera tile onClick wired to setFeaturedCamera ─────────
log "Step 3: Camera tile click handler"

if [ -f "$CR" ]; then
  if grep -q "setFeaturedCamera.mutate" "$CR"; then
    pass "Camera tiles call setFeaturedCamera.mutate"
  else
    fail "Camera tiles not calling setFeaturedCamera"
  fi

  if grep -q "vehicleId: cam.vehicle_id" "$CR"; then
    pass "Click passes vehicle_id from camera feed"
  else
    fail "Click not passing vehicle_id"
  fi

  if grep -q "cameraId: cam.camera_name" "$CR"; then
    pass "Click passes camera_name as cameraId"
  else
    fail "Click not passing camera_name"
  fi
fi

# ── 4. Per-vehicle state tracking ─────────────────────────────
log "Step 4: Per-vehicle state tracking"

if [ -f "$CR" ]; then
  if grep -q "featuredCameraStates" "$CR"; then
    pass "featuredCameraStates state variable exists"
  else
    fail "featuredCameraStates missing"
  fi

  if grep -q "setFeaturedCameraStates" "$CR"; then
    pass "setFeaturedCameraStates setter exists"
  else
    fail "setFeaturedCameraStates setter missing"
  fi

  if grep -q "Record<string, FeaturedCameraStatus>" "$CR"; then
    pass "State typed as Record<string, FeaturedCameraStatus>"
  else
    fail "State type incorrect"
  fi
fi

# ── 5. Optimistic pending state ───────────────────────────────
log "Step 5: Optimistic pending state"

if [ -f "$CR" ]; then
  if grep -q "onMutate:" "$CR"; then
    pass "onMutate handler exists for optimistic update"
  else
    fail "onMutate handler missing"
  fi

  if grep -A 10 "onMutate:" "$CR" | grep -q "'pending'"; then
    pass "onMutate sets status to pending"
  else
    fail "onMutate not setting pending status"
  fi
fi

# ── 6. Polling for pending states ─────────────────────────────
log "Step 6: Polling pending states"

if [ -f "$CR" ]; then
  if grep -q "pendingVehicles" "$CR"; then
    pass "Pending vehicles list computed"
  else
    fail "Pending vehicles list missing"
  fi

  if grep -q "setInterval" "$CR"; then
    pass "Polling interval set up"
  else
    fail "Polling interval missing"
  fi

  if grep -q "2000.*Poll every 2 seconds" "$CR"; then
    pass "Polls every 2 seconds while pending"
  else
    fail "Poll interval not 2 seconds"
  fi
fi

# ── 7. Auto-clear transient states ────────────────────────────
log "Step 7: Auto-clear transient states"

if [ -f "$CR" ]; then
  if grep -q "Auto-clear success/failed/timeout" "$CR"; then
    pass "Auto-clear effect exists"
  else
    fail "Auto-clear effect missing"
  fi

  if grep -q "5000" "$CR"; then
    pass "5 second auto-clear timeout"
  else
    fail "Auto-clear timeout not set"
  fi
fi

# ── 8. "Switching…" UI state ──────────────────────────────────
log "Step 8: Switching UI state"

if [ -f "$CR" ]; then
  if grep -q 'Switching…' "$CR"; then
    pass "Switching… text displayed for pending cameras"
  else
    fail "Switching… text missing"
  fi

  if grep -q "isPendingThis" "$CR"; then
    pass "Per-camera pending check (isPendingThis)"
  else
    fail "Per-camera pending check missing"
  fi

  if grep -q "animate-pulse" "$CR"; then
    pass "Pending state has pulse animation"
  else
    fail "Pulse animation missing"
  fi
fi

# ── 9. "Featured" badge on active camera ──────────────────────
log "Step 9: Featured badge"

if [ -f "$CR" ]; then
  if grep -q "Featured" "$CR" && grep -q "isActive" "$CR"; then
    pass "Featured badge shown on active camera"
  else
    fail "Featured badge missing"
  fi
fi

# ── 10. Error display with retry ──────────────────────────────
log "Step 10: Error display with retry"

if [ -f "$CR" ]; then
  if grep -q "last_error" "$CR"; then
    pass "Error message displayed from last_error"
  else
    fail "last_error display missing"
  fi

  if grep -q "Retry" "$CR"; then
    pass "Retry button exists"
  else
    fail "Retry button missing"
  fi

  if grep -q "isFailedThis" "$CR"; then
    pass "Per-camera failed check (isFailedThis)"
  else
    fail "Per-camera failed check missing"
  fi

  if grep -q "Timed out" "$CR"; then
    pass "Timeout message displayed"
  else
    fail "Timeout message missing"
  fi
fi

# ── 11. On Air SWITCHING badge ────────────────────────────────
log "Step 11: On Air pending state"

if [ -f "$CR" ]; then
  if grep -q 'SWITCHING' "$CR"; then
    pass "SWITCHING badge in On Air section"
  else
    fail "SWITCHING badge missing"
  fi

  if grep -q "variant=\"warning\"" "$CR"; then
    pass "SWITCHING badge uses warning variant"
  else
    fail "SWITCHING badge not using warning variant"
  fi
fi

# ── 12. On Air camera label ──────────────────────────────────
log "Step 12: On Air camera label fallback"

if [ -f "$CR" ]; then
  if grep -q "'unknown'" "$CR"; then
    pass "Camera label falls back to 'unknown'"
  else
    fail "Camera label fallback missing"
  fi

  if grep -q "camera unknown" "$CR"; then
    pass "Streaming (camera unknown) message exists"
  else
    fail "Camera unknown message missing"
  fi
fi

# ── 13. Keyboard shortcuts use setFeaturedCamera ──────────────
log "Step 13: Keyboard shortcuts"

if [ -f "$CR" ]; then
  if grep -A 20 "handleKeyDown" "$CR" | grep -q "setFeaturedCamera.mutate"; then
    pass "Keyboard shortcuts call setFeaturedCamera.mutate"
  else
    fail "Keyboard shortcuts not using setFeaturedCamera"
  fi

  if grep -q "setFeaturedCamera, clearFeatured" "$CR"; then
    pass "useEffect deps include setFeaturedCamera"
  else
    fail "useEffect deps missing setFeaturedCamera"
  fi
fi

# ── 14. Per-truck isolation ───────────────────────────────────
log "Step 14: Per-truck isolation"

if [ -f "$CR" ]; then
  # Each mutation call includes vehicleId
  COUNT=$(grep -c "vehicleId:" "$CR" || true)
  if [ "$COUNT" -ge 3 ]; then
    pass "vehicleId used in $COUNT locations (per-truck)"
  else
    fail "vehicleId not used enough (per-truck isolation)"
  fi

  # State is keyed by vehicle_id
  if grep -q "\[vehicleId\]:" "$CR" || grep -q "\[variables.vehicleId\]:" "$CR"; then
    pass "State keyed by vehicleId"
  else
    fail "State not keyed by vehicleId"
  fi
fi

# ── 15. Legacy switchCamera removed ───────────────────────────
log "Step 15: Legacy switchCamera removed from usage"

if [ -f "$CR" ]; then
  if grep -q "const switchCamera = useMutation" "$CR"; then
    fail "switchCamera mutation still defined (should be removed)"
  else
    pass "switchCamera mutation removed"
  fi

  if grep -q "switchCamera.mutate" "$CR"; then
    fail "switchCamera.mutate still called"
  else
    pass "switchCamera.mutate not called anywhere"
  fi
fi

# ── 16. TypeScript build check ────────────────────────────────
log "Step 16: TypeScript build check"

if command -v node >/dev/null 2>&1; then
  if cd "$REPO_ROOT/web" && npx tsc --noEmit 2>&1; then
    pass "TypeScript build passes"
  else
    fail "TypeScript build errors"
  fi
else
  warn "Node.js not available — skipping tsc check (source-level checks above substitute)"
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
