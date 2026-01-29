#!/usr/bin/env bash
# edge_status_lights_smoke.sh - Smoke test for Edge Status Lights Tri-State
#
# EDGE-STATUS-1: Validates that status indicators use red/yellow/green
# tri-state logic with boot window awareness.
#
# Validates:
#   Boot Window:
#     1.  boot_ts_ms field exists in TelemetryState
#     2.  boot_ts_ms included in to_dict() output
#     3.  boot_ts_ms set on PitCrewDashboard init
#     4.  BOOT_WINDOW_MS constant exists in JS
#   Device Status Dots:
#     5.  setDeviceStatusDot accepts bootTsMs parameter
#     6.  setDeviceStatusDot handles 'unknown' + inBootWindow → warning
#     7.  setDeviceStatusDot handles 'unknown' + past boot → red (no class)
#     8.  setDeviceStatusDot handles 'connected' + dataOk → ok
#     9.  setDeviceStatusDot handles 'connected' + !dataOk → warning
#    10.  setDeviceStatusDot handles 'missing' → warning
#    11.  setDeviceStatusDot handles 'timeout' → warning
#    12.  setDeviceStatusDot handles 'simulated' → warning
#   Cloud Status Dot:
#    13.  setCloudStatusDot function exists
#    14.  Cloud dot uses cloud_detail (not cloud_connected boolean)
#    15.  setCloudStatusDot handles 'healthy' → ok
#    16.  setCloudStatusDot handles 'event_not_live' → warning
#    17.  setCloudStatusDot handles 'not_configured' → warning
#    18.  setCloudStatusDot handles 'auth_rejected' → red (no class)
#   Audio Status Dot:
#    19.  Audio dot uses tri-state (ok/warning, not just setStatusDot)
#    20.  Audio dot shows warning when system up but no signal
#   Freshness Thresholds:
#    21.  CAN freshness threshold >= 5000ms
#    22.  GPS freshness checks gps_ts_ms staleness
#   Callers:
#    23.  canStatus caller passes bootTs
#    24.  gpsStatus caller passes bootTs
#    25.  antStatus caller passes bootTs
#    26.  cloudStatus uses setCloudStatusDot (not setStatusDot)
#   Syntax:
#    27.  Python syntax compiles
#
# Usage:
#   bash scripts/edge_status_lights_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[status-lights]  $*"; }
pass() { echo "[status-lights]    PASS: $*"; }
fail() { echo "[status-lights]    FAIL: $*"; FAIL=1; }

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "EDGE-STATUS-1: Status Lights Tri-State Smoke Test"
echo ""

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# BOOT WINDOW
# ═══════════════════════════════════════════════════════════════════

# ── 1. boot_ts_ms field in TelemetryState ────────────────────────
log "Step 1: boot_ts_ms field in TelemetryState"
if grep -q 'boot_ts_ms.*int.*=' "$PIT_DASH"; then
  pass "boot_ts_ms field exists"
else
  fail "boot_ts_ms field missing"
fi

# ── 2. boot_ts_ms in to_dict() ──────────────────────────────────
log "Step 2: boot_ts_ms in to_dict()"
if grep -q '"boot_ts_ms".*self.boot_ts_ms' "$PIT_DASH"; then
  pass "boot_ts_ms in to_dict"
else
  fail "boot_ts_ms missing from to_dict"
fi

# ── 3. boot_ts_ms set on init ───────────────────────────────────
log "Step 3: boot_ts_ms set on PitCrewDashboard init"
if grep -q 'boot_ts_ms.*=.*int(time' "$PIT_DASH"; then
  pass "boot_ts_ms set on init"
else
  fail "boot_ts_ms not set on init"
fi

# ── 4. BOOT_WINDOW_MS constant in JS ────────────────────────────
log "Step 4: BOOT_WINDOW_MS constant in JS"
if grep -q 'BOOT_WINDOW_MS' "$PIT_DASH"; then
  pass "BOOT_WINDOW_MS constant exists"
else
  fail "BOOT_WINDOW_MS constant missing"
fi

# ═══════════════════════════════════════════════════════════════════
# DEVICE STATUS DOTS
# ═══════════════════════════════════════════════════════════════════

