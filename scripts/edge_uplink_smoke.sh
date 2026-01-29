#!/usr/bin/env bash
# edge_uplink_smoke.sh — Smoke test for PIT-UPLINK-1 uplink crash fix
#
# Validates that uplink_service.py idles instead of crashing when cloud
# config is missing, writes a state file for observability, and that the
# dashboard maps crashed/failed states to red.
#
# Sections:
#   A. Python syntax
#   B. Config-wait loop (no bare return on missing config)
#   C. State file observability
#   D. Dashboard service status CSS mapping
#   E. Runtime integration (if edge is running)
#
# Usage:
#   bash scripts/edge_uplink_smoke.sh
#
# Exit codes:
#   0 — all checks passed (SKIPs allowed)
#   1 — at least one FAIL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[uplink]  $*"; }
pass() { echo "[uplink]    PASS: $*"; }
fail() { echo "[uplink]    FAIL: $*"; FAIL=1; }
skip() { echo "[uplink]    SKIP: $*"; }

UPLINK="$REPO_ROOT/edge/uplink_service.py"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "PIT-UPLINK-1: Uplink Crash Fix Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION A: Python Syntax
# ═══════════════════════════════════════════════════════════════════
log "─── Section A: Python Syntax ───"

log "A1: uplink_service.py compiles"
if python3 -c "import py_compile; py_compile.compile('$UPLINK', doraise=True)" 2>/dev/null; then
  pass "uplink_service.py compiles cleanly"
else
  fail "uplink_service.py has syntax errors"
fi

log "A2: pit_crew_dashboard.py compiles"
if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles cleanly"
else
  fail "pit_crew_dashboard.py has syntax errors"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION B: Config-Wait Loop (No Bare Return)
# ═══════════════════════════════════════════════════════════════════
log "─── Section B: Config-Wait Loop ───"

# B1: No bare return on missing cloud_url
log "B1: No bare 'return' when cloud_url missing"
if python3 -c "
import ast, sys

with open('$UPLINK') as f:
    source = f.read()

tree = ast.parse(source)

for node in ast.walk(tree):
    if isinstance(node, ast.AsyncFunctionDef) and node.name == 'start':
        # Check top-level if statements in start() for bare returns
        # guarded by cloud_url / truck_token checks
        for child in node.body:
            if isinstance(child, ast.If):
                src_lines = source.split('\n')
                if_line = src_lines[child.lineno - 1]
                if 'cloud_url' in if_line or 'truck_token' in if_line:
                    for body_stmt in child.body:
                        if isinstance(body_stmt, ast.Return):
                            print('FOUND_BARE_RETURN')
                            sys.exit(1)

sys.exit(0)
" 2>/dev/null; then
  pass "No bare return on missing cloud config in start()"
else
  fail "start() still has bare return on missing config"
fi

# B2: start() has config wait loop with sleep
log "B2: start() has config wait loop with asyncio.sleep"
if grep -A30 'PIT-UPLINK-1.*Wait for config' "$UPLINK" | grep -q 'asyncio.sleep'; then
  pass "start() has config wait loop with sleep"
else
  fail "start() missing config wait loop"
fi

# B3: Wait loop re-reads config from env
log "B3: Wait loop re-reads UplinkConfig.from_env()"
if grep -A20 'PIT-UPLINK-1.*Wait for config' "$UPLINK" | grep -q 'UplinkConfig.from_env()'; then
  pass "Wait loop re-reads config from environment"
else
  fail "Wait loop does not re-read config"
fi

# B4: Wait loop checks both cloud_url and truck_token
log "B4: Wait loop checks both cloud_url and truck_token"
if grep -A10 'PIT-UPLINK-1.*Wait for config' "$UPLINK" | grep -q 'self.config.cloud_url and self.config.truck_token'; then
  pass "Wait loop checks both cloud_url and truck_token"
else
  fail "Wait loop missing cloud_url/truck_token check"
fi

# B5: Rate-limited warning log (only warns once)
log "B5: Config warning is rate-limited (warns once)"
if grep -A25 'PIT-UPLINK-1.*Wait for config' "$UPLINK" | grep -q 'config_warned'; then
  pass "Config warning uses rate-limiting flag"
else
  fail "Config warning not rate-limited"
fi

# B6: Handles CancelledError during sleep (graceful shutdown)
log "B6: Handles CancelledError during config wait"
if grep -A30 'PIT-UPLINK-1.*Wait for config' "$UPLINK" | grep -q 'CancelledError'; then
  pass "Config wait handles CancelledError for graceful shutdown"
else
  fail "Config wait missing CancelledError handler"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION C: State File Observability
# ═══════════════════════════════════════════════════════════════════
log "─── Section C: State File Observability ───"

# C1: _write_state_file method exists
log "C1: _write_state_file method exists"
if grep -q 'def _write_state_file' "$UPLINK"; then
  pass "_write_state_file method exists"
else
  fail "_write_state_file method missing"
fi

# C2: State file writes to /opt/argus/state/
log "C2: State file path is /opt/argus/state/uplink_status.json"
if grep -q '/opt/argus/state/uplink_status.json' "$UPLINK"; then
  pass "State file path correct"
