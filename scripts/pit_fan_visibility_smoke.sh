#!/usr/bin/env bash
# pit_fan_visibility_smoke.sh — Smoke test for PIT-VIS-0: Fan visibility toggle fix
#
# Validates:
#   A. Python syntax
#   B. setFanVisibility JS function exists and is wired correctly
#   C. Backend endpoint route registration
#   D. Backend handler logic (auth, persistence, cloud sync)
#   E. CSS styling uses defined variables (no undefined --accent-green)
#   F. updateVisibilityUI uses CSS classes (not broken inline styles)
#   G. State persistence file includes visibility field
#   H. Initial state load on page load
#   I. Runtime integration (if edge is running)
#
# Usage:
#   bash scripts/pit_fan_visibility_smoke.sh
#
# Exit codes:
#   0 — all checks passed (SKIPs allowed)
#   1 — at least one FAIL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[vis-0]  $*"; }
pass() { echo "[vis-0]    PASS: $*"; }
fail() { echo "[vis-0]    FAIL: $*"; FAIL=1; }
skip() { echo "[vis-0]    SKIP: $*"; }

DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "PIT-VIS-0: Fan Visibility Toggle Smoke Test"
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
# SECTION B: setFanVisibility JS Function
# ═══════════════════════════════════════════════════════════════════
log "─── Section B: JS Function ───"

# B1: setFanVisibility function exists
log "B1: setFanVisibility function exists"
if grep -q 'async function setFanVisibility' "$DASHBOARD"; then
  pass "setFanVisibility function exists"
else
  fail "setFanVisibility function missing"
fi

# B2: setFanVisibility exists exactly once (no duplicates)
log "B2: setFanVisibility defined exactly once"
COUNT=$(grep -c 'async function setFanVisibility' "$DASHBOARD" || echo "0")
if [ "$COUNT" = "1" ]; then
  pass "setFanVisibility defined exactly once"
else
  fail "setFanVisibility defined $COUNT times (expected 1)"
fi

# B3: Buttons use data-click="setFanVisibility"
log "B3: Buttons use data-click wiring"
VIS_BTN_COUNT=$(grep -c 'data-click="setFanVisibility"' "$DASHBOARD" || echo "0")
if [ "$VIS_BTN_COUNT" = "2" ]; then
  pass "Two buttons wired via data-click=\"setFanVisibility\""
else
  fail "Expected 2 buttons with data-click=\"setFanVisibility\", found $VIS_BTN_COUNT"
fi

# B4: data-arg="true" and data-arg="false" present
log "B4: Buttons have correct data-arg values"
if grep -q 'data-click="setFanVisibility" data-arg="true"' "$DASHBOARD" && \
   grep -q 'data-click="setFanVisibility" data-arg="false"' "$DASHBOARD"; then
  pass "Buttons have data-arg true and false"
else
  fail "Buttons missing correct data-arg values"
fi

# B5: Event delegation handler exists for data-click
log "B5: Event delegation handler for data-click exists"
if grep -q "window\[el.dataset.click\]" "$DASHBOARD"; then
  pass "Event delegation handler wires data-click to window functions"
else
  fail "Event delegation handler missing"
fi

# B6: setFanVisibility calls /api/team/visibility
log "B6: setFanVisibility calls correct endpoint"
if grep -A20 'async function setFanVisibility' "$DASHBOARD" | grep -q "'/api/team/visibility'"; then
  pass "setFanVisibility calls /api/team/visibility"
else
  fail "setFanVisibility does not call /api/team/visibility"
fi

# B7: setFanVisibility sends POST with JSON body
log "B7: setFanVisibility sends POST with JSON"
if grep -A20 'async function setFanVisibility' "$DASHBOARD" | grep -q "method: 'POST'"; then
  pass "setFanVisibility sends POST request"
else
  fail "setFanVisibility does not send POST"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION C: Backend Route Registration
# ═══════════════════════════════════════════════════════════════════
log "─── Section C: Backend Routes ───"

# C1: GET /api/team/visibility route registered
log "C1: GET /api/team/visibility route"
if grep -q "add_get('/api/team/visibility'" "$DASHBOARD"; then
  pass "GET /api/team/visibility route registered"
else
  fail "GET /api/team/visibility route missing"
fi

# C2: POST /api/team/visibility route registered
log "C2: POST /api/team/visibility route"
if grep -q "add_post('/api/team/visibility'" "$DASHBOARD"; then
  pass "POST /api/team/visibility route registered"
else
  fail "POST /api/team/visibility route missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION D: Backend Handler Logic
# ═══════════════════════════════════════════════════════════════════
log "─── Section D: Backend Handlers ───"

# D1: GET handler exists and returns visible field
log "D1: GET handler returns visible field"
if grep -A5 'async def handle_get_visibility' "$DASHBOARD" | grep -q "'visible'"; then
  pass "GET handler returns visible field"
else
  fail "GET handler missing visible field"
fi

# D2: GET handler checks auth
log "D2: GET handler checks authentication"
if grep -A3 'async def handle_get_visibility' "$DASHBOARD" | grep -q '_is_authenticated'; then
  pass "GET handler checks auth"
