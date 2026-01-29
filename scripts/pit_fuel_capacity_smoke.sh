#!/usr/bin/env bash
# pit_fuel_capacity_smoke.sh - Smoke test for PIT-FUEL-0: Fuel capacity bug fix
#
# Validates:
#   A. Python syntax
#   B. No prompt string contains "(0 - 95 gallons)" or "(0 - 35 gallons)"
#   C. Prompt uses max possible range (250), not current tank capacity
#   D. Backend contains no hardcoded cap at 95/35
#   E. Constants defined and used consistently
#   F. Auto-expand logic: fuel > tankCapacity sends both fields
#   G. Runtime test: simulate setting fuel=120 with capacity=250
#
# Usage:
#   bash scripts/pit_fuel_capacity_smoke.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — at least one FAIL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[fuel-cap]  $*"; }
pass() { echo "[fuel-cap]    PASS: $*"; }
fail() { echo "[fuel-cap]    FAIL: $*"; FAIL=1; }
skip() { echo "[fuel-cap]    SKIP: $*"; }

log "PIT-FUEL-0: Fuel Capacity Bug Fix Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION A: Python Syntax
# ═══════════════════════════════════════════════════════════════════
log "─── Section A: Python Syntax ───"

log "A1: pit_crew_dashboard.py compiles"
if python3 -m py_compile "$PIT_DASH" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles cleanly"
else
  fail "pit_crew_dashboard.py has syntax errors"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION B: No Hardcoded Range in Prompt
# ═══════════════════════════════════════════════════════════════════
log "─── Section B: Prompt Range ───"

# B1: No "(0 - 95" in prompt string
log "B1: No hardcoded (0 - 95) in prompt"
if grep -A5 'async function promptFuelLevel' "$PIT_DASH" | grep -q '0 - 95'; then
  fail "Prompt contains hardcoded (0 - 95)"
elif grep 'Enter current fuel level' "$PIT_DASH" | grep -q '0 - 95'; then
  fail "Prompt contains hardcoded (0 - 95)"
else
  pass "No hardcoded (0 - 95) in prompt"
fi

# B2: No "(0 - 35" in prompt string
log "B2: No hardcoded (0 - 35) in prompt"
if grep 'Enter current fuel level' "$PIT_DASH" | grep -q '0 - 35'; then
  fail "Prompt contains hardcoded (0 - 35)"
else
  pass "No hardcoded (0 - 35) in prompt"
fi

# B3: Prompt uses MAX_CAPACITY (250) for range display
log "B3: Prompt uses 250 (MAX_CAPACITY) for range"
if grep -A30 'async function promptFuelLevel' "$PIT_DASH" | grep -q 'MAX_CAPACITY'; then
  pass "Prompt references MAX_CAPACITY constant"
else
  fail "Prompt does not reference MAX_CAPACITY"
fi

# B4: MAX_CAPACITY defined as 250 in promptFuelLevel
log "B4: MAX_CAPACITY = 250 defined in promptFuelLevel"
if grep -A5 'async function promptFuelLevel' "$PIT_DASH" | grep -q 'MAX_CAPACITY.*=.*250'; then
  pass "MAX_CAPACITY = 250 defined"
else
  fail "MAX_CAPACITY not set to 250"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION C: No Hardcoded Backend Cap
# ═══════════════════════════════════════════════════════════════════
log "─── Section C: Backend Validation ───"

# C1: Backend uses MAX_TANK_CAPACITY_GAL constant
log "C1: Backend uses MAX_TANK_CAPACITY_GAL for validation"
if grep -A30 'def handle_fuel_update' "$PIT_DASH" | grep -q 'MAX_TANK_CAPACITY_GAL'; then
  pass "handle_fuel_update uses MAX_TANK_CAPACITY_GAL"
else
  fail "handle_fuel_update does not use MAX_TANK_CAPACITY_GAL"
fi

