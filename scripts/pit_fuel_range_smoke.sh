#!/usr/bin/env bash
# pit_fuel_range_smoke.sh — Smoke test for Pit Crew Fuel + Range feature (PIT-FUEL-2)
#
# Validates (source-level):
#   1. Default tank_capacity_gal is 95 (not 35)
#   2. No clamp to 35 anywhere (regression guard)
#   3. Tank capacity range 1-250 (HTML, JS, Python)
#   4. MPG range 0.1-30 (HTML, JS, Python)
#   5. Range remaining = max(0, fuel * MPG - trip_miles)
#   6. Trip miles accumulation from GPS
#   7. Trip reset endpoint
#   8. Range & Trip UI panel
#   9. Fuel + trip state persistence
#  10. Old range values removed (regression)
#  11. Python syntax check
#
# Usage:
#   bash scripts/pit_fuel_range_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[pit-fuel-range] $*"; }
pass() { echo "[pit-fuel-range]   PASS: $*"; }
fail() { echo "[pit-fuel-range]   FAIL: $*"; FAIL=1; }

# ── 1. Default tank capacity is 95 (not 35) ────────────────
log "Step 1: Default tank_capacity_gal is 95 (via constant)"

if [ -f "$DASHBOARD" ]; then
  if grep -q "DEFAULT_TANK_CAPACITY_GAL = 95.0" "$DASHBOARD"; then
    pass "DEFAULT_TANK_CAPACITY_GAL = 95.0 defined"
  elif grep -q "'tank_capacity_gal': DEFAULT_TANK_CAPACITY_GAL" "$DASHBOARD"; then
    pass "Default tank_capacity_gal uses DEFAULT_TANK_CAPACITY_GAL constant"
  else
    fail "Default tank_capacity_gal is not 95.0"
  fi

  # HTML input uses placeholder or value for 95 default (value set from API on load)
  if grep 'id="tankCapacityInput"' "$DASHBOARD" | grep -q 'value="95"\|placeholder="95"'; then
    pass "HTML input default/placeholder is 95"
  else
    fail "HTML input default/placeholder is not 95"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. No clamp to 35 anywhere (regression guard) ──────────
log "Step 2: No clamp to 35 gallons anywhere"

if [ -f "$DASHBOARD" ]; then
  # No DEFAULT_TANK_CAPACITY_GAL = 35
  if grep -q "DEFAULT_TANK_CAPACITY_GAL = 35" "$DASHBOARD"; then
    fail "DEFAULT_TANK_CAPACITY_GAL still set to 35"
  else
    pass "DEFAULT_TANK_CAPACITY_GAL is not 35"
  fi

  # No HTML value="35" on tank input
  if grep 'id="tankCapacityInput"' "$DASHBOARD" | grep -q 'value="35"'; then
    fail "HTML tankCapacityInput still has value=35"
  else
    pass "HTML tankCapacityInput does not have value=35"
  fi

  # No JS fallback || 35
  if grep -q '|| 35' "$DASHBOARD"; then
    fail "JS still has || 35 fallback"
  else
    pass "No JS || 35 fallback"
  fi

  # MAX_TANK_CAPACITY_GAL must be 250
  if grep -q "MAX_TANK_CAPACITY_GAL = 250.0" "$DASHBOARD"; then
    pass "MAX_TANK_CAPACITY_GAL = 250"
  else
    fail "MAX_TANK_CAPACITY_GAL is not 250"
  fi
fi

# ── 3. Tank capacity range 1-250 (HTML, JS, Python) ────────
log "Step 3: Tank capacity range 1-250 (HTML, JS, Python)"

