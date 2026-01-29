#!/usr/bin/env bash
# pit_visibility_smoke.sh - Smoke test for Fan Visibility Controls
#
# PIT-VIS-0: Validates that fan visibility buttons work end-to-end:
# JS function exists, CSP nonce present, backend endpoints registered,
# persistence works, and cloud sync is wired.
#
# Validates:
#   JS Function:
#     1.  setFanVisibility function exists in JS
#     2.  updateVisibilityUI function exists
#     3.  loadTeamState function exists
#     4.  Team script block has CSP nonce
#   HTML Wiring:
#     5.  btnVisibilityOn button exists with data-click
#     6.  btnVisibilityOff button exists with data-click
#     7.  visibilityBadge element exists
#     8.  visibilitySyncStatus element exists
#   Backend Endpoints:
#     9.  GET /api/team/visibility route registered
#    10.  POST /api/team/visibility route registered
#   Backend Handlers:
#    11.  handle_get_visibility handler exists
#    12.  handle_set_visibility handler exists
#    13.  handle_set_visibility saves state (_save_fan_visibility)
#    14.  handle_set_visibility syncs to cloud (best-effort)
#   Persistence:
#    15.  _fan_visibility field exists
#    16.  _load_fan_visibility method exists
#    17.  _save_fan_visibility method exists
#    18.  fan_visibility.json path defined
#   Cloud Sync:
#    19.  Cloud sync attempts POST to cloud URL
#    20.  Sync result returned in response (synced field)
#   Syntax:
#    21.  Python syntax compiles
#
# Usage:
#   bash scripts/pit_visibility_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[pit-vis]  $*"; }
pass() { echo "[pit-vis]    PASS: $*"; }
fail() { echo "[pit-vis]    FAIL: $*"; FAIL=1; }

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "PIT-VIS-0: Fan Visibility Controls Smoke Test"
echo ""

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# JS FUNCTION
# ═══════════════════════════════════════════════════════════════════

# ── 1. setFanVisibility function exists ──────────────────────────
log "Step 1: setFanVisibility function exists"
if grep -q 'function setFanVisibility' "$PIT_DASH"; then
  pass "setFanVisibility function defined"
else
  fail "setFanVisibility function missing"
fi

# ── 2. updateVisibilityUI function exists ────────────────────────
log "Step 2: updateVisibilityUI function exists"
if grep -q 'function updateVisibilityUI' "$PIT_DASH"; then
  pass "updateVisibilityUI function defined"
else
  fail "updateVisibilityUI function missing"
fi

# ── 3. loadTeamState function exists ─────────────────────────────
log "Step 3: loadTeamState function exists"
if grep -q 'function loadTeamState' "$PIT_DASH"; then
  pass "loadTeamState function defined"
else
  fail "loadTeamState function missing"
fi

# ── 4. Team script block has CSP nonce ───────────────────────────
log "Step 4: Team script block has CSP nonce"
# The script block containing setFanVisibility must have nonce
# Find the <script> tag preceding setFanVisibility
SCRIPT_TAG=$(grep -B 200 'function setFanVisibility' "$PIT_DASH" | grep '<script' | tail -1)
if echo "$SCRIPT_TAG" | grep -q '__CSP_NONCE__'; then
  pass "Team script block has CSP nonce"
else
  fail "Team script block MISSING CSP nonce (functions will be blocked)"
fi

# ═══════════════════════════════════════════════════════════════════
# HTML WIRING
# ═══════════════════════════════════════════════════════════════════

# ── 5. btnVisibilityOn with data-click ───────────────────────────
log "Step 5: btnVisibilityOn button with data-click"
if grep -q 'id="btnVisibilityOn".*data-click="setFanVisibility"' "$PIT_DASH"; then
  pass "btnVisibilityOn wired via data-click"
else
  fail "btnVisibilityOn missing or not wired"
fi

# ── 6. btnVisibilityOff with data-click ──────────────────────────
log "Step 6: btnVisibilityOff button with data-click"
if grep -q 'id="btnVisibilityOff".*data-click="setFanVisibility"' "$PIT_DASH"; then
  pass "btnVisibilityOff wired via data-click"
else
  fail "btnVisibilityOff missing or not wired"
fi

# ── 7. visibilityBadge element ───────────────────────────────────
log "Step 7: visibilityBadge element exists"
if grep -q 'id="visibilityBadge"' "$PIT_DASH"; then
  pass "visibilityBadge element exists"
else
  fail "visibilityBadge element missing"
fi

# ── 8. visibilitySyncStatus element ──────────────────────────────
log "Step 8: visibilitySyncStatus element exists"
if grep -q 'id="visibilitySyncStatus"' "$PIT_DASH"; then
  pass "visibilitySyncStatus element exists"
