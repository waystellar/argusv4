#!/usr/bin/env bash
# link_cloud_loop_smoke.sh — Smoke test for LINK-1 cloud status loop restart fix
#
# Validates that _cloud_status_loop never permanently exits when settings are
# missing, and that settings save triggers a restart of the loop.
#
# Sections:
#   A. Python syntax — compiles without errors
#   B. Loop no longer exits permanently on missing config
#   C. _cloud_status_task instance variable exists
#   D. _restart_cloud_status_loop helper exists with correct behavior
#   E. Settings save handler calls restart
#   F. Setup handler calls restart
#   G. Startup tracks task handle
#   H. Runtime integration (if edge is running locally)
#
# Usage:
#   bash scripts/link_cloud_loop_smoke.sh
#
# Exit codes:
#   0 — all checks passed (SKIPs allowed)
#   1 — at least one FAIL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0
SKIP=0

log()  { echo "[link-1]  $*"; }
pass() { echo "[link-1]    PASS: $*"; }
fail() { echo "[link-1]    FAIL: $*"; FAIL=1; }
skip() { echo "[link-1]    SKIP: $*"; SKIP=1; }

DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "LINK-1: Cloud Status Loop Restart Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION A: Python Syntax
# ═══════════════════════════════════════════════════════════════════
log "─── Section A: Python Syntax ───"

log "A1: pit_crew_dashboard.py compiles"
if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles cleanly"
else
  fail "pit_crew_dashboard.py has syntax errors"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION B: Loop Never Permanently Exits on Missing Config
# ═══════════════════════════════════════════════════════════════════
log "─── Section B: Loop Idling Behavior ───"

# B1: The old pattern was: if not configured → return (exit forever)
# New pattern: if not configured → set state + sleep + continue
log "B1: No permanent return on missing cloud config"
# Extract the _cloud_status_loop function body and check for the old pattern
# The old code had: "if not self.config.cloud_url or not self.config.truck_token:" followed by "return"
# New code should use "continue" instead of "return" after the not-configured check
if python3 -c "
import ast, sys

with open('$DASHBOARD') as f:
    source = f.read()

tree = ast.parse(source)

for node in ast.walk(tree):
    if isinstance(node, ast.AsyncFunctionDef) and node.name == '_cloud_status_loop':
        # Find the while loop body
        has_while = False
        for child in ast.walk(node):
            if isinstance(child, ast.While):
                has_while = True
                # Inside the while loop, the config check should use Continue, not Return
                for stmt in ast.walk(child):
                    if isinstance(stmt, ast.If):
                        # Look for the 'not self.config.cloud_url' check inside while
                        src_lines = source.split('\n')
                        if_line = src_lines[stmt.lineno - 1]
                        if 'cloud_url' in if_line and 'truck_token' in if_line:
                            # Check that the body has Continue, not Return
                            for body_stmt in stmt.body:
                                if isinstance(body_stmt, ast.Return):
                                    print('FOUND_RETURN_IN_WHILE')
                                    sys.exit(1)
        # Also check that there's no bare return right before the while loop
        # that would kill the function on missing config
        for i, child in enumerate(node.body):
            if isinstance(child, ast.If):
                src_lines = source.split('\n')
                if_line = src_lines[child.lineno - 1]
                if 'cloud_url' in if_line or 'truck_token' in if_line:
                    for body_stmt in child.body:
                        if isinstance(body_stmt, ast.Return):
                            print('FOUND_EARLY_RETURN')
                            sys.exit(1)

sys.exit(0)
" 2>/dev/null; then
  pass "No permanent return on missing cloud config in _cloud_status_loop"
else
  fail "_cloud_status_loop still has permanent return on missing config"
fi

# B2: Loop body contains 'continue' after not-configured check (idling)
log "B2: Loop idles with continue when not configured"
if grep -A5 'not self.config.cloud_url or not self.config.truck_token' "$DASHBOARD" | grep -q 'continue'; then
  pass "Loop uses continue (idle) when not configured"
else
  fail "Loop missing continue after not-configured check"
fi

# B3: Loop sets cloud_detail to not_configured when idling
log "B3: Sets cloud_detail = not_configured when idling"
if grep -A3 'not self.config.cloud_url or not self.config.truck_token' "$DASHBOARD" | grep -q '"not_configured"'; then
  pass "Sets cloud_detail to not_configured"
else
  fail "Missing cloud_detail = not_configured in idle path"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION C: _cloud_status_task Instance Variable
# ═══════════════════════════════════════════════════════════════════
log "─── Section C: Task Handle Tracking ───"

log "C1: _cloud_status_task initialized in __init__"
if grep -q 'self._cloud_status_task' "$DASHBOARD" && grep 'self._cloud_status_task' "$DASHBOARD" | grep -q 'None'; then
  pass "_cloud_status_task initialized to None"
