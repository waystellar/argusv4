#!/usr/bin/env bash
# edge_video_devices_detect_smoke.sh - Smoke test for Device Detection (Devices tab)
#
# Validates:
#   1. Video device detection scans /dev/video0 through /dev/video9
#   2. v4l2-ctl used for camera identification
#   3. GPS detection checks /dev/ttyUSB*, /dev/ttyACM*, /dev/serial/by-id/*
#   4. GPS detection includes Prolific/ATEN patterns (for common USB-serial adapters)
#   5. ANT+ detection uses Dynastream vendor ID (0fcf)
#   6. ANT+ product name parsed from lsusb output
#   7. CAN bus detection checks can0 interface
#   8. Device scan returns mappings in response
#   9. Serial port enumeration includes /dev/serial/by-id/*
#  10. Python syntax compiles
#
# Usage:
#   bash scripts/edge_video_devices_detect_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[dev-detect]  $*"; }
pass() { echo "[dev-detect]    PASS: $*"; }
fail() { echo "[dev-detect]    FAIL: $*"; FAIL=1; }

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "Device Detection Smoke Test (Devices Tab)"
echo ""

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ── 1. Video device detection ─────────────────────────────────
log "Step 1: Video device detection"

if grep -q "/dev/video" "$PIT_DASH"; then
  pass "Scans /dev/video* paths"
else
  fail "No /dev/video scanning"
fi

if grep -q "range(10)" "$PIT_DASH"; then
  pass "Scans video0 through video9"
else
  fail "Not scanning full video device range"
fi

# ── 2. v4l2-ctl camera identification ─────────────────────────
log "Step 2: v4l2-ctl camera identification"

if grep -q "v4l2-ctl" "$PIT_DASH"; then
  pass "Uses v4l2-ctl for camera info"
else
  fail "No v4l2-ctl usage"
fi

if grep -q "Card type" "$PIT_DASH"; then
  pass "Parses 'Card type' from v4l2-ctl output"
else
  fail "Not parsing Card type from v4l2-ctl"
fi

# ── 3. GPS serial port detection ──────────────────────────────
log "Step 3: GPS serial port detection"

if grep -q "/dev/ttyUSB" "$PIT_DASH"; then
  pass "Checks /dev/ttyUSB* for GPS"
else
  fail "No /dev/ttyUSB detection"
fi

if grep -q "/dev/ttyACM" "$PIT_DASH"; then
  pass "Checks /dev/ttyACM* for GPS"
else
  fail "No /dev/ttyACM detection"
fi

if grep -q "/dev/serial/by-id/" "$PIT_DASH"; then
  pass "Checks /dev/serial/by-id/ for GPS"
else
  fail "No /dev/serial/by-id/ detection"
fi

# ── 4. GPS Prolific/ATEN adapter patterns ─────────────────────
log "Step 4: GPS Prolific/ATEN adapter patterns"

if grep -q "Prolific" "$PIT_DASH"; then
  pass "GPS detection includes Prolific pattern"
else
  fail "Missing Prolific serial adapter pattern for GPS"
fi

if grep -q "ATEN" "$PIT_DASH"; then
  pass "GPS detection includes ATEN pattern"
else
  fail "Missing ATEN serial adapter pattern for GPS"
fi

# ── 5. ANT+ Dynastream detection ──────────────────────────────
log "Step 5: ANT+ Dynastream detection"

if grep -q "0fcf" "$PIT_DASH"; then
  pass "ANT+ detection uses Dynastream vendor ID 0fcf"
else
  fail "ANT+ not checking Dynastream vendor ID 0fcf"
fi

if grep -q "lsusb" "$PIT_DASH"; then
  pass "Uses lsusb for ANT+ detection"
else
  fail "No lsusb usage for ANT+"
fi

# ── 6. ANT+ product name parsing ──────────────────────────────
log "Step 6: ANT+ product name parsing"

if grep -q "ant_product" "$PIT_DASH"; then
  pass "ANT+ product name parsed from lsusb"
else
  fail "ANT+ product name not parsed"
fi

# ── 7. CAN bus detection ──────────────────────────────────────
log "Step 7: CAN bus detection"

if grep -q "ip.*link.*show.*can0" "$PIT_DASH"; then
  pass "CAN bus checks can0 interface via ip link"
else
  fail "No CAN bus can0 detection"
fi

# ── 8. Scan returns mappings ──────────────────────────────────
log "Step 8: Device scan returns camera mappings"

if grep -q "'mappings': self._camera_devices" "$PIT_DASH"; then
  pass "Scan response includes camera mappings"
else
  fail "Scan response missing camera mappings"
fi

# ── 9. Serial port enumeration ────────────────────────────────
log "Step 9: Serial port enumeration"

if grep -q "serial_ports" "$PIT_DASH"; then
  pass "Serial ports listed in scan result"
else
  fail "No serial_ports in scan result"
fi

# ── 10. Python syntax compiles ────────────────────────────────
log "Step 10: Python syntax compiles"

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
