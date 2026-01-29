#!/usr/bin/env bash
# pit_can_placeholders_smoke.sh - Smoke test for PIT-CAN-1: Phantom 32F Fix
#
# Validates:
#   1. TelemetryState CAN fields are Optional[float] = None (not 0.0)
#   2. to_dict() safely handles None values
#   3. JavaScript UI checks for null before rendering temperatures
#   4. Python syntax compiles
#
# Usage:
#   bash scripts/pit_can_placeholders_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[pit-can-placeholders]  $*"; }
pass() { echo "[pit-can-placeholders]    PASS: $*"; }
fail() { echo "[pit-can-placeholders]    FAIL: $*"; FAIL=1; }
skip() { echo "[pit-can-placeholders]    SKIP: $*"; }

log "PIT-CAN-1: Phantom 32F Placeholders Smoke Test"
echo ""

# ── 1. TelemetryState CAN fields default to None ────────────────
log "Step 1: TelemetryState CAN fields default to None (not 0.0)"

if [ -f "$PIT_DASH" ]; then
  # Check coolant_temp is Optional[float] = None
  if grep -q 'coolant_temp: Optional\[float\] = None' "$PIT_DASH"; then
    pass "coolant_temp: Optional[float] = None"
  else
    fail "coolant_temp is NOT Optional[float] = None (may show phantom 32F)"
  fi

  # Check oil_temp is Optional[float] = None
  if grep -q 'oil_temp: Optional\[float\] = None' "$PIT_DASH"; then
    pass "oil_temp: Optional[float] = None"
  else
    fail "oil_temp is NOT Optional[float] = None (may show phantom 32F)"
  fi

  # Check oil_pressure is Optional[float] = None
  if grep -q 'oil_pressure: Optional\[float\] = None' "$PIT_DASH"; then
    pass "oil_pressure: Optional[float] = None"
  else
    fail "oil_pressure is NOT Optional[float] = None"
  fi

  # Check rpm is Optional[float] = None
  if grep -q 'rpm: Optional\[float\] = None' "$PIT_DASH"; then
    pass "rpm: Optional[float] = None"
  else
    fail "rpm is NOT Optional[float] = None"
  fi

  # Check PIT-CAN-1 marker present
  if grep -q 'PIT-CAN-1' "$PIT_DASH"; then
    pass "PIT-CAN-1 marker present in code"
  else
    fail "PIT-CAN-1 marker missing"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. to_dict() safely handles None values ─────────────────────
log "Step 2: to_dict() safely handles None values"

if [ -f "$PIT_DASH" ]; then
  # Check safe_round helper exists (defined inside to_dict, ~10 lines in)
  if grep -A 15 'def to_dict' "$PIT_DASH" | grep -q 'safe_round'; then
    pass "to_dict uses safe_round helper for None handling"
  else
    fail "to_dict missing safe_round helper"
  fi

  # Check safe_round checks for None
  if grep -A 3 'def safe_round' "$PIT_DASH" | grep -q 'if val is not None'; then
    pass "safe_round checks for None"
  else
    fail "safe_round does not check for None"
  fi
fi

# ── 3. JavaScript UI checks for null before rendering ───────────
log "Step 3: JavaScript UI checks for null before rendering temperatures"

if [ -f "$PIT_DASH" ]; then
  # Check coolant gauge checks for null
  if grep -q "data.coolant_temp !== null && data.coolant_temp !== undefined" "$PIT_DASH"; then
    pass "UI checks coolant_temp for null/undefined"
  else
    fail "UI does NOT check coolant_temp for null"
  fi

  # Check oil_temp gauge checks for null
  if grep -q "data.oil_temp !== null && data.oil_temp !== undefined" "$PIT_DASH"; then
    pass "UI checks oil_temp for null/undefined"
  else
    fail "UI does NOT check oil_temp for null"
  fi

  # Check oil_pressure gauge checks for null
  if grep -q "data.oil_pressure !== null && data.oil_pressure !== undefined" "$PIT_DASH"; then
    pass "UI checks oil_pressure for null/undefined"
  else
    fail "UI does NOT check oil_pressure for null"
  fi

  # Check RPM display checks for null
  if grep -q "data.rpm !== null && data.rpm !== undefined" "$PIT_DASH"; then
    pass "UI checks rpm for null/undefined"
  else
    fail "UI does NOT check rpm for null"
  fi

  # Check that we show '--' for null values
  if grep -q "textContent = '--'" "$PIT_DASH"; then
    pass "UI displays '--' placeholder for null values"
  else
    fail "UI missing '--' placeholder display"
  fi
fi

# ── 4. No default 0.0 initializations for temp fields ───────────
log "Step 4: No default 0.0 initializations for CAN temp fields"

if [ -f "$PIT_DASH" ]; then
  # Make sure coolant_temp doesn't have = 0.0 or = 0
  if grep -E 'coolant_temp.*=.*0\.0|coolant_temp.*= 0[^.]' "$PIT_DASH" | grep -v 'Optional' | grep -v '#' | grep -qv 'None'; then
    fail "coolant_temp still has default 0.0 somewhere"
  else
    pass "coolant_temp has no default 0.0 initialization"
  fi

  # Make sure oil_temp doesn't have = 0.0
  if grep -E 'oil_temp.*=.*0\.0|oil_temp.*= 0[^.]' "$PIT_DASH" | grep -v 'Optional' | grep -v '#' | grep -qv 'None'; then
    fail "oil_temp still has default 0.0 somewhere"
  else
    pass "oil_temp has no default 0.0 initialization"
  fi
fi

# ── 5. Python syntax check ──────────────────────────────────────
log "Step 5: Python syntax compiles"

if python3 -m py_compile "$PIT_DASH" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles without syntax errors"
else
  fail "pit_crew_dashboard.py has syntax errors"
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