if [ -f "$DASHBOARD" ]; then
  if grep 'id="tankCapacityInput"' "$DASHBOARD" | grep -q 'min="1"'; then
    pass "HTML input min=1"
  else
    fail "HTML input min is not 1"
  fi

  if grep 'id="tankCapacityInput"' "$DASHBOARD" | grep -q 'max="250"'; then
    pass "HTML input max=250"
  else
    fail "HTML input max is not 250"
  fi

  if grep -q 'tankCapacity < 1 || tankCapacity > 250' "$DASHBOARD"; then
    pass "JS validates tank capacity 1-250"
  else
    fail "JS tank capacity validation not 1-250"
  fi

  if grep -q 'new_capacity < MIN_TANK_CAPACITY_GAL or new_capacity > MAX_TANK_CAPACITY_GAL' "$DASHBOARD"; then
    pass "Python validates tank capacity using MIN/MAX constants"
  elif grep -q 'new_capacity < 1 or new_capacity > 250' "$DASHBOARD"; then
    pass "Python validates tank capacity 1-250 (hardcoded)"
  else
    fail "Python tank capacity validation not 1-250"
  fi

  if grep -q 'Tank capacity must be 1-250 gallons' "$DASHBOARD"; then
    pass "JS error message says 1-250"
  else
    fail "JS error message does not say 1-250"
  fi
fi

# ── 4. MPG range 0.1-30 (HTML, JS, Python) ─────────────────
log "Step 4: MPG range 0.1-30 (HTML, JS, Python)"

if [ -f "$DASHBOARD" ]; then
  if grep 'id="fuelMpgInput"' "$DASHBOARD" | grep -q 'min="0.1"'; then
    pass "HTML MPG input min=0.1"
  else
    fail "HTML MPG input min is not 0.1"
  fi

  if grep 'id="fuelMpgInput"' "$DASHBOARD" | grep -q 'max="30"'; then
    pass "HTML MPG input max=30"
  else
    fail "HTML MPG input max is not 30"
  fi

  if grep -q 'mpg < 0.1 || mpg > 30' "$DASHBOARD"; then
    pass "JS validates MPG 0.1-30"
  else
    fail "JS MPG validation not 0.1-30"
  fi

  if grep -q 'new_rate < 0.1 or new_rate > 30' "$DASHBOARD"; then
    pass "Python validates MPG 0.1-30"
  else
    fail "Python MPG validation not 0.1-30"
  fi

  if grep -q 'between 0.1 and 30' "$DASHBOARD"; then
    pass "Python error message says 0.1-30"
  else
    fail "Python error message does not say 0.1-30"
  fi

  if grep -q 'MPG must be 0.1-30' "$DASHBOARD"; then
    pass "JS error message says 0.1-30"
  else
    fail "JS error message does not say 0.1-30"
  fi

  if grep -q "'consumption_rate_mpg': 2.0" "$DASHBOARD"; then
    pass "Default MPG is 2.0"
  else
    fail "Default MPG not 2.0"
  fi
fi

# ── 5. Range remaining = max(0, fuel*MPG - trip_miles) ──────
log "Step 5: Range = max(0, fuel*MPG - trip_miles)"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'estimated_range = current_fuel \* consumption_rate' "$DASHBOARD"; then
    pass "estimated_range = current_fuel * consumption_rate"
  else
    fail "estimated_range calculation missing"
  fi

  if grep -q 'max(0, estimated_range - trip_miles)' "$DASHBOARD"; then
    pass "range_miles_remaining = max(0, estimated_range - trip_miles)"
  else
    fail "range_miles_remaining not subtracting trip_miles"
  fi

  if grep -q 'consumption_rate > 0' "$DASHBOARD"; then
    pass "division-by-zero guard exists"
  else
    fail "missing consumption_rate > 0 guard"
  fi
fi

# ── 6. Trip miles accumulation from GPS ─────────────────────
log "Step 6: GPS trip miles accumulation"

if [ -f "$DASHBOARD" ]; then
  if grep -q "trip_miles" "$DASHBOARD"; then
    pass "Dashboard has trip_miles field"
  else
    fail "Dashboard missing trip_miles"
  fi

  if grep -q "_trip_state\['trip_miles'\] += distance_mi" "$DASHBOARD"; then
    pass "GPS receiver accumulates trip miles"
  else
    fail "GPS receiver not accumulating trip miles"
  fi

  if grep -q 'distance_mi < 0.5' "$DASHBOARD"; then
    pass "GPS jump filter at 0.5 miles per update"
  else
    fail "Missing GPS jump filter"
  fi

  if grep -q 'distance_mi > 0.001' "$DASHBOARD"; then
    pass "GPS jitter filter at 0.001 miles"
  else
    fail "Missing GPS jitter filter"
  fi