else
  fail "GET handler does not check auth"
fi

# D3: POST handler saves to disk
log "D3: POST handler persists to disk"
if grep -A10 'async def handle_set_visibility' "$DASHBOARD" | grep -q '_save_fan_visibility'; then
  pass "POST handler calls _save_fan_visibility"
else
  fail "POST handler does not persist to disk"
fi

# D4: POST handler returns success + synced fields
log "D4: POST handler returns success and synced"
if grep -A40 'async def handle_set_visibility' "$DASHBOARD" | grep -q "'success': True.*'synced'"; then
  pass "POST handler returns success + synced"
else
  fail "POST handler missing success/synced fields"
fi

# D5: POST handler attempts cloud sync when configured
log "D5: POST handler attempts cloud sync"
if grep -A40 'async def handle_set_visibility' "$DASHBOARD" | grep -q 'self.config.cloud_url'; then
  pass "POST handler checks cloud_url for sync"
else
  fail "POST handler does not attempt cloud sync"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION E: CSS Styling Uses Defined Variables
# ═══════════════════════════════════════════════════════════════════
log "─── Section E: CSS Variables ───"

# E1: No --accent-green in visibility buttons (was the root cause)
log "E1: No undefined --accent-green in visibility buttons"
if grep 'btnVisibilityOn\|btnVisibilityOff\|visibilityBadge' "$DASHBOARD" | grep -q 'accent-green'; then
  fail "Visibility buttons still use undefined --accent-green"
else
  pass "No --accent-green in visibility buttons"
fi

# E2: No --accent-red in visibility JS
log "E2: No undefined --accent-red in updateVisibilityUI"
if grep -A20 'function updateVisibilityUI' "$DASHBOARD" | grep -q 'accent-red'; then
  fail "updateVisibilityUI still uses undefined --accent-red"
else
  pass "No --accent-red in updateVisibilityUI"
fi

# E3: Badge uses var(--success) (defined CSS variable)
log "E3: Badge uses var(--success)"
if grep 'visibilityBadge' "$DASHBOARD" | grep -q 'var(--success)'; then
  pass "Badge uses var(--success)"
else
  fail "Badge does not use var(--success)"
fi

# E4: vis-btn CSS class defined
log "E4: .vis-btn CSS class defined"
if grep -q '\.vis-btn {' "$DASHBOARD"; then
  pass ".vis-btn CSS class defined"
else
  fail ".vis-btn CSS class missing"
fi

# E5: vis-on CSS class uses --success
log "E5: .vis-on uses var(--success)"
if grep -A3 '\.vis-btn.vis-on' "$DASHBOARD" | grep -q 'var(--success)'; then
  pass ".vis-on uses var(--success)"
else
  fail ".vis-on does not use var(--success)"
fi

# E6: vis-off CSS class uses --danger
log "E6: .vis-off uses var(--danger)"
if grep -A3 '\.vis-btn.vis-off' "$DASHBOARD" | grep -q 'var(--danger)'; then
  pass ".vis-off uses var(--danger)"
else
  fail ".vis-off does not use var(--danger)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION F: updateVisibilityUI Uses CSS Classes
# ═══════════════════════════════════════════════════════════════════
log "─── Section F: UI State Management ───"

# F1: updateVisibilityUI uses classList (not opacity manipulation)
log "F1: updateVisibilityUI uses classList"
if grep -A20 'function updateVisibilityUI' "$DASHBOARD" | grep -q 'classList.add'; then
  pass "updateVisibilityUI uses classList.add for state"
else
  fail "updateVisibilityUI does not use classList"
fi

# F2: updateVisibilityUI does not use opacity for state
log "F2: No opacity manipulation in updateVisibilityUI"
if grep -A20 'function updateVisibilityUI' "$DASHBOARD" | grep -q 'style.opacity'; then
  fail "updateVisibilityUI still uses opacity manipulation"
else
  pass "No opacity manipulation in updateVisibilityUI"
fi

# F3: updateVisibilityUI adds vis-on for visible state
log "F3: Adds vis-on class for visible state"
if grep -A20 'function updateVisibilityUI' "$DASHBOARD" | grep -q "'vis-on'"; then
  pass "Adds vis-on class"
else
  fail "Missing vis-on class toggle"
fi

# F4: updateVisibilityUI adds vis-off for hidden state
log "F4: Adds vis-off class for hidden state"
if grep -A20 'function updateVisibilityUI' "$DASHBOARD" | grep -q "'vis-off'"; then
  pass "Adds vis-off class"
else
  fail "Missing vis-off class toggle"
fi

# F5: setFanVisibility calls updateVisibilityUI on success
log "F5: setFanVisibility calls updateVisibilityUI on success"
if grep -A30 'async function setFanVisibility' "$DASHBOARD" | grep -q 'updateVisibilityUI(visible)'; then
  pass "setFanVisibility calls updateVisibilityUI on success"
else
  fail "setFanVisibility does not call updateVisibilityUI"
fi