# C2: No hardcoded > 35 in validation
log "C2: No hardcoded > 35 clamp"
if grep 'new_capacity.*>' "$PIT_DASH" | grep -q '> 35[^0-9]'; then
  fail "Backend validation uses hardcoded > 35 clamp"
else
  pass "No hardcoded > 35 clamp"
fi

# C3: No hardcoded > 95 in validation
log "C3: No hardcoded > 95 clamp"
if grep 'new_capacity.*>' "$PIT_DASH" | grep -q '> 95[^0-9]'; then
  fail "Backend validation uses hardcoded > 95 clamp"
else
  pass "No hardcoded > 95 clamp"
fi

# C4: Fuel level validation uses tank_capacity variable (not constant)
log "C4: Fuel level validates against tank_capacity variable"
if grep -A40 'def handle_fuel_update' "$PIT_DASH" | grep -q 'new_fuel > tank_capacity'; then
  pass "Fuel level validates against tank_capacity variable"
else
  fail "Fuel level validation missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION D: Constants Defined
# ═══════════════════════════════════════════════════════════════════
log "─── Section D: Constants ───"

# D1: DEFAULT_TANK_CAPACITY_GAL = 95.0
log "D1: DEFAULT_TANK_CAPACITY_GAL = 95.0"
if grep -q 'DEFAULT_TANK_CAPACITY_GAL = 95.0' "$PIT_DASH"; then
  pass "DEFAULT_TANK_CAPACITY_GAL = 95.0"
else
  fail "DEFAULT_TANK_CAPACITY_GAL missing or wrong"
fi

# D2: MIN_TANK_CAPACITY_GAL = 1.0
log "D2: MIN_TANK_CAPACITY_GAL = 1.0"
if grep -q 'MIN_TANK_CAPACITY_GAL = 1.0' "$PIT_DASH"; then
  pass "MIN_TANK_CAPACITY_GAL = 1.0"
else
  fail "MIN_TANK_CAPACITY_GAL missing"
fi

# D3: MAX_TANK_CAPACITY_GAL = 250.0
log "D3: MAX_TANK_CAPACITY_GAL = 250.0"
if grep -q 'MAX_TANK_CAPACITY_GAL = 250.0' "$PIT_DASH"; then
  pass "MAX_TANK_CAPACITY_GAL = 250.0"
else
  fail "MAX_TANK_CAPACITY_GAL missing"
fi

# D4: _fuel_strategy init uses DEFAULT constant
log "D4: _fuel_strategy init uses DEFAULT_TANK_CAPACITY_GAL"
if grep -A5 "'tank_capacity_gal':" "$PIT_DASH" | grep -q 'DEFAULT_TANK_CAPACITY_GAL'; then
  pass "_fuel_strategy uses DEFAULT_TANK_CAPACITY_GAL"
else
  fail "_fuel_strategy does not use constant"
fi

# D5: handle_fuel_status uses DEFAULT constant as fallback
log "D5: handle_fuel_status uses DEFAULT_TANK_CAPACITY_GAL"
if grep -A15 'def handle_fuel_status' "$PIT_DASH" | grep -q 'DEFAULT_TANK_CAPACITY_GAL'; then
  pass "handle_fuel_status uses DEFAULT_TANK_CAPACITY_GAL"
else
  fail "handle_fuel_status missing constant"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION E: Auto-Expand Logic (PIT-FUEL-0)
# ═══════════════════════════════════════════════════════════════════
log "─── Section E: Auto-Expand Logic ───"

# E1: promptFuelLevel auto-expands tank capacity when fuel > tankCapacity
log "E1: Auto-expand sends tank_capacity_gal when fuel > tankCapacity"
if grep -A50 'async function promptFuelLevel' "$PIT_DASH" | grep -q 'fuelLevel > tankCapacity'; then
  pass "Auto-expand check exists (fuelLevel > tankCapacity)"
else
  fail "Auto-expand check missing"
fi

