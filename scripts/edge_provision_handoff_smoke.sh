#!/usr/bin/env bash
# edge_provision_handoff_smoke.sh — Smoke test for provision → dashboard handoff
#
# Validates:
#   1. install.sh provision server contains schedule_service_handoff()
#   2. SUCCESS_TEMPLATE polls for dashboard (no meta refresh to /status)
#   3. activate_telemetry() calls schedule_service_handoff()
#   4. Handoff script uses start_new_session=True (survives parent kill)
#   5. SUCCESS_TEMPLATE uses /api/edge/status as readiness probe
#   6. /status route still exists (diagnostics not removed)
#   7. Sudoers permits systemctl stop/start argus-* (source-level check)
#
# Usage:
#   bash scripts/edge_provision_handoff_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/edge/install.sh"
FAIL=0

log()  { echo "[handoff-smoke] $*"; }
pass() { echo "[handoff-smoke]   PASS: $*"; }
fail() { echo "[handoff-smoke]   FAIL: $*"; FAIL=1; }
warn() { echo "[handoff-smoke]   WARN: $*"; }
info() { echo "[handoff-smoke]   INFO: $*"; }

# ── 1. schedule_service_handoff() exists ─────────────────────────
log "Step 1: schedule_service_handoff function exists"

if [ ! -f "$INSTALL_SH" ]; then
  fail "install.sh not found at $INSTALL_SH"
else
  if grep -q "def schedule_service_handoff" "$INSTALL_SH" 2>/dev/null; then
    pass "schedule_service_handoff() defined in install.sh"
  else
    fail "schedule_service_handoff() NOT found in install.sh"
  fi
fi

# ── 2. SUCCESS_TEMPLATE no longer meta-refreshes to /status ──────
log "Step 2: SUCCESS_TEMPLATE does not meta-refresh to /status"

if grep -q 'meta http-equiv="refresh".*url=/status' "$INSTALL_SH" 2>/dev/null; then
  # Check if it's inside SUCCESS_TEMPLATE (not STATUS_TEMPLATE)
  # STATUS_TEMPLATE's auto-refresh is OK — it refreshes itself
  SUCCESS_SECTION=$(sed -n '/^SUCCESS_TEMPLATE/,/^"""/p' "$INSTALL_SH")
  if echo "$SUCCESS_SECTION" | grep -q 'url=/status'; then
    fail "SUCCESS_TEMPLATE still has meta refresh to /status"
  else
    pass "SUCCESS_TEMPLATE does not meta-refresh to /status"
  fi
else
  pass "No meta refresh to /status in SUCCESS_TEMPLATE"
fi

# ── 3. activate_telemetry calls schedule_service_handoff ─────────
log "Step 3: activate_telemetry() calls schedule_service_handoff()"

# Extract activate_telemetry function body
ACTIVATE_BODY=$(sed -n '/^def activate_telemetry/,/^def [a-z]/p' "$INSTALL_SH" | head -80)
if echo "$ACTIVATE_BODY" | grep -q "schedule_service_handoff()" 2>/dev/null; then
  pass "activate_telemetry() calls schedule_service_handoff()"
else
  fail "activate_telemetry() does NOT call schedule_service_handoff()"
fi

# ── 4. Handoff uses start_new_session (process detachment) ───────
log "Step 4: Handoff uses start_new_session=True"

HANDOFF_BODY=$(sed -n '/^def schedule_service_handoff/,/^def [a-z]/p' "$INSTALL_SH" | head -20)
if echo "$HANDOFF_BODY" | grep -q "start_new_session=True" 2>/dev/null; then
  pass "Handoff process is session-detached (start_new_session=True)"
else
  fail "Handoff process NOT session-detached — will die with parent"
fi

# ── 5. SUCCESS_TEMPLATE polls /api/edge/status ───────────────────
log "Step 5: SUCCESS_TEMPLATE polls dashboard readiness endpoint"

SUCCESS_SECTION=$(sed -n '/^SUCCESS_TEMPLATE/,/^"""/p' "$INSTALL_SH")
if echo "$SUCCESS_SECTION" | grep -q "/api/edge/status" 2>/dev/null; then
  pass "SUCCESS_TEMPLATE polls /api/edge/status"
else
  fail "SUCCESS_TEMPLATE does NOT poll /api/edge/status"
fi

# Also verify it redirects to / on success
if echo "$SUCCESS_SECTION" | grep -q "location.href.*=.*'/'" 2>/dev/null; then
  pass "SUCCESS_TEMPLATE redirects to / when dashboard ready"
else
  # Try alternate patterns
  if echo "$SUCCESS_SECTION" | grep -q 'location.href' 2>/dev/null; then
    pass "SUCCESS_TEMPLATE redirects on dashboard ready"
  else
    fail "SUCCESS_TEMPLATE does NOT redirect when dashboard is ready"
  fi
fi

# ── 6. /status route still exists ────────────────────────────────
log "Step 6: /status diagnostic route preserved"

if grep -q "@app.route('/status')" "$INSTALL_SH" 2>/dev/null; then
  pass "/status route still defined"
else
  fail "/status route removed — diagnostics lost"
fi

# Also verify STATUS_TEMPLATE still exists
if grep -q "STATUS_TEMPLATE" "$INSTALL_SH" 2>/dev/null; then
  pass "STATUS_TEMPLATE still defined"
else
  fail "STATUS_TEMPLATE removed"
fi

# ── 7. Sudoers permits stop/start argus-* ────────────────────────
log "Step 7: Sudoers source-level check"

if grep -q "NOPASSWD.*systemctl stop argus" "$INSTALL_SH" 2>/dev/null; then
  pass "Sudoers allows systemctl stop argus-*"
else
  fail "Sudoers missing systemctl stop for argus services"
fi

if grep -q "NOPASSWD.*systemctl start argus" "$INSTALL_SH" 2>/dev/null; then
  pass "Sudoers allows systemctl start argus-*"
else
  fail "Sudoers missing systemctl start for argus services"
fi

# ── 8. Handoff command sequence is correct ───────────────────────
log "Step 8: Handoff command sequence"

if echo "$HANDOFF_BODY" | grep -q "stop argus-provision" 2>/dev/null; then
  pass "Handoff stops argus-provision"
else
  fail "Handoff does NOT stop argus-provision"
fi

if echo "$HANDOFF_BODY" | grep -q "start argus-dashboard" 2>/dev/null; then
  pass "Handoff starts argus-dashboard"
else
  fail "Handoff does NOT start argus-dashboard"
fi

# Verify stop comes before start (sleep between them)
if echo "$HANDOFF_BODY" | grep -q "stop argus-provision.*sleep.*start argus-dashboard" 2>/dev/null; then
  pass "Handoff has delay between stop and start"
else
  # Check multi-line
  STOP_LINE=$(echo "$HANDOFF_BODY" | grep -n "stop argus-provision" | head -1 | cut -d: -f1)
  START_LINE=$(echo "$HANDOFF_BODY" | grep -n "start argus-dashboard" | head -1 | cut -d: -f1)
  if [ -n "$STOP_LINE" ] && [ -n "$START_LINE" ]; then
    if [ "$STOP_LINE" -lt "$START_LINE" ]; then
      pass "Handoff: stop before start (correct order)"
    else
      fail "Handoff: start before stop (wrong order)"
    fi
  else
    warn "Could not verify stop/start ordering"
  fi
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