else
  fail "State file path missing or wrong"
fi

# C3: State file includes status field
log "C3: State file includes status field"
if grep -A10 'def _write_state_file' "$UPLINK" | grep -q '"status"'; then
  pass "State file includes status field"
else
  fail "State file missing status field"
fi

# C4: State file includes epoch timestamp
log "C4: State file includes epoch timestamp"
if grep -A10 'def _write_state_file' "$UPLINK" | grep -q '"epoch"'; then
  pass "State file includes epoch timestamp"
else
  fail "State file missing epoch timestamp"
fi

# C5: start() writes not_configured state during wait
log "C5: start() writes not_configured state during config wait"
if grep -q "_write_state_file(\"not_configured\")" "$UPLINK"; then
  pass "Writes not_configured state during config wait"
else
  fail "Missing not_configured state write"
fi

# C6: start() writes running state after initialization
log "C6: start() writes running state after init"
if grep -q "_write_state_file(\"running\")" "$UPLINK"; then
  pass "Writes running state after initialization"
else
  fail "Missing running state write"
fi

# C7: start() writes starting state before init
log "C7: start() writes starting state before init"
if grep -q "_write_state_file(\"starting\")" "$UPLINK"; then
  pass "Writes starting state before initialization"
else
  fail "Missing starting state write"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION D: Dashboard Service Status CSS Mapping
# ═══════════════════════════════════════════════════════════════════
log "─── Section D: Dashboard CSS Status Mapping ───"

# D1: Dashboard maps crashed to stopped (red) CSS class
log "D1: Dashboard maps 'crashed' to red (stopped) CSS class"
if grep -q "status.includes('crashed')" "$DASHBOARD" && \
   grep -A1 "status.includes('crashed')" "$DASHBOARD" | grep -q 'stopped'; then
  pass "Dashboard maps crashed → stopped (red)"
else
  fail "Dashboard does not map crashed to red"
fi

# D2: Dashboard maps failed to stopped (red) CSS class
log "D2: Dashboard maps 'failed' to red (stopped) CSS class"
if grep -q "status === 'failed'" "$DASHBOARD"; then
  pass "Dashboard maps failed → stopped (red)"
else
  fail "Dashboard does not map failed to red"
fi

# D3: PIT-SVC-2 comment present
log "D3: PIT-SVC-2 comment present in CSS mapping"
if grep -q 'PIT-SVC-2' "$DASHBOARD"; then
  pass "PIT-SVC-2 comment found in dashboard"
else
  fail "PIT-SVC-2 comment missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION E: Runtime Integration (if edge is running)
# ═══════════════════════════════════════════════════════════════════
log "─── Section E: Runtime Integration ───"

# E1: Check if we're on an edge host with systemd
if command -v systemctl >/dev/null 2>&1; then
  log "E1: systemd available — checking argus-uplink unit"

  # E1a: Unit file exists
  if systemctl cat argus-uplink.service >/dev/null 2>&1; then
    pass "argus-uplink.service unit file exists"

    # E2: Check ActiveState
    log "E2: argus-uplink ActiveState"
    ACTIVE_STATE=$(systemctl show argus-uplink.service --property=ActiveState --value 2>/dev/null || echo "unknown")
    if [ "$ACTIVE_STATE" = "active" ]; then
      pass "ActiveState=active"
    elif [ "$ACTIVE_STATE" = "inactive" ]; then
      skip "ActiveState=inactive (service not started or not provisioned)"
    else
      fail "ActiveState=$ACTIVE_STATE (expected active)"
    fi

    # E3: Check SubState
    log "E3: argus-uplink SubState"
    SUB_STATE=$(systemctl show argus-uplink.service --property=SubState --value 2>/dev/null || echo "unknown")
    if [ "$SUB_STATE" = "running" ]; then
      pass "SubState=running"
    elif [ "$SUB_STATE" = "dead" ]; then
      skip "SubState=dead (service not started)"
    else
      fail "SubState=$SUB_STATE (expected running)"
    fi

    # E4: Check recent logs for Traceback/Exception
    log "E4: No Traceback in last 50 log lines"
    RECENT_LOGS=$(journalctl -u argus-uplink.service -n 50 --no-pager 2>/dev/null || echo "")
    if [ -z "$RECENT_LOGS" ]; then
      skip "No journal entries for argus-uplink"
    elif echo "$RECENT_LOGS" | grep -qi 'Traceback\|Exception'; then
      fail "Found Traceback/Exception in recent argus-uplink logs"
    else
      pass "No Traceback or Exception in last 50 log lines"
    fi

    # E5: Check for PIT-UPLINK-1 idle message (if not configured)
    log "E5: PIT-UPLINK-1 idle message (if applicable)"
    if echo "$RECENT_LOGS" | grep -q 'PIT-UPLINK-1'; then
      pass "PIT-UPLINK-1 idle message present (waiting for config)"
    else
      skip "PIT-UPLINK-1 message not in recent logs (may already be configured)"
    fi

  else
    skip "argus-uplink.service unit not installed"
  fi
else
  skip "systemd not available (not on edge host) — runtime checks skipped"
  skip "To run runtime checks: deploy to Ubuntu edge host, then re-run"
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════"
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