# Extract setDeviceStatusDot function
DEVICE_DOT_FUNC=$(sed -n '/function setDeviceStatusDot/,/^        function /p' "$PIT_DASH")

# ── 5. setDeviceStatusDot accepts bootTsMs ───────────────────────
log "Step 5: setDeviceStatusDot accepts bootTsMs parameter"
if echo "$DEVICE_DOT_FUNC" | grep -q 'bootTsMs\|bootTs'; then
  pass "setDeviceStatusDot has boot timestamp parameter"
else
  fail "setDeviceStatusDot missing boot timestamp parameter"
fi

# ── 6. unknown + inBootWindow → warning ──────────────────────────
log "Step 6: unknown + inBootWindow → warning"
if echo "$DEVICE_DOT_FUNC" | grep -q "unknown.*inBootWindow\|unknown.*&&.*inBootWindow"; then
  pass "unknown during boot window shows warning"
else
  fail "unknown during boot window not handled"
fi

# ── 7. unknown + past boot → red ────────────────────────────────
log "Step 7: unknown past boot window → red (no class added)"
# The else branch should not add ok or warning class
if echo "$DEVICE_DOT_FUNC" | grep -q "Hardware not responding\|Status unknown"; then
  pass "unknown past boot window falls to red"
else
  fail "unknown past boot window not handled"
fi

# ── 8. connected + dataOk → ok ──────────────────────────────────
log "Step 8: connected + dataOk → green"
if echo "$DEVICE_DOT_FUNC" | grep -q "connected.*dataOk"; then
  pass "connected + dataOk → green"
else
  fail "connected + dataOk not handled"
fi

# ── 9. connected + !dataOk → warning ────────────────────────────
log "Step 9: connected + !dataOk → yellow"
if echo "$DEVICE_DOT_FUNC" | grep -q "connected.*waiting for data"; then
  pass "connected without data → yellow"
else
  fail "connected without data not handled"
fi

# ── 10. missing → warning ───────────────────────────────────────
log "Step 10: missing → warning"
if echo "$DEVICE_DOT_FUNC" | grep -q "'missing'"; then
  pass "missing → yellow"
else
  fail "missing not handled"
fi

# ── 11. timeout → warning ───────────────────────────────────────
log "Step 11: timeout → warning"
if echo "$DEVICE_DOT_FUNC" | grep -q "'timeout'"; then
  pass "timeout → yellow"
else
  fail "timeout not handled"
fi

# ── 12. simulated → warning ─────────────────────────────────────
log "Step 12: simulated → warning"
if echo "$DEVICE_DOT_FUNC" | grep -q "'simulated'"; then
  pass "simulated → yellow"
else
  fail "simulated not handled"
fi

# ═══════════════════════════════════════════════════════════════════
# CLOUD STATUS DOT
# ═══════════════════════════════════════════════════════════════════

# ── 13. setCloudStatusDot function exists ────────────────────────
log "Step 13: setCloudStatusDot function exists"
if grep -q 'function setCloudStatusDot' "$PIT_DASH"; then
  pass "setCloudStatusDot function exists"
else
  fail "setCloudStatusDot function missing"
fi

# ── 14. Cloud dot uses cloud_detail ──────────────────────────────
log "Step 14: Cloud dot uses cloud_detail (not boolean)"
if grep -q "setCloudStatusDot.*cloud_detail" "$PIT_DASH"; then
  pass "Cloud dot uses cloud_detail"
else
  fail "Cloud dot not using cloud_detail"
fi

CLOUD_DOT_FUNC=$(sed -n '/function setCloudStatusDot/,/^        function /p' "$PIT_DASH")

# ── 15. healthy → ok ────────────────────────────────────────────
log "Step 15: healthy → green"
if echo "$CLOUD_DOT_FUNC" | grep -q "'healthy'"; then
  pass "healthy → green"
else
  fail "healthy not handled"
fi

# ── 16. event_not_live → warning ────────────────────────────────
log "Step 16: event_not_live → yellow"
if echo "$CLOUD_DOT_FUNC" | grep -q "'event_not_live'"; then
  pass "event_not_live → yellow"