else
  fail "visibilitySyncStatus element missing"
fi

# ═══════════════════════════════════════════════════════════════════
# BACKEND ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

# ── 9. GET /api/team/visibility ──────────────────────────────────
log "Step 9: GET /api/team/visibility route registered"
if grep -q "add_get.*/api/team/visibility.*handle_get_visibility" "$PIT_DASH"; then
  pass "GET /api/team/visibility registered"
else
  fail "GET /api/team/visibility missing"
fi

# ── 10. POST /api/team/visibility ────────────────────────────────
log "Step 10: POST /api/team/visibility route registered"
if grep -q "add_post.*/api/team/visibility.*handle_set_visibility" "$PIT_DASH"; then
  pass "POST /api/team/visibility registered"
else
  fail "POST /api/team/visibility missing"
fi

# ═══════════════════════════════════════════════════════════════════
# BACKEND HANDLERS
# ═══════════════════════════════════════════════════════════════════

# ── 11. handle_get_visibility ────────────────────────────────────
log "Step 11: handle_get_visibility handler exists"
if grep -q 'def handle_get_visibility' "$PIT_DASH"; then
  pass "handle_get_visibility exists"
else
  fail "handle_get_visibility missing"
fi

# ── 12. handle_set_visibility ────────────────────────────────────
log "Step 12: handle_set_visibility handler exists"
if grep -q 'def handle_set_visibility' "$PIT_DASH"; then
  pass "handle_set_visibility exists"
else
  fail "handle_set_visibility missing"
fi

# ── 13. handle_set_visibility saves state ────────────────────────
log "Step 13: handle_set_visibility saves state"
if grep -A 50 'def handle_set_visibility' "$PIT_DASH" | grep -q '_save_fan_visibility'; then
  pass "handle_set_visibility calls _save_fan_visibility"
else
  fail "handle_set_visibility missing persistence"
fi

# ── 14. handle_set_visibility syncs to cloud ─────────────────────
log "Step 14: handle_set_visibility syncs to cloud"
if grep -A 50 'def handle_set_visibility' "$PIT_DASH" | grep -q 'cloud_url'; then
  pass "handle_set_visibility attempts cloud sync"
else
  fail "handle_set_visibility missing cloud sync"
fi

# ═══════════════════════════════════════════════════════════════════
# PERSISTENCE
# ═══════════════════════════════════════════════════════════════════

# ── 15. _fan_visibility field ────────────────────────────────────
log "Step 15: _fan_visibility field exists"
if grep -q '_fan_visibility' "$PIT_DASH"; then
  pass "_fan_visibility field exists"
else
  fail "_fan_visibility field missing"
fi

# ── 16. _load_fan_visibility method ──────────────────────────────
log "Step 16: _load_fan_visibility method exists"
if grep -q 'def _load_fan_visibility' "$PIT_DASH"; then
  pass "_load_fan_visibility method exists"
else
  fail "_load_fan_visibility method missing"
fi

# ── 17. _save_fan_visibility method ──────────────────────────────
log "Step 17: _save_fan_visibility method exists"
if grep -q 'def _save_fan_visibility' "$PIT_DASH"; then
  pass "_save_fan_visibility method exists"
else
  fail "_save_fan_visibility method missing"
fi

# ── 18. fan_visibility.json path ─────────────────────────────────
log "Step 18: fan_visibility.json path defined"
if grep -q 'fan_visibility.json' "$PIT_DASH"; then
  pass "fan_visibility.json path defined"
else
  fail "fan_visibility.json path missing"
fi

# ═══════════════════════════════════════════════════════════════════
# CLOUD SYNC
# ═══════════════════════════════════════════════════════════════════

# ── 19. Cloud sync POSTs to cloud URL ────────────────────────────
log "Step 19: Cloud sync POSTs to cloud URL"
if grep -A 50 'def handle_set_visibility' "$PIT_DASH" | grep -q 'team/visibility\|team/login'; then
  pass "Cloud sync targets cloud visibility endpoint"
else
  fail "Cloud sync not targeting cloud endpoint"
fi

# ── 20. Sync result in response ──────────────────────────────────
log "Step 20: Sync result returned in response"
if grep -A 50 'def handle_set_visibility' "$PIT_DASH" | grep -q "'synced'"; then
  pass "Response includes synced field"
else
  fail "Response missing synced field"
fi

# ═══════════════════════════════════════════════════════════════════
# SYNTAX
# ═══════════════════════════════════════════════════════════════════

# ── 21. Python syntax compiles ───────────────────────────────────
log "Step 21: Python syntax compiles"
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
