#!/usr/bin/env bash
# edge_devices_assignments_smoke.sh - Smoke test for Camera Assignments (Devices tab)
#
# Validates:
#   1. HTML has exactly 4 canonical camera slot dropdowns (main, cockpit, chase, suspension)
#   2. No duplicate camera slots in HTML
#   3. No legacy slot names (pov, roof, front) in HTML dropdown IDs
#   4. JS populates canonical dropdown IDs (Main, Cockpit, Chase, Suspension)
#   5. JS cameraMappings object uses canonical names
#   6. Backend save handler accepts canonical names
#   7. Backend load handler loads canonical names
#   8. Legacy-to-canonical migration in save and load handlers
#   9. _camera_devices initialization uses canonical names
#  10. Persistence saves to camera_mappings.json
#  11. Python syntax compiles
#
# Usage:
#   bash scripts/edge_devices_assignments_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[cam-assign]  $*"; }
pass() { echo "[cam-assign]    PASS: $*"; }
fail() { echo "[cam-assign]    FAIL: $*"; FAIL=1; }

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "Camera Assignments Smoke Test (Devices Tab)"
echo ""

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ── 1. HTML has exactly 4 canonical camera slot dropdowns ──────
log "Step 1: HTML has 4 canonical camera slot dropdowns"

for slot in Main Cockpit Chase Suspension; do
  if grep -q "id=\"mapping${slot}\"" "$PIT_DASH"; then
    pass "HTML dropdown id='mapping${slot}' exists"
  else
    fail "HTML dropdown id='mapping${slot}' missing"
  fi
done

# ── 2. No duplicate camera slot IDs ───────────────────────────
log "Step 2: No duplicate camera slot dropdown IDs"

for slot in Main Cockpit Chase Suspension; do
  count=$(grep -c "id=\"mapping${slot}\"" "$PIT_DASH" || echo "0")
  if [ "$count" -eq 1 ]; then
    pass "mapping${slot} appears exactly once"
  elif [ "$count" -eq 0 ]; then
    fail "mapping${slot} not found"
  else
    fail "mapping${slot} appears $count times (duplicate!)"
  fi
done

# ── 3. No legacy slot names in HTML dropdown IDs ──────────────
log "Step 3: No legacy slot names in HTML dropdown IDs"

for legacy in Pov Roof Front ChaseAlt; do
  if grep -q "id=\"mapping${legacy}\"" "$PIT_DASH"; then
    fail "Legacy HTML dropdown id='mapping${legacy}' still present"
  else
    pass "No legacy mapping${legacy} dropdown"
  fi
done

# ── 4. JS populates canonical dropdown IDs ────────────────────
log "Step 4: JS populates canonical dropdown IDs"

if grep -q "'Main', 'Cockpit', 'Chase', 'Suspension'" "$PIT_DASH" || \
   grep -q "'Main','Cockpit','Chase','Suspension'" "$PIT_DASH"; then
  pass "JS forEach uses canonical names [Main, Cockpit, Chase, Suspension]"
else
  fail "JS forEach not using canonical names"
fi

# No legacy names in forEach
if grep -q "'Pov', 'Roof', 'Front'" "$PIT_DASH" || \
   grep -q "'Pov','Roof','Front'" "$PIT_DASH"; then
  fail "JS forEach still references legacy names [Pov, Roof, Front]"
else
  pass "No legacy names in JS forEach"
fi

# ── 5. JS cameraMappings uses canonical names ─────────────────
log "Step 5: JS cameraMappings uses canonical names"

if grep -q "cameraMappings = { main:" "$PIT_DASH" || \
   grep -q "cameraMappings = {main:" "$PIT_DASH"; then
  pass "cameraMappings uses canonical names"
else
  fail "cameraMappings not using canonical names"
fi

# ── 6. Backend save handler accepts canonical names ───────────
log "Step 6: Backend save handler accepts canonical names"

if grep -q "for role in \['main', 'cockpit', 'chase', 'suspension'\]" "$PIT_DASH"; then
  pass "Save handler iterates canonical names"
else
  fail "Save handler not iterating canonical names"
fi

# No legacy-only save handler
if grep -q "for role in \['chase', 'pov', 'roof', 'front'\]" "$PIT_DASH"; then
  fail "Save handler still uses legacy-only names"
else
  pass "No legacy-only save handler"
fi

# ── 7. Backend load handler loads canonical names ─────────────
log "Step 7: Backend load handler loads canonical names"

if grep -q "for role in ('main', 'cockpit', 'chase', 'suspension')" "$PIT_DASH"; then
  pass "Load handler iterates canonical names"
else
  fail "Load handler not iterating canonical names"
fi

# No legacy-only load handler
if grep -q "for role in ('chase', 'pov', 'roof', 'front')" "$PIT_DASH"; then
  fail "Load handler still uses legacy-only names"
else
  pass "No legacy-only load handler"
fi

# ── 8. Legacy-to-canonical migration exists ───────────────────
log "Step 8: Legacy-to-canonical migration in save and load"

if grep -q "legacy_to_canonical" "$PIT_DASH"; then
  pass "legacy_to_canonical mapping exists"
else
  fail "No legacy_to_canonical migration mapping"
fi

# Check it maps pov->cockpit
if grep -q "'pov': 'cockpit'" "$PIT_DASH"; then
  pass "Legacy migration: pov -> cockpit"
else
  fail "Missing legacy migration: pov -> cockpit"
fi

# ── 9. _camera_devices initialization uses canonical names ────
log "Step 9: _camera_devices uses canonical names"

for slot in main cockpit chase suspension; do
  if grep -A5 "_camera_devices = {" "$PIT_DASH" | grep -q "\"$slot\""; then
    pass "_camera_devices has '$slot'"
  else
    fail "_camera_devices missing '$slot'"
  fi
done

# ── 10. Persistence saves to camera_mappings.json ─────────────
log "Step 10: Persistence file"

if grep -q "camera_mappings.json" "$PIT_DASH"; then
  pass "Saves to camera_mappings.json"
else
  fail "camera_mappings.json not referenced"
fi

# ── 11. Python syntax compiles ────────────────────────────────
log "Step 11: Python syntax compiles"

if python3 -m py_compile "$PIT_DASH" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles"
else
  fail "pit_crew_dashboard.py has syntax errors"
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
