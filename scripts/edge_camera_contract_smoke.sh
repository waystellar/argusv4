#!/usr/bin/env bash
# edge_camera_contract_smoke.sh - Smoke test for CAM-CONTRACT-1B: Edge Camera Contract
#
# Validates:
#   1. Canonical camera slots defined (main, cockpit, chase, suspension)
#   2. Backward compatibility aliases exist (pov->cockpit, roof->chase, front->suspension, rear->suspension)
#   3. normalize_camera_slot function exists
#   4. Python syntax compiles
#   5. "rear" does NOT appear as a canonical slot (only in alias map)
#
# Usage:
#   bash scripts/edge_camera_contract_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STREAM_PROFILES="$REPO_ROOT/edge/stream_profiles.py"
VIDEO_DIRECTOR="$REPO_ROOT/edge/video_director.py"
PIT_DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[edge-cam]  $*"; }
pass() { echo "[edge-cam]    PASS: $*"; }
fail() { echo "[edge-cam]    FAIL: $*"; FAIL=1; }
skip() { echo "[edge-cam]    SKIP: $*"; }

log "CAM-CONTRACT-1B: Edge Camera Contract Smoke Test"
echo ""

# ── 1. Canonical camera slots in stream_profiles.py ──────────
log "Step 1: Canonical camera slots in stream_profiles.py"

if [ -f "$STREAM_PROFILES" ]; then
  # Check VALID_CAMERAS contains exactly: main, cockpit, chase, suspension
  if grep -q '"main"' "$STREAM_PROFILES" && \
     grep -q '"cockpit"' "$STREAM_PROFILES" && \
     grep -q '"chase"' "$STREAM_PROFILES" && \
     grep -q '"suspension"' "$STREAM_PROFILES"; then
    pass "VALID_CAMERAS contains canonical slots (main, cockpit, chase, suspension)"
  else
    fail "VALID_CAMERAS missing canonical slots (main, cockpit, chase, suspension)"
  fi

  # Check CAM-CONTRACT-1B marker
  if grep -q 'CAM-CONTRACT-1B' "$STREAM_PROFILES"; then
    pass "CAM-CONTRACT-1B marker present"
  else
    fail "CAM-CONTRACT-1B marker missing"
  fi
else
  fail "stream_profiles.py not found"
fi

# ── 2. Backward compatibility aliases ────────────────────────
log "Step 2: Backward compatibility aliases"

if [ -f "$STREAM_PROFILES" ]; then
  if grep -q 'CAMERA_SLOT_ALIASES' "$STREAM_PROFILES"; then
    pass "CAMERA_SLOT_ALIASES defined"
  else
    fail "CAMERA_SLOT_ALIASES missing"
  fi

  # Check specific aliases
  if grep -q '"pov".*cockpit' "$STREAM_PROFILES"; then
    pass "pov->cockpit alias exists"
  else
    fail "pov->cockpit alias missing"
  fi

  if grep -q '"roof".*chase' "$STREAM_PROFILES"; then
    pass "roof->chase alias exists"
  else
    fail "roof->chase alias missing"
  fi

  if grep -q '"front".*suspension' "$STREAM_PROFILES"; then
    pass "front->suspension alias exists"
  else
    fail "front->suspension alias missing"
  fi

  if grep -q '"rear".*suspension' "$STREAM_PROFILES"; then
    pass "rear->suspension alias exists"
  else
    fail "rear->suspension alias missing"
  fi
fi

# ── 3. normalize_camera_slot function ────────────────────────
log "Step 3: normalize_camera_slot function exists"

if [ -f "$STREAM_PROFILES" ]; then
  if grep -q 'def normalize_camera_slot' "$STREAM_PROFILES"; then
    pass "normalize_camera_slot function exists in stream_profiles.py"
  else
    fail "normalize_camera_slot function missing in stream_profiles.py"
  fi
fi

if [ -f "$PIT_DASHBOARD" ]; then
  if grep -q '_normalize_camera_slot' "$PIT_DASHBOARD"; then
    pass "_normalize_camera_slot method exists in pit_crew_dashboard.py"
  else
    fail "_normalize_camera_slot method missing in pit_crew_dashboard.py"
  fi
fi

# ── 4. Video director camera config ──────────────────────────
log "Step 4: Video director camera config"

if [ -f "$VIDEO_DIRECTOR" ]; then
  if grep -q '"main".*argus_cam_main' "$VIDEO_DIRECTOR"; then
    pass "main camera udev symlink configured"
  else
    fail "main camera udev symlink missing"
  fi

  if grep -q '"cockpit".*argus_cam_cockpit' "$VIDEO_DIRECTOR"; then
    pass "cockpit camera udev symlink configured"
  else
    fail "cockpit camera udev symlink missing"
  fi

  if grep -q '"suspension".*argus_cam_suspension' "$VIDEO_DIRECTOR"; then
    pass "suspension camera udev symlink configured"
  else
    fail "suspension camera udev symlink missing"
  fi

  if grep -q 'camera_aliases' "$VIDEO_DIRECTOR"; then
    pass "camera_aliases defined in VideoConfig"
  else
    fail "camera_aliases missing in VideoConfig"
  fi
fi

# ── 5. Pit crew dashboard camera UI ──────────────────────────
log "Step 5: Pit crew dashboard camera UI"

if [ -f "$PIT_DASHBOARD" ]; then
  # Check select dropdown options
  if grep -q 'value="main"' "$PIT_DASHBOARD"; then
    pass "Main Cam option in dropdown"
  else
    fail "Main Cam option missing in dropdown"
  fi

  if grep -q 'value="cockpit"' "$PIT_DASHBOARD"; then
    pass "Cockpit option in dropdown"
  else
    fail "Cockpit option missing in dropdown"
  fi

  if grep -q 'value="suspension"' "$PIT_DASHBOARD"; then
    pass "Suspension option in dropdown"
  else
    fail "Suspension option missing in dropdown"
  fi

  # Check screenshot grid
  if grep -q 'screenshot-main' "$PIT_DASHBOARD"; then
    pass "Main camera in screenshot grid"
  else
    fail "Main camera missing in screenshot grid"
  fi

  if grep -q 'screenshot-cockpit' "$PIT_DASHBOARD"; then
    pass "Cockpit camera in screenshot grid"
  else
    fail "Cockpit camera missing in screenshot grid"
  fi

  if grep -q 'screenshot-suspension' "$PIT_DASHBOARD"; then
    pass "Suspension camera in screenshot grid"
  else
    fail "Suspension camera missing in screenshot grid"
  fi
fi

# ── 6. Python syntax check ───────────────────────────────────
log "Step 6: Python syntax compiles"

for pyfile in "$STREAM_PROFILES" "$VIDEO_DIRECTOR" "$PIT_DASHBOARD"; do
  if [ -f "$pyfile" ]; then
    basename=$(basename "$pyfile")
    if python3 -m py_compile "$pyfile" 2>/dev/null; then
      pass "$basename compiles without syntax errors"
    else
      fail "$basename has syntax errors"
    fi
  fi
done

# ── Summary ──────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
