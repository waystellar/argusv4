#!/usr/bin/env bash
# pit_engine_layout_smoke.sh — Smoke test for Engine Tab 2x2 layout (PIT-3)
#
# Validates:
#   1. Load bar removed from Engine tab UI
#   2. 2x2 grid layout class exists
#   3. Speed tile present with label
#   4. RPM tile present with tachometer
#   5. Gear tile present with label
#   6. Coolant tile present with label and value element
#   7. Coolant tile JS update exists (with color coding)
#   8. CAN parsing for engine_load still intact (data model)
#   9. Python syntax check
#
# Usage:
#   bash scripts/pit_engine_layout_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[engine-layout] $*"; }
pass() { echo "[engine-layout]   PASS: $*"; }
fail() { echo "[engine-layout]   FAIL: $*"; FAIL=1; }
warn() { echo "[engine-layout]   WARN: $*"; }

# ── 1. Load removed from Engine tab UI ────────────────────────────
log "Step 1: Load removed from UI"

if [ -f "$DASHBOARD" ]; then
  # No Load bar HTML elements
  if grep -q 'id="loadFill"' "$DASHBOARD"; then
    fail "loadFill element still in UI"
  else
    pass "loadFill element removed"
  fi

  if grep -q 'id="loadValue"' "$DASHBOARD"; then
    fail "loadValue element still in UI"
  else
    pass "loadValue element removed"
  fi

  if grep -q 'load-bar-container' "$DASHBOARD"; then
    fail "load-bar-container CSS still present"
  else
    pass "load-bar-container CSS removed"
  fi

  # No "LOAD" label in Engine tab
  if grep -q '>LOAD<' "$DASHBOARD"; then
    fail "LOAD label still in Engine tab"
  else
    pass "LOAD label removed from Engine tab"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. 2x2 grid layout ───────────────────────────────────────────
log "Step 2: 2x2 grid layout"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'engine-2x2-grid' "$DASHBOARD"; then
    pass "engine-2x2-grid class exists"
  else
    fail "engine-2x2-grid class missing"
  fi

  if grep -q 'grid-template-columns: 1fr 1fr' "$DASHBOARD"; then
    pass "Grid has 2 equal columns"
  else
    fail "Grid missing 2-column layout"
  fi

  if grep -q 'engine-tile' "$DASHBOARD"; then
    pass "engine-tile class exists"
  else
    fail "engine-tile class missing"
  fi
fi

# ── 3. Speed tile ─────────────────────────────────────────────────
log "Step 3: Speed tile"

if [ -f "$DASHBOARD" ]; then
  if grep -q '>SPEED<' "$DASHBOARD"; then
    pass "SPEED label present"
  else
    fail "SPEED label missing"
  fi

  if grep -q 'id="speedValueEngine"' "$DASHBOARD"; then
    pass "speedValueEngine element present"
  else
    fail "speedValueEngine element missing"
  fi

  if grep -q '>MPH<' "$DASHBOARD"; then
    pass "MPH unit label present"
  else
    fail "MPH unit label missing"
  fi
fi

# ── 4. RPM tile ──────────────────────────────────────────────────
log "Step 4: RPM tile"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'engine-tile-rpm' "$DASHBOARD"; then
    pass "RPM tile class exists"
  else
    fail "RPM tile class missing"
  fi

  if grep -q 'id="rpmValue"' "$DASHBOARD"; then
    pass "rpmValue element present"
  else
    fail "rpmValue element missing"
  fi

  if grep -q 'id="tachNeedle"' "$DASHBOARD"; then
    pass "Tachometer needle present"
  else
    fail "Tachometer needle missing"
  fi
fi

# ── 5. Gear tile ──────────────────────────────────────────────────
log "Step 5: Gear tile"

if [ -f "$DASHBOARD" ]; then
  if grep -q '>GEAR<' "$DASHBOARD"; then
    pass "GEAR label present"
  else
    fail "GEAR label missing"
  fi

  if grep -q 'id="gearValue"' "$DASHBOARD"; then
    pass "gearValue element present"
  else
    fail "gearValue element missing"
  fi
fi

# ── 6. Coolant tile ───────────────────────────────────────────────
log "Step 6: Coolant tile"

if [ -f "$DASHBOARD" ]; then
  if grep -q '>COOLANT<' "$DASHBOARD"; then
    pass "COOLANT label present in 2x2 grid"
  else
    fail "COOLANT label missing from 2x2 grid"
  fi

  if grep -q 'id="coolantTile"' "$DASHBOARD"; then
    pass "coolantTile element present"
  else
    fail "coolantTile element missing"
  fi

  if grep -q 'id="coolantTileValue"' "$DASHBOARD"; then
    pass "coolantTileValue element present"
  else
    fail "coolantTileValue element missing"
  fi

  if grep -q 'id="coolantTileFill"' "$DASHBOARD"; then
    pass "coolantTileFill gauge bar present"
  else
    fail "coolantTileFill gauge bar missing"
  fi
fi

# ── 7. Coolant tile JS update ─────────────────────────────────────
log "Step 7: Coolant tile JavaScript update"

if [ -f "$DASHBOARD" ]; then
  if grep -q "coolantTileValue" "$DASHBOARD" && grep -q "coolantTileFill" "$DASHBOARD"; then
    pass "JS updates coolant tile value and fill"
  else
    fail "JS missing coolant tile updates"
  fi

  # Color coding thresholds
  if grep -q '250' "$DASHBOARD" && grep -q '220' "$DASHBOARD"; then
    pass "Coolant tile has temperature thresholds (220/250F)"
  else
    fail "Missing coolant temperature thresholds"
  fi
fi

# ── 8. CAN parsing for engine_load intact ─────────────────────────
log "Step 8: CAN parsing preserved"

if [ -f "$DASHBOARD" ]; then
  if grep -q "engine_load:" "$DASHBOARD"; then
    pass "engine_load field in telemetry model"
  else
    fail "engine_load removed from telemetry model"
  fi

  if grep -q "engine_load.*payload" "$DASHBOARD"; then
    pass "engine_load CAN parsing intact"
  else
    fail "engine_load CAN parsing removed"
  fi
fi

# ── 9. Python syntax check ────────────────────────────────────────
log "Step 9: Python syntax"

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