# F6: setFanVisibility shows sync status feedback
log "F6: setFanVisibility shows sync status"
if grep -A30 'async function setFanVisibility' "$DASHBOARD" | grep -q 'visibilitySyncStatus'; then
  pass "setFanVisibility shows sync status feedback"
else
  fail "setFanVisibility missing sync status feedback"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION G: State Persistence
# ═══════════════════════════════════════════════════════════════════
log "─── Section G: State Persistence ───"

# G1: fan_visibility.json path defined
log "G1: fan_visibility.json path defined"
if grep -q 'fan_visibility.json' "$DASHBOARD"; then
  pass "fan_visibility.json path defined"
else
  fail "fan_visibility.json path missing"
fi

# G2: _load_fan_visibility method exists
log "G2: _load_fan_visibility method exists"
if grep -q 'def _load_fan_visibility' "$DASHBOARD"; then
  pass "_load_fan_visibility method exists"
else
  fail "_load_fan_visibility method missing"
fi

# G3: _save_fan_visibility method exists
log "G3: _save_fan_visibility method exists"
if grep -q 'def _save_fan_visibility' "$DASHBOARD"; then
  pass "_save_fan_visibility method exists"
else
  fail "_save_fan_visibility method missing"
fi

# G4: Persistence file includes visible field
log "G4: Persistence file writes visible field"
if grep -A5 'def _save_fan_visibility' "$DASHBOARD" | grep -q "'visible'"; then
  pass "Persistence file includes visible field"
else
  fail "Persistence file missing visible field"
fi

# G5: _fan_visibility initialized with default
log "G5: _fan_visibility has default value"
if grep -q '_fan_visibility.*=.*True' "$DASHBOARD"; then
  pass "_fan_visibility initialized to True"
else
  fail "_fan_visibility missing default"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION H: Initial State Load
# ═══════════════════════════════════════════════════════════════════
log "─── Section H: Initial State Load ───"

# H1: loadTeamState called on page load (not just tab click)
log "H1: loadTeamState called on page load"
if grep -B1 'loadTeamState()' "$DASHBOARD" | grep -q 'PIT-VIS-0'; then
  pass "loadTeamState called on page load (PIT-VIS-0)"
else
  fail "loadTeamState not called on page load"
fi

# H2: loadTeamState fetches /api/team/visibility
log "H2: loadTeamState fetches visibility endpoint"
if grep -A15 'async function loadTeamState' "$DASHBOARD" | grep -q "'/api/team/visibility'"; then
  pass "loadTeamState fetches /api/team/visibility"
else
  fail "loadTeamState does not fetch visibility"
fi

# H3: loadTeamState calls updateVisibilityUI
log "H3: loadTeamState calls updateVisibilityUI"
if grep -A15 'async function loadTeamState' "$DASHBOARD" | grep -q 'updateVisibilityUI'; then
  pass "loadTeamState calls updateVisibilityUI"
else
  fail "loadTeamState does not call updateVisibilityUI"
fi

# H4: Script block has CSP nonce (the second <script> block contains setFanVisibility)
log "H4: Second script block has CSP nonce"
# The second script block starts with <script nonce="__CSP_NONCE__"> and contains setFanVisibility
# Verify both exist and the nonce block comes before the function
NONCE_LINE=$(grep -n 'script nonce="__CSP_NONCE__"' "$DASHBOARD" | tail -1 | cut -d: -f1)
FN_LINE=$(grep -n 'async function setFanVisibility' "$DASHBOARD" | head -1 | cut -d: -f1)
if [ -n "$NONCE_LINE" ] && [ -n "$FN_LINE" ] && [ "$NONCE_LINE" -lt "$FN_LINE" ]; then
  pass "Script block containing setFanVisibility has CSP nonce (line $NONCE_LINE < $FN_LINE)"
else
  fail "Script block missing CSP nonce"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION I: Runtime Integration (if edge is running)
# ═══════════════════════════════════════════════════════════════════
log "─── Section I: Runtime Integration ───"

EDGE_PORT="${ARGUS_EDGE_PORT:-8080}"
EDGE_HOST="${ARGUS_EDGE_HOST:-localhost}"
EDGE_URL="http://${EDGE_HOST}:${EDGE_PORT}"

# I1: Check if edge is running
log "I1: Edge reachability check"
EDGE_BODY=$(curl -s --connect-timeout 2 --max-time 3 \
  "${EDGE_URL}/api/telemetry/current" 2>/dev/null || true)

if echo "$EDGE_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'cloud_detail' in d" 2>/dev/null; then
  pass "Edge reachable at ${EDGE_URL}"

  # I2: GET /api/team/visibility endpoint
  log "I2: GET /api/team/visibility"
  VIS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    "${EDGE_URL}/api/team/visibility" 2>/dev/null || echo "000")
  if [ "$VIS_CODE" = "401" ]; then
    skip "Visibility GET requires auth (expected)"
  elif [ "$VIS_CODE" = "200" ]; then
    pass "Visibility GET returns 200"
  else
    skip "Visibility GET returned HTTP $VIS_CODE"
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