fi

# ── 7. Trip reset endpoint ──────────────────────────────────
log "Step 7: Trip reset API"

if [ -f "$DASHBOARD" ]; then
  if grep -q "trip-reset" "$DASHBOARD"; then
    pass "Trip reset endpoint exists"
  else
    fail "Missing trip-reset endpoint"
  fi

  if grep -q "handle_trip_reset" "$DASHBOARD"; then
    pass "Trip reset handler exists"
  else
    fail "Missing trip reset handler"
  fi

  if grep -q "trip_miles.*=.*0.0" "$DASHBOARD"; then
    pass "Trip reset sets miles to 0"
  else
    fail "Trip reset missing zero assignment"
  fi
fi

# ── 8. Range & Trip UI panel ────────────────────────────────
log "Step 8: Range & Trip UI"

if [ -f "$DASHBOARD" ]; then
  for el_id in 'rangePanel' 'rangeMpgAvg' 'rangeFuelRemaining' 'rangeEstRemaining' 'tripMilesValue' 'tripStartTime'; do
    if grep -q "id=\"$el_id\"" "$DASHBOARD"; then
      pass "UI has $el_id element"
    else
      fail "UI missing $el_id element"
    fi
  done

  if grep -q 'resetTripMiles' "$DASHBOARD"; then
    pass "Reset Trip Miles button exists"
  else
    fail "Missing Reset Trip Miles button"
  fi
fi

# ── 9. Fuel + trip state persistence ────────────────────────
log "Step 9: State persistence"

if [ -f "$DASHBOARD" ]; then
  for fn in '_save_fuel_state' '_load_fuel_state' '_save_trip_state' '_load_trip_state'; do
    if grep -q "def $fn" "$DASHBOARD"; then
      pass "$fn function exists"
    else
      fail "Missing $fn"
    fi
  done

  if grep -q 'fuel_state.json' "$DASHBOARD"; then
    pass "Fuel state persisted to fuel_state.json"
  else
    fail "Missing fuel_state.json persistence"
  fi

  if grep -q 'trip_state.json' "$DASHBOARD"; then
    pass "Trip state persisted to trip_state.json"
  else
    fail "Missing trip_state.json persistence"
  fi

  # Safe upgrade: _load_fuel_state merges saved keys over defaults
  if grep -A15 'def _load_fuel_state' "$DASHBOARD" | grep -q 'saved_state'; then
    pass "Fuel state load merges saved keys (safe upgrade)"
  else
    fail "Fuel state load may not safely upgrade"
  fi
fi

# ── 10. Old range values removed (regression) ───────────────
log "Step 10: Old range values removed"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'between 5 and 250' "$DASHBOARD"; then
    fail "Old 'between 5 and 250' error message still present"
  else
    pass "No old '5 and 250' error messages"
  fi

  if grep -q 'between 0.5 and 10.0' "$DASHBOARD"; then
    fail "Old 'between 0.5 and 10.0' error message still present"
  else
    pass "No old '0.5 and 10.0' error messages"
  fi

  if grep 'id="tankCapacityInput"' "$DASHBOARD" | grep -q 'min="5"'; then
    fail "HTML still has min=5 on tank input"
  else
    pass "No old min=5 on tank input"
  fi

  if grep 'id="fuelMpgInput"' "$DASHBOARD" | grep -q 'max="10.0"'; then
    fail "HTML still has max=10.0 on MPG input"
  else
    pass "No old max=10.0 on MPG input"
  fi

  if grep 'id="tankCapacityInput"' "$DASHBOARD" | grep -q 'max="35"'; then
    fail "HTML still has max=35 on tank input"
  else
    pass "No old max=35 on tank input"
  fi
fi

# ── 11. Python syntax check ─────────────────────────────────
log "Step 11: Python syntax"

if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "Python syntax valid"
else
  fail "Python syntax error"
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
