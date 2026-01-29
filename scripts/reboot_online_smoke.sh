#!/usr/bin/env bash
# reboot_online_smoke.sh - Smoke test for heartbeat resilience across reboots
#
# EDGE-CLOUD-3: Validates that a fresh install + reboot cycle does NOT
# revert to "never connected" / "unknown" / requiring manual activation.
#
# Validates:
#   Systemd Ordering:
#     1.  argus-dashboard.service After=network-online.target
#     2.  argus-dashboard.service Wants=network-online.target
#     3.  argus-dashboard.service Restart=always
#     4.  argus-dashboard.service has NO ConditionPathExists
#     5.  argus-uplink.service After=network-online.target
#     6.  argus-uplink.service Wants=network-online.target
#     7.  argus-uplink.service Restart=always
#   Heartbeat Independence:
#     8.  _cloud_status_loop launched as asyncio.create_task
#     9.  Heartbeat NOT gated on event_id
#    10.  Heartbeat NOT gated on .provisioned flag
#    11.  cloud_detail set to "not_configured" when no cloud_url
#    12.  Heartbeat sends regardless of event status (any status accepted)
#   Service Startup:
#    13.  argus-dashboard enabled on install (no manual activation)
#    14.  argus-uplink enabled on install
#    15.  No manual activation scripts required for heartbeat
#   Reboot Simulation (source-level):
#    16.  Dashboard service starts before uplink (no ordering conflict)
#    17.  Dashboard does not Require uplink (independent)
#    18.  Cloud heartbeat loop tolerates network-not-ready (catches exceptions)
#   Syntax:
#    19.  Python syntax compiles
#    20.  install.sh syntax OK
#
# Usage:
#   bash scripts/reboot_online_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[reboot-online]  $*"; }
pass() { echo "[reboot-online]    PASS: $*"; }
fail() { echo "[reboot-online]    FAIL: $*"; FAIL=1; }

INSTALL_SH="$REPO_ROOT/edge/install.sh"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "EDGE-CLOUD-3: Heartbeat Resilience Across Reboots Smoke Test"
echo ""

if [ ! -f "$INSTALL_SH" ]; then
  fail "install.sh not found"
  exit 1
fi
if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# Extract systemd unit definitions from install.sh (match heredoc start, stop at first EOF)
DASH_UNIT=$(awk '/system\/argus-dashboard.service/{found=1} found{print; if(/^EOF$/) exit}' "$INSTALL_SH")
UPLINK_UNIT=$(awk '/system\/argus-uplink.service/{found=1} found{print; if(/^EOF$/) exit}' "$INSTALL_SH")

# ═══════════════════════════════════════════════════════════════════
# SYSTEMD ORDERING
# ═══════════════════════════════════════════════════════════════════

# ── 1. Dashboard After=network-online.target ─────────────────────
log "Step 1: argus-dashboard After=network-online.target"
if echo "$DASH_UNIT" | grep -q 'After=network-online.target'; then
  pass "Dashboard waits for network-online.target"
else
  fail "Dashboard does not wait for network-online.target"
fi

# ── 2. Dashboard Wants=network-online.target ─────────────────────
log "Step 2: argus-dashboard Wants=network-online.target"
if echo "$DASH_UNIT" | grep -q 'Wants=network-online.target'; then
  pass "Dashboard wants network-online.target"
else
  fail "Dashboard missing Wants=network-online.target"
fi

# ── 3. Dashboard Restart=always ──────────────────────────────────
log "Step 3: argus-dashboard Restart=always"
if echo "$DASH_UNIT" | grep -q 'Restart=always'; then
  pass "Dashboard restarts always"
else
  fail "Dashboard missing Restart=always"
fi

# ── 4. Dashboard has NO ConditionPathExists ──────────────────────
log "Step 4: argus-dashboard has NO ConditionPathExists"
if echo "$DASH_UNIT" | grep -v '^#' | grep -q 'ConditionPathExists'; then
  fail "Dashboard has ConditionPathExists (should always start)"
else
  pass "Dashboard starts unconditionally"
fi

# ── 5. Uplink After=network-online.target ────────────────────────
log "Step 5: argus-uplink After=network-online.target"
if echo "$UPLINK_UNIT" | grep -q 'After=network-online.target'; then
  pass "Uplink waits for network-online.target"
else
  fail "Uplink does not wait for network-online.target"
fi

# ── 6. Uplink Wants=network-online.target ────────────────────────
log "Step 6: argus-uplink Wants=network-online.target"
if echo "$UPLINK_UNIT" | grep -q 'Wants=network-online.target'; then
  pass "Uplink wants network-online.target"
else
  fail "Uplink missing Wants=network-online.target"
fi

# ── 7. Uplink Restart=always ────────────────────────────────────
log "Step 7: argus-uplink Restart=always"
if echo "$UPLINK_UNIT" | grep -q 'Restart=always'; then
  pass "Uplink restarts always"
else
  fail "Uplink missing Restart=always"
fi

# ═══════════════════════════════════════════════════════════════════
# HEARTBEAT INDEPENDENCE
# ═══════════════════════════════════════════════════════════════════

