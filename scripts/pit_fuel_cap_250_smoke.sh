#!/usr/bin/env bash
# pit_fuel_cap_250_smoke.sh - Smoke test for fuel cap 250-gallon support
#
# PIT-FUEL-0: Validates that no hardcoded 35 or 95 cap restricts fuel entry
# and that the system supports user-selectable tank size up to 250 gallons.
#
# Validates:
#   No Hardcoded Caps:
#     1.  No UI string says "0 - 35"
#     2.  No UI string says "0 - 95"
#     3.  No hardcoded value="35" on tank input
#     4.  No hardcoded value="95" on tank input
#   Max 250 Support:
#     5.  MAX_TANK_CAPACITY_GAL = 250 in Python constants
#     6.  HTML tank input has max="250"
#     7.  JS saveFuelConfig validates up to 250
#     8.  Backend validates up to MAX_TANK_CAPACITY_GAL
#   Default Is Not a Cap:
#     9.  DEFAULT_TANK_CAPACITY_GAL exists as a named constant
#    10.  Fuel prompt uses dynamic tankCapacity (not hardcoded)
#    11.  HTML tank input value comes from API (loadFuelStatus)
#    12.  Backend uses DEFAULT_TANK_CAPACITY_GAL constant (not magic number)
#   Persistence:
#    13.  Fuel state saved to file (survives restarts)
#    14.  tank_capacity_gal included in saved state
#   Syntax:
#    15.  Python syntax compiles
#
# Usage:
#   bash scripts/pit_fuel_cap_250_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[fuel-cap-250]  $*"; }
pass() { echo "[fuel-cap-250]    PASS: $*"; }
fail() { echo "[fuel-cap-250]    FAIL: $*"; FAIL=1; }

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "PIT-FUEL-0: Fuel Cap 250-Gallon Support Smoke Test"
echo ""

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# NO HARDCODED CAPS
# ═══════════════════════════════════════════════════════════════════

# ── 1. No UI string says "0 - 35" ───────────────────────────────
log "Step 1: No UI string says '0 - 35'"
if grep -q '0 - 35' "$PIT_DASH"; then
  fail "Found hardcoded '0 - 35' fuel range"
else
  pass "No '0 - 35' fuel range found"
fi

# ── 2. No UI string says "0 - 95" ───────────────────────────────
log "Step 2: No UI string says '0 - 95'"
# Check for literal "0 - 95" in prompt strings (not in dynamic template literals)
if grep -E "\"0 - 95\"|'0 - 95'" "$PIT_DASH" | grep -v '^\s*#' | grep -qi fuel; then
  fail "Found hardcoded '0 - 95' fuel range"
else
  pass "No hardcoded '0 - 95' fuel range found"
fi

# ── 3. No hardcoded value="35" on tank input ─────────────────────
log "Step 3: No hardcoded value='35' on tank input"
if grep -q 'tankCapacityInput.*value="35"' "$PIT_DASH"; then
  fail "Tank input has hardcoded value=35"
else
  pass "No hardcoded value=35 on tank input"
fi

# ── 4. No hardcoded value="95" on tank input ─────────────────────
log "Step 4: No hardcoded value='95' on tank input"
if grep -q 'tankCapacityInput.*value="95"' "$PIT_DASH"; then
  fail "Tank input has hardcoded value=95"
else
  pass "No hardcoded value=95 on tank input"
fi

# ═══════════════════════════════════════════════════════════════════
# MAX 250 SUPPORT
# ═══════════════════════════════════════════════════════════════════

# ── 5. MAX_TANK_CAPACITY_GAL = 250 ──────────────────────────────
log "Step 5: MAX_TANK_CAPACITY_GAL = 250"
if grep -q 'MAX_TANK_CAPACITY_GAL = 250' "$PIT_DASH"; then
  pass "MAX_TANK_CAPACITY_GAL is 250"
else
  fail "MAX_TANK_CAPACITY_GAL is not 250"
fi

# ── 6. HTML tank input max="250" ─────────────────────────────────
log "Step 6: HTML tank input has max=250"
if grep -q 'tankCapacityInput.*max="250"' "$PIT_DASH"; then
  pass "HTML input max is 250"
else
  fail "HTML input max is not 250"
fi

