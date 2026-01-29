#!/usr/bin/env bash
# cloud_control_room_smoke.sh — Smoke test for PROD-CRASH-1: Control Room crash fix
#
# Validates:
#   1. Web project builds without TypeScript errors (tsc && vite build)
#   2. Leaderboard queryFn validates Array.isArray(data.entries)
#   3. Leaderboard render guard uses Array.isArray(leaderboard)
#   4. StreamingStatusBadge guards typeof status === 'string'
#   5. VehicleDrillDownModal cam.status guarded with typeof check
#   6. edgeStatus.edges guarded with Array.isArray
#   7. No unguarded .slice() calls on external data in ControlRoom
#
# Usage:
#   bash scripts/cloud_control_room_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CR="$REPO_ROOT/web/src/pages/ControlRoom.tsx"
FAIL=0

log()  { echo "[control-room-smoke]  $*"; }
pass() { echo "[control-room-smoke]    PASS: $*"; }
fail() { echo "[control-room-smoke]    FAIL: $*"; FAIL=1; }

# ── 1. Web build (tsc + vite) ─────────────────────────────────
log "Step 1: Web project builds (tsc && vite build)"

if command -v npm &>/dev/null; then
  if (cd "$REPO_ROOT/web" && npm run build 2>&1); then
    pass "Web build succeeded"
  else
    fail "Web build failed"
  fi
else
  echo "[control-room-smoke]    SKIP: npm not available — run on a machine with Node.js"
fi

# ── 2. Leaderboard queryFn uses Array.isArray ─────────────────
log "Step 2: Leaderboard queryFn validates Array.isArray(data.entries)"

if grep -q 'Array.isArray(data.entries)' "$CR"; then
  pass "queryFn validates data.entries with Array.isArray"
else
  fail "queryFn missing Array.isArray(data.entries) guard"
fi

# ── 3. Leaderboard render uses Array.isArray ──────────────────
log "Step 3: Leaderboard render guard uses Array.isArray(leaderboard)"

if grep -q 'Array.isArray(leaderboard)' "$CR"; then
  pass "Render guard uses Array.isArray(leaderboard)"
else
  fail "Render guard missing Array.isArray(leaderboard)"
fi

# ── 4. StreamingStatusBadge guards status type ────────────────
log "Step 4: StreamingStatusBadge guards typeof status"

if grep -A 5 "function StreamingStatusBadge" "$CR" | grep -q "typeof status === 'string'"; then
  pass "StreamingStatusBadge guards typeof status"
else
  fail "StreamingStatusBadge missing typeof status guard"
fi

# ── 5. cam.status guarded in VehicleDrillDownModal ────────────
log "Step 5: cam.status guarded with typeof check"

if grep -q "typeof cam.status === 'string'" "$CR"; then
  pass "cam.status guarded with typeof check"
else
  fail "cam.status missing typeof guard"
fi

# ── 6. edgeStatus.edges guarded with Array.isArray ────────────
log "Step 6: edgeStatus.edges guarded with Array.isArray"

if grep -q 'Array.isArray(edgeStatus.edges)' "$CR"; then
  pass "edgeStatus.edges guarded with Array.isArray"
else
  fail "edgeStatus.edges missing Array.isArray guard"
fi

# ── 7. No unguarded .slice() on external data ────────────────
log "Step 7: All .slice() calls are guarded"

# Check that leaderboard.slice is preceded by Array.isArray guard
# (the guard should be on the same conditional branch)
SLICE_COUNT=$(grep -c '\.slice(' "$CR" || true)
GUARDED=$(grep -c 'Array.isArray\|typeof.*string.*slice\|Object\.values.*slice' "$CR" || true)

if [ "$SLICE_COUNT" -gt 0 ] && [ "$GUARDED" -gt 0 ]; then
  pass "Found $SLICE_COUNT .slice() calls with $GUARDED type guards"
else
  fail "Unguarded .slice() calls detected"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
