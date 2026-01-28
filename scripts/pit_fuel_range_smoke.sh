#!/usr/bin/env bash
# pit_fuel_range_smoke.sh — Smoke test for Pit Crew Fuel + Range feature (PIT-1R)
#
# Validates (source-level):
#   1. fuel_tank_capacity_gal configurable up to 250 (not capped at 100)
#   2. fuel_mpg_avg (consumption_rate_mpg) configurable 0.5-10.0
#   3. Trip miles accumulation from GPS
#   4. Range remaining calculation
#   5. Trip reset endpoint
#   6. Range & Trip UI panel
#   7. Persisted trip state
#   8. Python syntax check
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
warn() { echo "[pit-fuel-range]   WARN: $*"; }

# ── 1. Tank capacity allows up to 250 ─────────────────────────────
log "Step 1: Tank capacity range (5-250 gal)"

if [ -f "$DASHBOARD" ]; then
  # Backend validation allows 250
  if grep -q 'new_capacity > 250' "$DASHBOARD" || grep -q "new_capacity < 5 or new_capacity > 250" "$DASHBOARD"; then
    pass "Backend validates tank capacity 5-250"
  else
    fail "Backend does not allow 250 gal tank"
  fi

  # Backend does NOT cap at 100
  if grep -q 'cannot exceed 100 gallons' "$DASHBOARD"; then
    fail "Backend still caps at 100 gallons"
  else
    pass "Backend removed 100 gal cap"
  fi

  # HTML input max=250
  if grep -q 'id="tankCapacityInput"' "$DASHBOARD" && grep -q 'max="250"' "$DASHBOARD"; then
    pass "HTML tankCapacityInput max=250"
  else
    fail "HTML tankCapacityInput not max=250"
  fi

  # JS validation allows 250
  if grep -q 'tankCapacity > 250' "$DASHBOARD"; then
    pass "JS validates tank capacity up to 250"
  else
    fail "JS does not validate 250"
  fi

  # JS does NOT cap at 100
  if grep -q 'tankCapacity > 100' "$DASHBOARD"; then
    fail "JS still caps at 100"
  else
    pass "JS removed 100 cap"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. MPG configurable 0.5-10.0 ──────────────────────────────────
log "Step 2: MPG range (0.5-10.0)"

if [ -f "$DASHBOARD" ]; then
  # Backend validation
  if grep -q "new_rate < 0.5 or new_rate > 10.0" "$DASHBOARD"; then
    pass "Backend validates MPG 0.5-10.0"
  else
    fail "Backend MPG validation not 0.5-10.0"
  fi

  # HTML input
  if grep -q 'id="fuelMpgInput"' "$DASHBOARD" && grep -q 'max="10.0"' "$DASHBOARD"; then
    pass "HTML fuelMpgInput max=10.0"
  else
    fail "HTML fuelMpgInput not max=10.0"
  fi

  if grep -q 'min="0.5"' "$DASHBOARD"; then
    pass "HTML fuelMpgInput min=0.5"
  else
    fail "HTML fuelMpgInput not min=0.5"
  fi

  # Default MPG is 2.0
  if grep -q "consumption_rate_mpg.*2.0" "$DASHBOARD"; then
    pass "Default MPG is 2.0"
  else
    fail "Default MPG not 2.0"
  fi

  # JS validation
  if grep -q 'mpg < 0.5' "$DASHBOARD"; then
    pass "JS validates MPG >= 0.5"
  else
    fail "JS missing MPG >= 0.5 check"
  fi

  if grep -q 'mpg > 10.0' "$DASHBOARD"; then
    pass "JS validates MPG <= 10.0"
  else
    fail "JS missing MPG <= 10.0 check"
  fi
fi