else
  fail "event_not_live not handled"
fi

# ── 17. not_configured → warning ────────────────────────────────
log "Step 17: not_configured → yellow"
if echo "$CLOUD_DOT_FUNC" | grep -q "'not_configured'"; then
  pass "not_configured → yellow"
else
  fail "not_configured not handled"
fi

# ── 18. auth_rejected → red ─────────────────────────────────────
log "Step 18: auth_rejected → red"
if echo "$CLOUD_DOT_FUNC" | grep -q "auth_rejected"; then
  # Should NOT add ok or warning
  if echo "$CLOUD_DOT_FUNC" | sed -n "/auth_rejected/,/else/p" | grep -q "classList.add.*ok\|classList.add.*warning"; then
    fail "auth_rejected should be red (no ok/warning class)"
  else
    pass "auth_rejected → red"
  fi
else
  fail "auth_rejected not handled"
fi

# ═══════════════════════════════════════════════════════════════════
# AUDIO STATUS DOT
# ═══════════════════════════════════════════════════════════════════

# ── 19. Audio dot uses tri-state ─────────────────────────────────
log "Step 19: Audio dot uses tri-state"
AUDIO_POLL=$(sed -n '/function pollAudioLevel/,/^        function /p' "$PIT_DASH")
if echo "$AUDIO_POLL" | grep -q "classList.*warning\|add.*warning"; then
  pass "Audio dot uses warning state (tri-state)"
else
  fail "Audio dot missing warning state"
fi

# ── 20. Audio warning when no signal ─────────────────────────────
log "Step 20: Audio shows warning when no signal"
if echo "$AUDIO_POLL" | grep -q "no signal"; then
  pass "Audio shows 'no signal' warning"
else
  fail "Audio missing 'no signal' state"
fi

# ═══════════════════════════════════════════════════════════════════
# FRESHNESS THRESHOLDS
# ═══════════════════════════════════════════════════════════════════

# ── 21. CAN freshness >= 5000ms ──────────────────────────────────
log "Step 21: CAN freshness threshold >= 5000ms"
CAN_THRESH=$(grep 'canFresh.*last_update_ms' "$PIT_DASH" | grep -oE '[0-9]+' | tail -1)
if [ -n "$CAN_THRESH" ] && [ "$CAN_THRESH" -ge 5000 ]; then
  pass "CAN freshness threshold is ${CAN_THRESH}ms"
else
  fail "CAN freshness threshold too tight: ${CAN_THRESH:-unknown}ms"
fi

# ── 22. GPS freshness checks gps_ts_ms ──────────────────────────
log "Step 22: GPS freshness checks gps_ts_ms staleness"
if grep -q 'gpsFresh.*gps_ts_ms' "$PIT_DASH"; then
  pass "GPS freshness includes timestamp staleness check"
else
  fail "GPS freshness missing gps_ts_ms check"
fi

# ═══════════════════════════════════════════════════════════════════
# CALLERS
# ═══════════════════════════════════════════════════════════════════

# ── 23-25. Device dot callers pass bootTs ────────────────────────
for dot in canStatus gpsStatus antStatus; do
  STEP=$((23 + $(echo "canStatus gpsStatus antStatus" | tr ' ' '\n' | grep -n "^${dot}$" | cut -d: -f1) - 1))
  log "Step $STEP: ${dot} caller passes bootTs"
  if grep "setDeviceStatusDot.*${dot}" "$PIT_DASH" | grep -q 'bootTs'; then
    pass "${dot} passes boot timestamp"
  else
    fail "${dot} missing boot timestamp argument"
  fi
done

# ── 26. cloudStatus uses setCloudStatusDot ───────────────────────
log "Step 26: cloudStatus uses setCloudStatusDot"
if grep -q "setCloudStatusDot.*cloudStatus" "$PIT_DASH"; then
  pass "cloudStatus uses setCloudStatusDot"
else
  fail "cloudStatus not using setCloudStatusDot"
fi

# ═══════════════════════════════════════════════════════════════════
# SYNTAX
# ═══════════════════════════════════════════════════════════════════

# ── 27. Python syntax compiles ───────────────────────────────────
log "Step 27: Python syntax compiles"
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
