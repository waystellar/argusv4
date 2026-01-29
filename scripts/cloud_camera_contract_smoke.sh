#!/usr/bin/env bash
# cloud_camera_contract_smoke.sh - Smoke test for CAM-CONTRACT-1B: Cloud Camera Contract
#
# Validates:
#   1. CANONICAL_CAMERAS contains (main, cockpit, chase, suspension)
#   2. VALID_CAMERAS set matches canonical slots
#   3. CAMERA_SLOT_ALIASES exists for backward compatibility (including rear->suspension)
#   4. normalize_camera_slot function exists
#   5. Switch command validation accepts both canonical and legacy names
#
# Usage:
#   bash scripts/cloud_camera_contract_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRODUCTION_PY="$REPO_ROOT/cloud/app/routes/production.py"
FAIL=0

log()  { echo "[cloud-cam]  $*"; }
pass() { echo "[cloud-cam]    PASS: $*"; }
fail() { echo "[cloud-cam]    FAIL: $*"; FAIL=1; }
skip() { echo "[cloud-cam]    SKIP: $*"; }

log "CAM-CONTRACT-1B: Cloud Camera Contract Smoke Test"
echo ""

# ── 1. CANONICAL_CAMERAS contains canonical slots ────────────
log "Step 1: CANONICAL_CAMERAS contains canonical slots"

if [ -f "$PRODUCTION_PY" ]; then
  # Check CANONICAL_CAMERAS list
  if grep -q 'CANONICAL_CAMERAS.*=.*\[' "$PRODUCTION_PY"; then
    if grep -A1 'CANONICAL_CAMERAS' "$PRODUCTION_PY" | grep -q 'main'; then
      pass "CANONICAL_CAMERAS includes 'main'"
    else
      fail "CANONICAL_CAMERAS missing 'main'"
    fi

    if grep -A1 'CANONICAL_CAMERAS' "$PRODUCTION_PY" | grep -q 'cockpit'; then
      pass "CANONICAL_CAMERAS includes 'cockpit'"
    else
      fail "CANONICAL_CAMERAS missing 'cockpit'"
    fi

    if grep -A1 'CANONICAL_CAMERAS' "$PRODUCTION_PY" | grep -q 'chase'; then
      pass "CANONICAL_CAMERAS includes 'chase'"
    else
      fail "CANONICAL_CAMERAS missing 'chase'"
    fi

    if grep -A1 'CANONICAL_CAMERAS' "$PRODUCTION_PY" | grep -q 'suspension'; then
      pass "CANONICAL_CAMERAS includes 'suspension'"
    else
      fail "CANONICAL_CAMERAS missing 'suspension'"
    fi
  else
    fail "CANONICAL_CAMERAS not defined"
  fi

  # Check CAM-CONTRACT-1B marker
  if grep -q 'CAM-CONTRACT-1B' "$PRODUCTION_PY"; then
    pass "CAM-CONTRACT-1B marker present"
  else
    fail "CAM-CONTRACT-1B marker missing"
  fi
else
  fail "production.py not found"
fi

# ── 2. VALID_CAMERAS set matches canonical slots ─────────────
log "Step 2: VALID_CAMERAS contains canonical slots"

if [ -f "$PRODUCTION_PY" ]; then
  # VALID_CAMERAS should be a set with main, cockpit, chase, suspension
  if grep -q 'VALID_CAMERAS.*=.*{' "$PRODUCTION_PY"; then
    pass "VALID_CAMERAS is defined as a set"
  else
    fail "VALID_CAMERAS not defined as a set"
  fi

  # Verify 'suspension' is in VALID_CAMERAS
  if grep 'VALID_CAMERAS.*=' "$PRODUCTION_PY" | grep -q '"suspension"'; then
    pass "VALID_CAMERAS contains 'suspension'"
  else
    fail "VALID_CAMERAS should contain 'suspension'"
  fi
fi

# ── 3. Backward compatibility aliases ────────────────────────
log "Step 3: Backward compatibility aliases"

if [ -f "$PRODUCTION_PY" ]; then
  if grep -q 'CAMERA_SLOT_ALIASES' "$PRODUCTION_PY"; then
    pass "CAMERA_SLOT_ALIASES defined"
  else
    fail "CAMERA_SLOT_ALIASES missing"
  fi

  # Check specific aliases
  if grep -q '"pov".*cockpit' "$PRODUCTION_PY"; then
    pass "pov->cockpit alias exists"
  else
    fail "pov->cockpit alias missing"
  fi

  if grep -q '"roof".*chase' "$PRODUCTION_PY"; then
    pass "roof->chase alias exists"
  else
    fail "roof->chase alias missing"
  fi

  if grep -q '"front".*suspension' "$PRODUCTION_PY"; then
    pass "front->suspension alias exists"
  else
    fail "front->suspension alias missing"
  fi

  if grep -q '"rear".*suspension' "$PRODUCTION_PY"; then
    pass "rear->suspension alias exists (backward compat)"
  else
    fail "rear->suspension alias missing"
  fi

  # Check ALL_VALID_CAMERAS union for validation
  if grep -q 'ALL_VALID_CAMERAS' "$PRODUCTION_PY"; then
    pass "ALL_VALID_CAMERAS union defined for validation"
  else
    fail "ALL_VALID_CAMERAS union missing"
  fi
fi

# ── 4. normalize_camera_slot function ────────────────────────
log "Step 4: normalize_camera_slot function"

if [ -f "$PRODUCTION_PY" ]; then
  if grep -q 'def normalize_camera_slot' "$PRODUCTION_PY"; then
    pass "normalize_camera_slot function exists"
  else
    fail "normalize_camera_slot function missing"
  fi
fi

# ── 5. Switch command validation ─────────────────────────────
log "Step 5: Switch command accepts canonical and legacy names"

if [ -f "$PRODUCTION_PY" ]; then
  # Check that set_active_camera validation uses ALL_VALID_CAMERAS
  if grep -A5 'set_active_camera' "$PRODUCTION_PY" | grep -q 'ALL_VALID_CAMERAS'; then
    pass "set_active_camera validates against ALL_VALID_CAMERAS"
  else
    fail "set_active_camera should validate against ALL_VALID_CAMERAS"
  fi

  # Check that normalization is applied
  if grep -A10 'set_active_camera' "$PRODUCTION_PY" | grep -q 'normalize_camera_slot'; then
    pass "set_active_camera normalizes camera name"
  else
    fail "set_active_camera should normalize camera name"
  fi
fi

# ── 6. Docstring updated ─────────────────────────────────────
log "Step 6: Docstrings updated with new camera names"

if [ -f "$PRODUCTION_PY" ]; then
  if grep -q 'main|cockpit|chase|suspension' "$PRODUCTION_PY"; then
    pass "Docstring shows canonical camera names"
  else
    fail "Docstring should show canonical camera names"
  fi
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
