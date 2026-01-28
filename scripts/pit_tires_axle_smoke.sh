#!/usr/bin/env bash
# pit_tires_axle_smoke.sh — Smoke test for Tires v2: Front/Rear Independent (PIT-5R)
#
# Validates:
#   1. Compound UI removed (no compound label or buttons)
#   2. Brand selector with Toyo/BFG/Maxxis/Other options
#   3. Front axle: brand display, miles, last changed, reset button
#   4. Rear axle: brand display, miles, last changed, reset button
#   5. Reset buttons are distinct (front vs rear)
#   6. Backend tire state model (brand, front/rear baselines)
#   7. Backend persistence (tire_state.json)
#   8. Backend first-run baseline initialization
#   9. Miles computed from trip baseline (not raw accumulator)
#  10. JS functions: updateTireBrand, resetTireAxle, loadTireStatus
#  11. Python syntax check
#
# Usage:
#   bash scripts/pit_tires_axle_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[pit-tires] $*"; }
pass() { echo "[pit-tires]   PASS: $*"; }
fail() { echo "[pit-tires]   FAIL: $*"; FAIL=1; }
warn() { echo "[pit-tires]   WARN: $*"; }

# ── 1. Compound UI removed ──────────────────────────────────────
log "Step 1: Compound UI removed"

if [ -f "$DASHBOARD" ]; then
  # No compound label
  if grep -q '>Compound<' "$DASHBOARD"; then
    fail "Compound label still in UI"
  else
    pass "Compound label removed"
  fi

  # No compound buttons (All-Terrain, Mud, Sand, Rock)
  if grep -q "recordTireChange" "$DASHBOARD"; then
    fail "recordTireChange function still present"
  else
    pass "recordTireChange removed"
  fi

  if grep -q "A/T Installed" "$DASHBOARD"; then
    fail "A/T Installed button still present"
  else
    pass "A/T Installed button removed"
  fi

  if grep -q 'id="tireCompound"' "$DASHBOARD"; then
    fail "tireCompound element still present"
  else
    pass "tireCompound element removed"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. Brand selector ───────────────────────────────────────────
log "Step 2: Brand selector"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'id="tireBrandSelect"' "$DASHBOARD"; then
    pass "Brand selector element exists"
  else
    fail "Brand selector missing"
  fi

  # Options: Toyo, BFG, Maxxis, Other
  for brand in Toyo BFG Maxxis Other; do
    if grep -q "value=\"$brand\"" "$DASHBOARD"; then
      pass "Brand option $brand present"
    else
      fail "Brand option $brand missing"
    fi
  done

  if grep -q 'updateTireBrand' "$DASHBOARD"; then
    pass "updateTireBrand JS function exists"
  else
    fail "updateTireBrand missing"
  fi
fi

# ── 3. Front axle UI ────────────────────────────────────────────
log "Step 3: Front axle UI"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'id="tireFrontRow"' "$DASHBOARD"; then
    pass "Front axle row exists"
  else
    fail "Front axle row missing"
  fi

  if grep -q 'id="tireFrontBrand"' "$DASHBOARD"; then
    pass "Front brand display exists"
  else
    fail "Front brand display missing"
  fi

  if grep -q 'id="tireFrontMiles"' "$DASHBOARD"; then
    pass "Front miles display exists"
  else
    fail "Front miles display missing"
  fi

  if grep -q 'id="tireFrontChanged"' "$DASHBOARD"; then
    pass "Front last-changed display exists"
  else
    fail "Front last-changed display missing"
  fi

  if grep -q 'id="tireFrontResetBtn"' "$DASHBOARD"; then
    pass "Front reset button exists"
  else
    fail "Front reset button missing"
  fi
fi

# ── 4. Rear axle UI ─────────────────────────────────────────────
log "Step 4: Rear axle UI"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'id="tireRearRow"' "$DASHBOARD"; then
    pass "Rear axle row exists"
  else
    fail "Rear axle row missing"
  fi

  if grep -q 'id="tireRearBrand"' "$DASHBOARD"; then
    pass "Rear brand display exists"
  else
    fail "Rear brand display missing"
  fi

  if grep -q 'id="tireRearMiles"' "$DASHBOARD"; then
    pass "Rear miles display exists"
  else
    fail "Rear miles display missing"
  fi

  if grep -q 'id="tireRearChanged"' "$DASHBOARD"; then
    pass "Rear last-changed display exists"
  else
    fail "Rear last-changed display missing"
  fi

  if grep -q 'id="tireRearResetBtn"' "$DASHBOARD"; then
    pass "Rear reset button exists"
  else
    fail "Rear reset button missing"
  fi
fi

# ── 5. Reset buttons are distinct ───────────────────────────────
log "Step 5: Independent reset controls"

if [ -f "$DASHBOARD" ]; then
  if grep -q "resetTireAxle('front')" "$DASHBOARD"; then
    pass "Front reset calls resetTireAxle('front')"
  else
    fail "Front reset not wired"
  fi

  if grep -q "resetTireAxle('rear')" "$DASHBOARD"; then
    pass "Rear reset calls resetTireAxle('rear')"
  else
    fail "Rear reset not wired"
  fi

  if grep -q "reset_front" "$DASHBOARD" && grep -q "reset_rear" "$DASHBOARD"; then
    pass "Backend handles reset_front and reset_rear independently"
  else
    fail "Backend missing independent reset fields"
  fi
