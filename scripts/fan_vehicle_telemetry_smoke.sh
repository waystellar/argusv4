#!/usr/bin/env bash
# fan_vehicle_telemetry_smoke.sh - Smoke test for FAN-TELEM-1: Stable Telemetry Categories
#
# Validates:
#   1. Fan vehicle page renders all telemetry category labels (Speed, RPM, Gear, Coolant, etc)
#   2. Placeholders use "--" pattern (not flashing skeletons for whole telemetry block)
#   3. TelemetryTileSkeleton is not used for main telemetry section
#   4. npm run build passes
#
# Usage:
#   bash scripts/fan_vehicle_telemetry_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VEHICLE_PAGE="$REPO_ROOT/web/src/pages/VehiclePage.tsx"
FAIL=0

log()  { echo "[fan-telem]  $*"; }
pass() { echo "[fan-telem]    PASS: $*"; }
fail() { echo "[fan-telem]    FAIL: $*"; FAIL=1; }
skip() { echo "[fan-telem]    SKIP: $*"; }

log "FAN-TELEM-1: Stable Telemetry Categories Smoke Test"
echo ""

# ── 1. Telemetry category labels are rendered ─────────────────
log "Step 1: Telemetry category labels are always rendered"

if [ -f "$VEHICLE_PAGE" ]; then
  # Check Speed label
  if grep -q 'label="Speed"' "$VEHICLE_PAGE"; then
    pass "Speed label exists"
  else
    fail "Speed label missing"
  fi

  # Check RPM label
  if grep -q 'label="RPM"' "$VEHICLE_PAGE"; then
    pass "RPM label exists"
  else
    fail "RPM label missing"
  fi

  # Check Gear label
  if grep -q 'label="Gear"' "$VEHICLE_PAGE"; then
    pass "Gear label exists"
  else
    fail "Gear label missing"
  fi

  # Check Coolant label
  if grep -q 'label="Coolant"' "$VEHICLE_PAGE"; then
    pass "Coolant label exists"
  else
    fail "Coolant label missing"
  fi

  # Check Oil Press label
  if grep -q 'label="Oil Press"' "$VEHICLE_PAGE"; then
    pass "Oil Press label exists"
  else
    fail "Oil Press label missing"
  fi

  # Check Fuel Press label
  if grep -q 'label="Fuel Press"' "$VEHICLE_PAGE"; then
    pass "Fuel Press label exists"
  else
    fail "Fuel Press label missing"
  fi

  # Check Voltage label
  if grep -q 'label="Voltage"' "$VEHICLE_PAGE"; then
    pass "Voltage label exists"
  else
    fail "Voltage label missing"
  fi
else
  fail "VehiclePage.tsx not found"
fi

# ── 2. Placeholders use "--" pattern ──────────────────────────
log "Step 2: Placeholders use '--' pattern"

if [ -f "$VEHICLE_PAGE" ]; then
  # Check that RPM uses ?? '--' fallback (not hidden)
  if grep -q "telemetryData.rpm ?? '--'" "$VEHICLE_PAGE"; then
    pass "RPM uses '--' placeholder"
  else
    fail "RPM missing '--' placeholder pattern"
  fi

  # Check that Gear uses ?? '--' fallback
  if grep -q "telemetryData.gear ?? '--'" "$VEHICLE_PAGE"; then
    pass "Gear uses '--' placeholder"
  else
    fail "Gear missing '--' placeholder pattern"
  fi

  # Check that Coolant uses ?? '--' fallback
  if grep -q "telemetryData.coolant_temp_c ?? '--'" "$VEHICLE_PAGE"; then
    pass "Coolant uses '--' placeholder"
  else
    fail "Coolant missing '--' placeholder pattern"
  fi

  # Check that Oil uses ?? '--' fallback
  if grep -q "telemetryData.oil_pressure_psi ?? '--'" "$VEHICLE_PAGE"; then
    pass "Oil Press uses '--' placeholder"
  else
    fail "Oil Press missing '--' placeholder pattern"
  fi

  # Check that Fuel uses ?? '--' fallback
  if grep -q "telemetryData.fuel_pressure_psi ?? '--'" "$VEHICLE_PAGE"; then
    pass "Fuel Press uses '--' placeholder"
  else
    fail "Fuel Press missing '--' placeholder pattern"
  fi

  # Check that Voltage uses ?? '--' fallback
  if grep -q "telemetryData.voltage ?? '--'" "$VEHICLE_PAGE"; then
    pass "Voltage uses '--' placeholder"
  else
    fail "Voltage missing '--' placeholder pattern"
  fi
fi

# ── 3. No skeleton flashing for main telemetry block ──────────
log "Step 3: No skeleton flashing for main telemetry block"

if [ -f "$VEHICLE_PAGE" ]; then
  # Check that TelemetryTileSkeleton is NOT imported
  if grep -q 'TelemetryTileSkeleton' "$VEHICLE_PAGE"; then
    fail "TelemetryTileSkeleton still imported/used (causes flashing)"
  else
    pass "TelemetryTileSkeleton not used"
  fi

  # Check that isInitialLoading is NOT used for telemetry section conditional
  if grep -q 'isInitialLoading' "$VEHICLE_PAGE"; then
    fail "isInitialLoading still used (may cause flashing)"
  else
    pass "isInitialLoading not used"
  fi

  # Check that hasEngineTelemetry conditional is removed
  if grep -q 'hasEngineTelemetry &&' "$VEHICLE_PAGE"; then
    fail "hasEngineTelemetry conditional still present (hides section)"
  else
    pass "hasEngineTelemetry conditional removed"
  fi

  # Check that hasAdvancedTelemetry conditional is removed
  if grep -q 'hasAdvancedTelemetry &&' "$VEHICLE_PAGE"; then
    fail "hasAdvancedTelemetry conditional still present (hides section)"
  else
    pass "hasAdvancedTelemetry conditional removed"
  fi
fi

# ── 4. FAN-TELEM-1 marker present ─────────────────────────────
log "Step 4: FAN-TELEM-1 marker present"

if [ -f "$VEHICLE_PAGE" ]; then
  if grep -q 'FAN-TELEM-1' "$VEHICLE_PAGE"; then
    pass "FAN-TELEM-1 marker present"
  else
    fail "FAN-TELEM-1 marker missing"
  fi
fi

# ── 5. TypeScript compiles (npm run build) ────────────────────
log "Step 5: npm run build passes"

cd "$REPO_ROOT/web"
if command -v npm &> /dev/null; then
  if npm run build > /tmp/fan_telem_build.log 2>&1; then
    pass "npm run build succeeded"
  else
    fail "npm run build failed"
    echo "      Build log (last 20 lines):"
    tail -20 /tmp/fan_telem_build.log | sed 's/^/      /'
  fi
else
  skip "npm not available - run 'npm run build' manually to verify"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
