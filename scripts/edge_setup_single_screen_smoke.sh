#!/usr/bin/env bash
# edge_setup_single_screen_smoke.sh - Smoke test for Edge Setup Single Screen
#
# Validates:
#   Setup Flow (pit_crew_dashboard.py):
#     1.  SETUP_HTML template exists
#     2.  Setup page has password fields
#     3.  Setup page has vehicle_number field
#     4.  Setup page has cloud_url field
#     5.  Setup page has truck_token field
#     6.  Setup page title says "Setup"
#     7.  handle_index redirects to /setup when not configured
#     8.  handle_setup_page redirects to /login when already configured
#     9.  No legacy setup markers (wizard step indicators, multi-page flow)
#    10.  URL validation applied on setup save (http:// auto-prefix)
#    11.  Setup form has id="setupForm"
#    12.  Setup JS validates password match
#   Routing:
#    13.  GET / route exists (handle_index)
#    14.  GET /setup route exists
#    15.  POST /setup route exists
#   Syntax:
#    16.  Python syntax compiles
#
# Usage:
#   bash scripts/edge_setup_single_screen_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[edge-setup]  $*"; }
pass() { echo "[edge-setup]    PASS: $*"; }
fail() { echo "[edge-setup]    FAIL: $*"; FAIL=1; }

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "EDGE-CLOUD-2: Edge Setup Single Screen Smoke Test"
echo ""

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# Extract SETUP_HTML template
SETUP_HTML=$(sed -n "/^SETUP_HTML = '''/,/^'''/p" "$PIT_DASH")

# ── 1. SETUP_HTML exists ──────────────────────────────────────
log "Step 1: SETUP_HTML template exists"
if [ -n "$SETUP_HTML" ]; then
  pass "SETUP_HTML template found"
else
  fail "SETUP_HTML template not found"
fi

# ── 2. Password fields ───────────────────────────────────────
log "Step 2: Setup page has password fields"
if echo "$SETUP_HTML" | grep -q 'name="password"'; then
  pass "Password field exists"
else
  fail "Missing password field"
fi

# ── 3. Vehicle number field ───────────────────────────────────
log "Step 3: Setup page has vehicle_number field"
if echo "$SETUP_HTML" | grep -q 'name="vehicle_number"'; then
  pass "vehicle_number field exists"
else
  fail "Missing vehicle_number field"
fi

# ── 4. Cloud URL field ────────────────────────────────────────
log "Step 4: Setup page has cloud_url field"
if echo "$SETUP_HTML" | grep -q 'name="cloud_url"'; then
  pass "cloud_url field exists"
else
  fail "Missing cloud_url field"
fi

# ── 5. Truck token field ─────────────────────────────────────
log "Step 5: Setup page has truck_token field"
if echo "$SETUP_HTML" | grep -q 'name="truck_token"'; then
  pass "truck_token field exists"
else
  fail "Missing truck_token field"
fi

# ── 6. Setup page title ──────────────────────────────────────
log "Step 6: Setup page title says Setup"
if echo "$SETUP_HTML" | grep -q '<title>.*Setup'; then
  pass "Setup page has correct title"
else
  fail "Setup page missing correct title"
fi

# ── 7. handle_index redirects to /setup when not configured ──
log "Step 7: handle_index redirects to /setup when not configured"
INDEX_FUNC=$(sed -n '/async def handle_index/,/^    async def /p' "$PIT_DASH")
if echo "$INDEX_FUNC" | grep -q "HTTPFound.*setup"; then
  pass "Redirects to /setup when not configured"
else
  fail "Missing redirect to /setup"
fi

# ── 8. handle_setup_page redirects when configured ───────────
log "Step 8: handle_setup_page redirects when already configured"
SETUP_PAGE_FUNC=$(sed -n '/async def handle_setup_page/,/^    async def /p' "$PIT_DASH")
if echo "$SETUP_PAGE_FUNC" | grep -q "HTTPFound.*login"; then
  pass "Redirects to /login when already configured"
else
  fail "Missing redirect when configured"
fi

# ── 9. No legacy wizard markers ──────────────────────────────
log "Step 9: No legacy setup markers"
LEGACY_OK=true
for marker in "step-indicator" "wizard-step" "step-2" "step-3" "next-step" "prev-step"; do
  if echo "$SETUP_HTML" | grep -qi "$marker"; then
    fail "Legacy marker found: $marker"
    LEGACY_OK=false
  fi
done
if $LEGACY_OK; then
  pass "No legacy wizard markers found"
fi

# ── 10. URL validation on setup save ─────────────────────────
log "Step 10: URL validation on setup save"
HANDLE_SETUP=$(sed -n '/async def handle_setup(self, request/,/^    async def /p' "$PIT_DASH")
if echo "$HANDLE_SETUP" | grep -q "startswith.*http"; then
  pass "URL validation present in setup handler"
else
  fail "Missing URL validation in setup handler"
fi

# ── 11. Setup form has id="setupForm" ────────────────────────
log "Step 11: Setup form has id=setupForm"
if echo "$SETUP_HTML" | grep -q 'id="setupForm"'; then
  pass "Form has id=setupForm"
else
  fail "Missing id=setupForm"
fi

# ── 12. Setup JS validates password match ────────────────────
log "Step 12: Setup JS validates password match"
if grep -A 20 'function validateForm' "$PIT_DASH" | grep -q 'password.*confirm\|confirm.*password'; then
  pass "Password match validation exists"
else
  fail "Missing password match validation"
fi

# ── 13-15. Routes exist ──────────────────────────────────────
log "Step 13: GET / route exists"
if grep -q "add_get.*'/'.*handle_index" "$PIT_DASH"; then
  pass "GET / route registered"
else
  fail "Missing GET / route"
fi

log "Step 14: GET /setup route exists"
if grep -q "add_get.*/setup.*handle_setup_page" "$PIT_DASH"; then
  pass "GET /setup route registered"
else
  fail "Missing GET /setup route"
fi

log "Step 15: POST /setup route exists"
if grep -q "add_post.*/setup.*handle_setup" "$PIT_DASH"; then
  pass "POST /setup route registered"
else
  fail "Missing POST /setup route"
fi

# ── 16. Python syntax ────────────────────────────────────────
log "Step 16: Python syntax compiles"
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