fi

# ── 6. Backend data model ───────────────────────────────────────
log "Step 6: Backend tire state model"

if [ -f "$DASHBOARD" ]; then
  if grep -q "_tire_state" "$DASHBOARD"; then
    pass "_tire_state dict exists"
  else
    fail "_tire_state missing"
  fi

  if grep -q "'brand'" "$DASHBOARD" && grep -q "'Toyo'" "$DASHBOARD"; then
    pass "Brand field with Toyo default"
  else
    fail "Brand field or Toyo default missing"
  fi

  if grep -q "front_trip_baseline" "$DASHBOARD"; then
    pass "front_trip_baseline field exists"
  else
    fail "front_trip_baseline missing"
  fi

  if grep -q "rear_trip_baseline" "$DASHBOARD"; then
    pass "rear_trip_baseline field exists"
  else
    fail "rear_trip_baseline missing"
  fi

  if grep -q "front_last_changed_at" "$DASHBOARD"; then
    pass "front_last_changed_at field exists"
  else
    fail "front_last_changed_at missing"
  fi

  if grep -q "rear_last_changed_at" "$DASHBOARD"; then
    pass "rear_last_changed_at field exists"
  else
    fail "rear_last_changed_at missing"
  fi

  if grep -q "front_change_count" "$DASHBOARD"; then
    pass "front_change_count field exists"
  else
    fail "front_change_count missing"
  fi

  if grep -q "rear_change_count" "$DASHBOARD"; then
    pass "rear_change_count field exists"
  else
    fail "rear_change_count missing"
  fi
fi

# ── 7. Persistence ──────────────────────────────────────────────
log "Step 7: Tire state persistence"

if [ -f "$DASHBOARD" ]; then
  if grep -q "_save_tire_state" "$DASHBOARD"; then
    pass "_save_tire_state method exists"
  else
    fail "_save_tire_state missing"
  fi

  if grep -q "_load_tire_state" "$DASHBOARD"; then
    pass "_load_tire_state method exists"
  else
    fail "_load_tire_state missing"
  fi

  if grep -q "tire_state.json" "$DASHBOARD"; then
    pass "Persisted to tire_state.json"
  else
    fail "tire_state.json reference missing"
  fi
fi

# ── 8. First-run baseline initialization ────────────────────────
log "Step 8: First-run baseline initialization"

if [ -f "$DASHBOARD" ]; then
  # On first run (no file), baselines set to current trip_miles
  if grep -A 20 'def _load_tire_state' "$DASHBOARD" | grep -q 'front_trip_baseline.*trip_miles'; then
    pass "First-run sets front baseline to current trip_miles"
  else
    fail "First-run baseline initialization missing"
  fi
fi

# ── 9. Miles computed from baseline ─────────────────────────────
log "Step 9: Miles from baseline computation"

if [ -f "$DASHBOARD" ]; then
  if grep -q "trip_miles - self._tire_state\['front_trip_baseline'\]" "$DASHBOARD"; then
    pass "Front miles = trip_miles - front_trip_baseline"
  else
    fail "Front miles computation missing"
  fi

  if grep -q "trip_miles - self._tire_state\['rear_trip_baseline'\]" "$DASHBOARD"; then
    pass "Rear miles = trip_miles - rear_trip_baseline"
  else
    fail "Rear miles computation missing"
  fi

  # Clamped >= 0
  if grep -q "max(0.0, trip_miles" "$DASHBOARD"; then
    pass "Miles clamped >= 0"
  else
    fail "Miles not clamped"
  fi
fi

# ── 10. JS functions ────────────────────────────────────────────
log "Step 10: JavaScript functions"

if [ -f "$DASHBOARD" ]; then
  if grep -q "async function updateTireBrand" "$DASHBOARD"; then
    pass "updateTireBrand function exists"
  else
    fail "updateTireBrand function missing"
  fi

  if grep -q "async function resetTireAxle" "$DASHBOARD"; then
    pass "resetTireAxle function exists"
  else
    fail "resetTireAxle function missing"
  fi

  if grep -q "async function loadTireStatus" "$DASHBOARD"; then
    pass "loadTireStatus function exists"
  else
    fail "loadTireStatus function missing"
  fi

  # Brand sync
  if grep -q "tireFrontBrand.*brand" "$DASHBOARD" && grep -q "tireRearBrand.*brand" "$DASHBOARD"; then
    pass "Both axle brand displays synced from brand field"
  else
    fail "Brand display sync missing"
  fi
fi

# ── 11. No old compound fields in backend ────────────────────────
log "Step 11: Old compound fields removed from backend"

if [ -f "$DASHBOARD" ]; then
  if grep -q "'current_compound'" "$DASHBOARD"; then
    fail "current_compound field still in backend"
  else
    pass "current_compound removed from backend"
  fi

  if grep -q "miles_on_tires" "$DASHBOARD"; then
    fail "miles_on_tires accumulator still in backend"
  else
    pass "miles_on_tires accumulator removed"
  fi
fi

# ── 12. Python syntax check ─────────────────────────────────────
log "Step 12: Python syntax"

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