# ── 3. Trip miles accumulation from GPS ────────────────────────────
log "Step 3: GPS trip miles accumulation"

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

  if grep -q "trip_start_at" "$DASHBOARD"; then
    pass "Dashboard has trip_start_at field"
  else
    fail "Dashboard missing trip_start_at"
  fi

  # Anti-jump filter (0.5 mi max per update)
  if grep -q 'distance_mi < 0.5' "$DASHBOARD"; then
    pass "GPS jump filter at 0.5 miles per update"
  else
    fail "Missing GPS jump filter"
  fi

  # Anti-jitter filter (0.001 mi / ~5m minimum)
  if grep -q 'distance_mi > 0.001' "$DASHBOARD"; then
    pass "GPS jitter filter at 0.001 miles"
  else
    fail "Missing GPS jitter filter"
  fi
fi

# ── 4. Range remaining calculation ─────────────────────────────────
log "Step 4: Range remaining calculation"

if [ -f "$DASHBOARD" ]; then
  if grep -q "range_miles_remaining" "$DASHBOARD"; then
    pass "API returns range_miles_remaining"
  else
    fail "API missing range_miles_remaining"
  fi

  if grep -q 'current_fuel \* consumption_rate' "$DASHBOARD"; then
    pass "Range = fuel * MPG calculation"
  else
    fail "Missing range calculation"
  fi
fi

# ── 5. Trip reset endpoint ─────────────────────────────────────────
log "Step 5: Trip reset API"

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

  # Verify it resets to 0
  if grep -q "trip_miles.*=.*0.0" "$DASHBOARD"; then
    pass "Trip reset sets miles to 0"
  else
    fail "Trip reset missing zero assignment"
  fi
fi

# ── 6. Range & Trip UI panel ──────────────────────────────────────
log "Step 6: Range & Trip UI"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'id="rangePanel"' "$DASHBOARD"; then
    pass "Range panel exists in UI"
  else
    fail "Missing range panel"
  fi

  if grep -q 'id="rangeMpgAvg"' "$DASHBOARD"; then
    pass "MPG Avg display in range panel"
  else
    fail "Missing MPG Avg display"
  fi

  if grep -q 'id="rangeFuelRemaining"' "$DASHBOARD"; then
    pass "Fuel Remaining display in range panel"
  else
    fail "Missing Fuel Remaining display"
  fi

  if grep -q 'id="rangeEstRemaining"' "$DASHBOARD"; then
    pass "Est. Range display in range panel"
  else
    fail "Missing Est. Range display"
  fi

  if grep -q 'id="tripMilesValue"' "$DASHBOARD"; then
    pass "Trip Miles display in range panel"
  else
    fail "Missing Trip Miles display"
  fi

  if grep -q 'id="tripStartTime"' "$DASHBOARD"; then
    pass "Trip start time display in range panel"
  else
    fail "Missing Trip start time display"
  fi

  if grep -q 'resetTripMiles' "$DASHBOARD"; then
    pass "Reset Trip Miles button exists"
  else
    fail "Missing Reset Trip Miles button"
  fi

  # Labels
  if grep -q 'Est. Range' "$DASHBOARD"; then
    pass "Range label present"
  else
    fail "Range label missing"
  fi

  if grep -q 'Trip Miles' "$DASHBOARD"; then
    pass "Trip Miles label present"
  else
    fail "Trip Miles label missing"
  fi
fi

# ── 7. Trip state persistence ──────────────────────────────────────
log "Step 7: Trip state persistence"

if [ -f "$DASHBOARD" ]; then
  if grep -q '_save_trip_state' "$DASHBOARD"; then
    pass "Trip state save function exists"
  else
    fail "Missing trip state save"
  fi

  if grep -q '_load_trip_state' "$DASHBOARD"; then
    pass "Trip state load function exists"
  else
    fail "Missing trip state load"
  fi

  if grep -q 'trip_state.json' "$DASHBOARD"; then
    pass "Trip state persisted to trip_state.json"
  else
    fail "Missing trip_state.json persistence"
  fi
fi

# ── 8. Python syntax check ────────────────────────────────────────
log "Step 8: Python syntax"

if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "Python syntax valid"
else
  fail "Python syntax error"
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