else
  fail "_cloud_status_task not initialized in __init__"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION D: _restart_cloud_status_loop Helper
# ═══════════════════════════════════════════════════════════════════
log "─── Section D: Restart Helper ───"

# D1: Helper method exists
log "D1: _restart_cloud_status_loop method exists"
if grep -q 'def _restart_cloud_status_loop' "$DASHBOARD"; then
  pass "_restart_cloud_status_loop method exists"
else
  fail "_restart_cloud_status_loop method missing"
fi

# D2: Helper cancels existing task
log "D2: Restart helper cancels existing task"
if grep -A10 'def _restart_cloud_status_loop' "$DASHBOARD" | grep -q 'cancel()'; then
  pass "Restart helper cancels existing task"
else
  fail "Restart helper does not cancel existing task"
fi

# D3: Helper creates new task
log "D3: Restart helper creates new task"
if grep -A15 'def _restart_cloud_status_loop' "$DASHBOARD" | grep -q '_cloud_status_loop()'; then
  pass "Restart helper creates new _cloud_status_loop task"
else
  fail "Restart helper does not create new task"
fi

# D4: Helper checks .done() before cancel (avoids cancelling completed task)
log "D4: Restart helper checks task.done() before cancel"
if grep -A10 'def _restart_cloud_status_loop' "$DASHBOARD" | grep -q 'done()'; then
  pass "Restart helper checks done() before cancel"
else
  fail "Restart helper does not check done() — may cancel completed task"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION E: Settings Save Handler Calls Restart
# ═══════════════════════════════════════════════════════════════════
log "─── Section E: Settings Save Wiring ───"

log "E1: handle_settings calls _restart_cloud_status_loop"
if grep -A30 'async def handle_settings' "$DASHBOARD" | grep -q '_restart_cloud_status_loop'; then
  pass "handle_settings calls _restart_cloud_status_loop"
else
  fail "handle_settings does not call _restart_cloud_status_loop"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION F: Setup Handler Calls Restart
# ═══════════════════════════════════════════════════════════════════
log "─── Section F: Setup Handler Wiring ───"

log "F1: handle_setup calls _restart_cloud_status_loop"
if grep -A50 'async def handle_setup' "$DASHBOARD" | grep -q '_restart_cloud_status_loop'; then
  pass "handle_setup calls _restart_cloud_status_loop"
else
  fail "handle_setup does not call _restart_cloud_status_loop"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION G: Startup Tracks Task Handle
# ═══════════════════════════════════════════════════════════════════
log "─── Section G: Startup Task Handle ───"

log "G1: Startup assigns _cloud_status_task"
if grep -q 'self._cloud_status_task = asyncio.create_task(self._cloud_status_loop' "$DASHBOARD"; then
  pass "Startup assigns _cloud_status_task from create_task"
else
  fail "Startup does not assign _cloud_status_task"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION H: Runtime Integration (optional — requires running edge)
# ═══════════════════════════════════════════════════════════════════
log "─── Section H: Runtime Integration ───"

EDGE_PORT="${ARGUS_EDGE_PORT:-8080}"
EDGE_HOST="${ARGUS_EDGE_HOST:-localhost}"
EDGE_URL="http://${EDGE_HOST}:${EDGE_PORT}"

# H1: Check if edge is running
log "H1: Edge reachability check"
EDGE_BODY=$(curl -s --connect-timeout 2 --max-time 3 \
  "${EDGE_URL}/api/telemetry/current" 2>/dev/null || true)

# Verify response is valid JSON with expected fields
if echo "$EDGE_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'cloud_detail' in d" 2>/dev/null; then
  pass "Edge reachable at ${EDGE_URL}"

  # H2: Check current cloud_detail
  log "H2: Current cloud_detail value"
  CLOUD_DETAIL=$(echo "$EDGE_BODY" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cloud_detail','MISSING'))" 2>/dev/null || echo "ERROR")
  if [ "$CLOUD_DETAIL" != "ERROR" ] && [ "$CLOUD_DETAIL" != "MISSING" ]; then
    pass "cloud_detail is '$CLOUD_DETAIL'"
  else
    fail "Could not read cloud_detail from /api/telemetry/current"
  fi

  # H3: If cloud_detail is not_configured, save settings and re-check
  if [ "$CLOUD_DETAIL" = "not_configured" ]; then
    log "H3: cloud_detail is not_configured — would need authenticated settings POST to test restart"
    skip "Runtime restart test requires authenticated session (manual test recommended)"
  else
    log "H3: cloud_detail is already '$CLOUD_DETAIL' — loop is running"
    pass "Cloud status loop is active (cloud_detail != not_configured)"
  fi
else
  skip "Edge not running at ${EDGE_URL} — runtime checks skipped"
  skip "To run runtime checks: start the edge, then re-run this script"
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