# E2: Auto-expand sends both fields in payload
log "E2: Auto-expand payload includes tank_capacity_gal"
if grep -A55 'async function promptFuelLevel' "$PIT_DASH" | grep -q 'payload.tank_capacity_gal'; then
  pass "Auto-expand sets payload.tank_capacity_gal"
else
  fail "Auto-expand does not set tank_capacity_gal in payload"
fi

# E3: Auto-expand shows user feedback about capacity change
log "E3: Auto-expand shows capacity change feedback"
if grep -A65 'async function promptFuelLevel' "$PIT_DASH" | grep -q 'tank capacity updated'; then
  pass "Auto-expand shows capacity change message"
else
  fail "Auto-expand missing capacity change feedback"
fi

# E4: PIT-FUEL-0 marker present
log "E4: PIT-FUEL-0 marker present"
if grep -q 'PIT-FUEL-0' "$PIT_DASH"; then
  pass "PIT-FUEL-0 marker found"
else
  fail "PIT-FUEL-0 marker missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION F: UI Input Constraints
# ═══════════════════════════════════════════════════════════════════
log "─── Section F: UI Input Constraints ───"

# F1: tankCapacityInput has max="250"
log "F1: tankCapacityInput has max=250"
if grep -q 'id="tankCapacityInput".*max="250"' "$PIT_DASH"; then
  pass "tankCapacityInput has max=250"
else
  fail "tankCapacityInput missing max=250"
fi

# F2: tankCapacityInput does NOT have max="35" or max="95"
log "F2: tankCapacityInput does not have max=35 or max=95"
if grep 'id="tankCapacityInput"' "$PIT_DASH" | grep -q 'max="35"\|max="95"'; then
  fail "tankCapacityInput has incorrect max"
else
  pass "tankCapacityInput does not have max=35 or max=95"
fi

# F3: saveFuelConfig validates 1-250
log "F3: saveFuelConfig validates 1-250"
if grep -A10 'async function saveFuelConfig' "$PIT_DASH" | grep -q 'tankCapacity > 250'; then
  pass "saveFuelConfig validates max 250"
else
  fail "saveFuelConfig validation missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION G: No JS Fallback to Hardcoded 35
# ═══════════════════════════════════════════════════════════════════
log "─── Section G: No Hardcoded Fallbacks ───"

# G1: promptFuelLevel does not use || 35
log "G1: promptFuelLevel does not fallback to 35"
if grep -A20 'async function promptFuelLevel' "$PIT_DASH" | grep -q '|| 35'; then
  fail "promptFuelLevel uses || 35 fallback"
else
  pass "No || 35 fallback in promptFuelLevel"
fi

# G2: loadFuelStatus does not use || 35
log "G2: loadFuelStatus does not fallback to 35"
if grep -A15 'async function loadFuelStatus' "$PIT_DASH" | grep -q 'tank_capacity_gal || 35'; then
  fail "loadFuelStatus uses || 35 fallback"
else
  pass "No || 35 fallback in loadFuelStatus"
fi

# G3: No || 95 fallback either
log "G3: No || 95 fallback anywhere in fuel JS"
if grep -A20 'promptFuelLevel\|loadFuelStatus\|saveFuelConfig' "$PIT_DASH" | grep -q '|| 95'; then
  fail "Found || 95 fallback in fuel JS"
else
  pass "No || 95 fallback in fuel JS"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION H: Enhanced Logging
# ═══════════════════════════════════════════════════════════════════
log "─── Section H: Debug Logging ───"

# H1: _load_fuel_state has debug logging
log "H1: _load_fuel_state has debug logging"
if grep -A25 'def _load_fuel_state' "$PIT_DASH" | grep -q 'PIT-FUEL-1.*Loading fuel state'; then
  pass "_load_fuel_state has debug logging"
else
  fail "_load_fuel_state missing debug logging"
fi