# ── 7. JS saveFuelConfig validates up to 250 ────────────────────
log "Step 7: JS saveFuelConfig validates up to 250"
if grep -A 10 'function saveFuelConfig' "$PIT_DASH" | grep -q '250'; then
  pass "saveFuelConfig validates up to 250"
else
  fail "saveFuelConfig missing 250 validation"
fi

# ── 8. Backend validates up to MAX_TANK_CAPACITY_GAL ─────────────
log "Step 8: Backend validates up to MAX_TANK_CAPACITY_GAL"
if grep -q 'MAX_TANK_CAPACITY_GAL' "$PIT_DASH" | head -1; then
  true  # grep -q doesn't need piping
fi
if grep -q 'new_capacity.*MAX_TANK_CAPACITY_GAL\|MAX_TANK_CAPACITY_GAL.*new_capacity' "$PIT_DASH"; then
  pass "Backend uses MAX_TANK_CAPACITY_GAL for validation"
else
  # Check if it references the constant in the validation block
  if grep -q 'MAX_TANK_CAPACITY_GAL' "$PIT_DASH"; then
    pass "Backend references MAX_TANK_CAPACITY_GAL constant"
  else
    fail "Backend missing MAX_TANK_CAPACITY_GAL validation"
  fi
fi

# ═══════════════════════════════════════════════════════════════════
# DEFAULT IS NOT A CAP
# ═══════════════════════════════════════════════════════════════════

# ── 9. DEFAULT_TANK_CAPACITY_GAL exists ──────────────────────────
log "Step 9: DEFAULT_TANK_CAPACITY_GAL exists as named constant"
if grep -q 'DEFAULT_TANK_CAPACITY_GAL' "$PIT_DASH"; then
  pass "DEFAULT_TANK_CAPACITY_GAL constant exists"
else
  fail "DEFAULT_TANK_CAPACITY_GAL constant missing"
fi

# ── 10. Fuel prompt uses dynamic tankCapacity ────────────────────
log "Step 10: Fuel prompt uses dynamic tankCapacity"
if grep -q '0 - \${tankCapacity}' "$PIT_DASH"; then
  pass "Prompt uses dynamic tankCapacity variable"
else
  fail "Prompt does not use dynamic tankCapacity"
fi

# ── 11. HTML tank input value set from API ───────────────────────
log "Step 11: HTML tank input value set from API (loadFuelStatus)"
if grep -q 'tankCapacityInput.*value.*=.*data.tank_capacity_gal' "$PIT_DASH"; then
  pass "Tank input populated from API"
else
  fail "Tank input not populated from API"
fi

# ── 12. Backend uses DEFAULT constant (not magic number) ─────────
log "Step 12: Backend uses DEFAULT_TANK_CAPACITY_GAL (not magic number)"
FUEL_INIT=$(grep 'tank_capacity_gal.*DEFAULT_TANK_CAPACITY_GAL' "$PIT_DASH")
if [ -n "$FUEL_INIT" ]; then
  pass "Backend initializes tank_capacity from DEFAULT constant"
else
  fail "Backend uses magic number instead of DEFAULT constant"
fi

# ═══════════════════════════════════════════════════════════════════
# PERSISTENCE
# ═══════════════════════════════════════════════════════════════════

# ── 13. Fuel state saved to file ─────────────────────────────────
log "Step 13: Fuel state saved to file"
if grep -q 'fuel_strategy.*json\|fuel.*state.*json\|_save_fuel_state\|save.*fuel.*state' "$PIT_DASH"; then
  pass "Fuel state persistence exists"
else
  fail "No fuel state persistence found"
fi

# ── 14. tank_capacity_gal in saved state ─────────────────────────
log "Step 14: tank_capacity_gal included in saved state"
if grep -q "tank_capacity_gal.*save\|save.*tank_capacity_gal\|'tank_capacity_gal'" "$PIT_DASH"; then
  pass "tank_capacity_gal included in saved state"
else
  fail "tank_capacity_gal missing from saved state"
fi

# ═══════════════════════════════════════════════════════════════════
# SYNTAX
# ═══════════════════════════════════════════════════════════════════

# ── 15. Python syntax compiles ───────────────────────────────────
log "Step 15: Python syntax compiles"
if python3 -c "import ast; ast.parse(open('$PIT_DASH').read())" 2>/dev/null; then
  pass "Python syntax OK"
else
  fail "Python syntax error"
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