# ── 8. _cloud_status_loop launched as asyncio.create_task ────────
log "Step 8: _cloud_status_loop launched as asyncio.create_task"
if grep -q 'create_task(self._cloud_status_loop' "$PIT_DASH"; then
  pass "Heartbeat loop is independent asyncio task"
else
  fail "Heartbeat loop not launched as asyncio task"
fi

# ── 9. Heartbeat NOT gated on event_id ───────────────────────────
log "Step 9: Heartbeat NOT gated on event_id"
CLOUD_LOOP=$(sed -n '/_cloud_status_loop/,/^    async def \|^    def [a-z]/p' "$PIT_DASH")
HB_LINE=$(echo "$CLOUD_LOOP" | grep -n '_send_cloud_heartbeat' | head -1 | cut -d: -f1)
EVENT_LINE=$(echo "$CLOUD_LOOP" | grep -n 'if self.config.event_id:' | head -1 | cut -d: -f1)
if [ -n "$HB_LINE" ] && [ -n "$EVENT_LINE" ] && [ "$HB_LINE" -lt "$EVENT_LINE" ]; then
  pass "Heartbeat called before event_id gate"
else
  fail "Heartbeat may be gated on event_id"
fi

# ── 10. Heartbeat NOT gated on .provisioned flag ─────────────────
log "Step 10: Heartbeat NOT gated on .provisioned flag"
if echo "$CLOUD_LOOP" | grep -q '\.provisioned'; then
  fail "Heartbeat checks .provisioned flag"
else
  pass "Heartbeat does not check .provisioned flag"
fi

# ── 11. cloud_detail set to "not_configured" when no cloud_url ──
log "Step 11: cloud_detail set to not_configured when no cloud_url"
if echo "$CLOUD_LOOP" | grep -q 'not_configured'; then
  pass "Handles not_configured state"
else
  fail "Missing not_configured fallback"
fi

# ── 12. Heartbeat sends regardless of event status ───────────────
log "Step 12: Heartbeat sends regardless of event status"
HB_FUNC=$(sed -n '/_send_cloud_heartbeat/,/^    async def \|^    def [a-z]/p' "$PIT_DASH")
if echo "$HB_FUNC" | grep -q 'event_status'; then
  pass "Heartbeat response includes event_status (accepts any status)"
else
  fail "Heartbeat may not handle event_status"
fi

# ═══════════════════════════════════════════════════════════════════
# SERVICE STARTUP
# ═══════════════════════════════════════════════════════════════════

# ── 13. Dashboard enabled on install ─────────────────────────────
log "Step 13: argus-dashboard enabled on install"
if grep -q 'systemctl.*enable.*argus-dashboard\|enable.*argus-dashboard' "$INSTALL_SH"; then
  pass "Dashboard enabled on install"
else
  fail "Dashboard not enabled on install"
fi

# ── 14. Uplink enabled on install ────────────────────────────────
log "Step 14: argus-uplink enabled on install"
if grep -q 'systemctl.*enable.*argus-uplink' "$INSTALL_SH"; then
  pass "Uplink enabled on install"
else
  fail "Uplink not enabled on install"
fi

# ── 15. No manual activation scripts required ────────────────────
log "Step 15: No manual activation scripts required for heartbeat"
# The heartbeat should start automatically via dashboard service.
# Check that install.sh starts the dashboard immediately.
if grep -q 'systemctl.*start.*argus-dashboard' "$INSTALL_SH"; then
  pass "Dashboard started on install (no manual activation)"
else
  fail "Dashboard not started on install"
fi

# ═══════════════════════════════════════════════════════════════════
# REBOOT SIMULATION (source-level)
# ═══════════════════════════════════════════════════════════════════

# ── 16. Dashboard starts before uplink (no ordering conflict) ────
log "Step 16: Dashboard does not depend on uplink ordering"
if echo "$DASH_UNIT" | grep -q 'argus-uplink'; then
  fail "Dashboard has ordering dependency on uplink"
else
  pass "Dashboard starts independently of uplink"
fi

# ── 17. Dashboard does not Require uplink ────────────────────────
log "Step 17: Dashboard does not Require uplink"
if echo "$DASH_UNIT" | grep -q 'Requires='; then
  fail "Dashboard has hard Requires= dependency"
else
  pass "Dashboard has no hard Requires= dependency"
fi

# ── 18. Cloud heartbeat loop tolerates network-not-ready ─────────
log "Step 18: Cloud heartbeat loop catches exceptions"
if echo "$CLOUD_LOOP" | grep -q 'except.*Exception\|except.*httpx\|except:'; then
  pass "Heartbeat loop has exception handling"
else
  fail "Heartbeat loop missing exception handling"
fi

# ═══════════════════════════════════════════════════════════════════
# SYNTAX
# ═══════════════════════════════════════════════════════════════════

# ── 19. Python syntax compiles ───────────────────────────────────
log "Step 19: Python syntax compiles"
if python3 -c "import ast; ast.parse(open('$PIT_DASH').read())" 2>/dev/null; then
  pass "Python syntax OK"
else
  fail "Python syntax error"
fi

# ── 20. install.sh syntax OK ────────────────────────────────────
log "Step 20: install.sh syntax OK"
if bash -n "$INSTALL_SH" 2>/dev/null; then
  pass "install.sh syntax OK"
else
  fail "install.sh syntax error"
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