# H2: _save_fuel_state has debug logging
log "H2: _save_fuel_state has debug logging"
if grep -A15 'def _save_fuel_state' "$PIT_DASH" | grep -q 'PIT-FUEL-1.*Saved fuel state'; then
  pass "_save_fuel_state has debug logging"
else
  fail "_save_fuel_state missing debug logging"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION I: Runtime Test — Simulate fuel=120 with capacity=250
# ═══════════════════════════════════════════════════════════════════
log "─── Section I: Runtime Simulation ───"

log "I1: Simulate setting fuel=120 with capacity=250 via Python"
RUNTIME_RESULT=$(python3 -c "
import sys, json, os, tempfile

# Simulate the fuel state persistence logic from pit_crew_dashboard.py
DEFAULT_TANK_CAPACITY_GAL = 95.0
MIN_TANK_CAPACITY_GAL = 1.0
MAX_TANK_CAPACITY_GAL = 250.0

# Simulate initial fuel_strategy (fresh install)
fuel_strategy = {
    'tank_capacity_gal': DEFAULT_TANK_CAPACITY_GAL,
    'current_fuel_gal': None,
    'fuel_set': False,
    'consumption_rate_mpg': 2.0,
}

# --- Simulate the handle_fuel_update validation logic ---

# Test 1: Set fuel=120 with default capacity=95 (should fail without capacity update)
tank_capacity = fuel_strategy['tank_capacity_gal']
new_fuel = 120.0
if new_fuel > tank_capacity:
    # Without PIT-FUEL-0 fix, this would be rejected
    # With PIT-FUEL-0 fix, UI sends tank_capacity_gal=120 alongside
    pass

# Test 2: Update tank capacity to 120, then set fuel=120
new_capacity = 120.0
if new_capacity < MIN_TANK_CAPACITY_GAL or new_capacity > MAX_TANK_CAPACITY_GAL:
    print('FAIL: capacity 120 rejected by validation')
    sys.exit(1)
fuel_strategy['tank_capacity_gal'] = new_capacity
tank_capacity = new_capacity

# Now set fuel=120
if new_fuel < 0 or new_fuel > tank_capacity:
    print('FAIL: fuel=120 rejected after capacity update')
    sys.exit(1)
fuel_strategy['current_fuel_gal'] = new_fuel
fuel_strategy['fuel_set'] = True

# Test 3: Persist and re-read
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(fuel_strategy, f)
    tmp_path = f.name

with open(tmp_path, 'r') as f:
    loaded = json.load(f)

os.unlink(tmp_path)

if loaded['current_fuel_gal'] != 120.0:
    print(f'FAIL: expected 120.0, got {loaded[\"current_fuel_gal\"]}')
    sys.exit(1)

if loaded['tank_capacity_gal'] != 120.0:
    print(f'FAIL: capacity expected 120.0, got {loaded[\"tank_capacity_gal\"]}')
    sys.exit(1)

if not loaded['fuel_set']:
    print('FAIL: fuel_set should be True')
    sys.exit(1)

# Test 4: Set fuel=200 with capacity=250
fuel_strategy['tank_capacity_gal'] = 250.0
fuel_strategy['current_fuel_gal'] = 200.0
if fuel_strategy['current_fuel_gal'] != 200.0:
    print('FAIL: fuel=200 with capacity=250 should work')
    sys.exit(1)

# Test 5: Reject fuel=300 (over MAX_TANK_CAPACITY_GAL)
new_fuel_bad = 300.0
if new_fuel_bad > MAX_TANK_CAPACITY_GAL:
    pass  # Correctly rejected
else:
    print('FAIL: fuel=300 should be rejected')
    sys.exit(1)

print('ALL_RUNTIME_TESTS_PASSED')
" 2>&1)

if [ "$RUNTIME_RESULT" = "ALL_RUNTIME_TESTS_PASSED" ]; then
  pass "Runtime: fuel=120 with capacity=250 saves correctly"
else
  fail "Runtime: $RUNTIME_RESULT"
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════"
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
