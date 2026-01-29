#!/usr/bin/env bash
# edge_cloud_heartbeat_smoke.sh - Smoke test for Edge→Cloud Heartbeat Pipeline
#
# Validates:
#   Cloud (telemetry.py):
#     1.  POST /telemetry/heartbeat endpoint exists
#     2.  Heartbeat does NOT require in_progress event status
#     3.  Heartbeat response includes event_status field
#     4.  Heartbeat updates last_seen in Redis
#     5.  Heartbeat publishes presence to SSE
#     6.  Heartbeat returns vehicle_id, event_id, server_ts_ms
#   Cloud (production.py):
#     7.  POST /edge/heartbeat endpoint exists
#     8.  Edge heartbeat validates X-Truck-Token
#     9.  Edge heartbeat stores status in Redis with TTL
#    10.  Edge heartbeat updates last_seen timestamp
#   Edge (pit_crew_dashboard.py):
#    11.  cloud_detail field in TelemetryState
#    12.  cloud_detail included in to_dict output
#    13.  _cloud_status_loop sets cloud_detail
#    14.  _send_cloud_heartbeat returns cloud_detail string
#    15.  Heartbeat sent regardless of event_id (not gated)
#    16.  Banner shows "not configured" state
#    17.  Banner shows "event not live" state
#    18.  Banner shows "auth rejected" state
#    19.  Banner shows "connection lost" state
#    20.  URL validation: adds http:// if no scheme
#    21.  URL validation: strips trailing slash
#    22.  URL validation applied in setup handler
#    23.  URL validation applied in settings handler
#   Syntax:
#    24.  Python syntax compiles
#   Live (optional):
#    25.  POST /telemetry/heartbeat returns 200 or 400
#    26.  Response includes event_status field
#
# Usage:
#   bash scripts/edge_cloud_heartbeat_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[edge-cloud-hb]  $*"; }
pass() { echo "[edge-cloud-hb]    PASS: $*"; }
fail() { echo "[edge-cloud-hb]    FAIL: $*"; FAIL=1; }
skip() { echo "[edge-cloud-hb]    SKIP: $*"; }

TELEM_PY="$REPO_ROOT/cloud/app/routes/telemetry.py"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "EDGE-CLOUD-HB: Edge→Cloud Heartbeat Pipeline Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# CLOUD - telemetry.py (simple heartbeat)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$TELEM_PY" ]; then
  fail "telemetry.py not found"
  exit 1
fi

# ── 1. POST /telemetry/heartbeat endpoint exists ────────────────
log "Step 1: POST /telemetry/heartbeat endpoint exists"
if grep -q 'post.*telemetry/heartbeat' "$TELEM_PY"; then
  pass "Heartbeat endpoint exists"
else
  fail "Heartbeat endpoint not found"
fi

# ── 2. Heartbeat does NOT use validate_truck_token dependency ───
log "Step 2: Heartbeat does NOT require in_progress event status"
# The heartbeat function should do its own token validation that
# accepts any event status (not just in_progress)
HB_FUNC=$(sed -n '/^@router.post.*telemetry\/heartbeat/,/^@router\.\|^async def [a-z]/p' "$TELEM_PY")
if echo "$HB_FUNC" | grep -q 'Event.status.*in_progress'; then
  fail "Heartbeat still requires in_progress event status"
else
  pass "Heartbeat accepts any event status"
fi

# ── 3. Heartbeat response includes event_status ─────────────────
log "Step 3: Heartbeat response includes event_status field"
if echo "$HB_FUNC" | grep -q '"event_status"'; then
  pass "Response includes event_status"
else
  fail "Response missing event_status"
fi

# ── 4. Heartbeat updates last_seen in Redis ─────────────────────
log "Step 4: Heartbeat updates last_seen in Redis"
if echo "$HB_FUNC" | grep -q 'set_vehicle_last_seen'; then
  pass "Updates last_seen via Redis"
else
  fail "Missing set_vehicle_last_seen call"
fi

# ── 5. Heartbeat publishes presence to SSE ──────────────────────
log "Step 5: Heartbeat publishes presence to SSE"
if echo "$HB_FUNC" | grep -q 'publish_event.*presence'; then
  pass "Publishes presence event"
else
  fail "Missing presence publish"
fi

# ── 6. Response includes vehicle_id, event_id, server_ts_ms ────
log "Step 6: Heartbeat returns vehicle_id, event_id, server_ts_ms"
MISSING=""
for field in vehicle_id event_id server_ts_ms; do
  if ! echo "$HB_FUNC" | grep -q "\"$field\""; then
    MISSING="$MISSING $field"
  fi
done
if [ -z "$MISSING" ]; then
  pass "Response includes all required fields"
else
  fail "Response missing:$MISSING"
fi

# ═══════════════════════════════════════════════════════════════════
# CLOUD - production.py (detailed heartbeat)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$PROD_PY" ]; then
  fail "production.py not found"
  exit 1
fi

# ── 7. POST /edge/heartbeat endpoint exists ─────────────────────
log "Step 7: POST /edge/heartbeat endpoint exists"
if grep -q 'post.*edge/heartbeat' "$PROD_PY"; then
  pass "Detailed edge heartbeat endpoint exists"
else
  fail "Detailed edge heartbeat endpoint not found"
fi

# ── 8. Edge heartbeat validates X-Truck-Token ───────────────────
log "Step 8: Edge heartbeat validates X-Truck-Token"
if grep -q 'X-Truck-Token' "$PROD_PY"; then
  pass "Validates X-Truck-Token"
else
  fail "Missing X-Truck-Token validation"
fi

# ── 9. Edge heartbeat stores status in Redis with TTL ───────────
log "Step 9: Edge heartbeat stores status in Redis"
if grep -q 'set_edge_status' "$PROD_PY"; then
  pass "Stores edge status in Redis"
else
  fail "Missing set_edge_status call"
fi

# ── 10. Edge heartbeat updates last_seen ────────────────────────
log "Step 10: Edge heartbeat updates last_seen timestamp"
EDGE_HB_FUNC=$(sed -n '/async def edge_heartbeat/,/^@router\.\|^async def [a-z]/p' "$PROD_PY")
if echo "$EDGE_HB_FUNC" | grep -q 'set_vehicle_last_seen'; then
  pass "Updates last_seen from edge heartbeat"
else
  fail "Missing set_vehicle_last_seen in edge heartbeat"
fi

# ═══════════════════════════════════════════════════════════════════
# EDGE (pit_crew_dashboard.py)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ── 11. cloud_detail field in TelemetryState ────────────────────
log "Step 11: cloud_detail field in TelemetryState"
if grep -q 'cloud_detail.*str.*=' "$PIT_DASH"; then
  pass "cloud_detail field exists"
else
  fail "cloud_detail field missing"
fi

# ── 12. cloud_detail included in to_dict output ────────────────
log "Step 12: cloud_detail included in to_dict output"
if grep -q '"cloud_detail".*self.cloud_detail' "$PIT_DASH"; then
  pass "cloud_detail in to_dict"
else
  fail "cloud_detail missing from to_dict"
fi

# ── 13. _cloud_status_loop sets cloud_detail ───────────────────
log "Step 13: _cloud_status_loop sets cloud_detail"
CLOUD_LOOP=$(sed -n '/_cloud_status_loop/,/^    async def \|^    def [a-z]/p' "$PIT_DASH")
if echo "$CLOUD_LOOP" | grep -q 'cloud_detail'; then
  pass "_cloud_status_loop references cloud_detail"
else
  fail "_cloud_status_loop does not set cloud_detail"
fi

# ── 14. _send_cloud_heartbeat returns cloud_detail ─────────────
log "Step 14: _send_cloud_heartbeat returns cloud_detail string"
HB_SEND=$(sed -n '/_send_cloud_heartbeat/,/^    async def \|^    def [a-z]/p' "$PIT_DASH")
if echo "$HB_SEND" | grep -q 'return.*cloud_detail\|return "healthy"\|return "event_not_live"\|return "auth_rejected"'; then
  pass "_send_cloud_heartbeat returns cloud_detail"
else
  fail "_send_cloud_heartbeat does not return cloud_detail"
fi

# ── 15. Heartbeat sent regardless of event_id ──────────────────
log "Step 15: Heartbeat not gated on event_id"
# The heartbeat call should be OUTSIDE the 'if self.config.event_id:' block
# Check that _send_cloud_heartbeat is called before/outside event_id check
if echo "$CLOUD_LOOP" | grep -q '_send_cloud_heartbeat'; then
  # Verify it's not inside the event_id-gated section
  # The heartbeat should appear before the event_id production status block
  HB_LINE=$(echo "$CLOUD_LOOP" | grep -n '_send_cloud_heartbeat' | head -1 | cut -d: -f1)
  EVENT_LINE=$(echo "$CLOUD_LOOP" | grep -n 'if self.config.event_id:' | head -1 | cut -d: -f1)
  if [ -n "$HB_LINE" ] && [ -n "$EVENT_LINE" ] && [ "$HB_LINE" -lt "$EVENT_LINE" ]; then
    pass "Heartbeat called before event_id gate"
  else
    fail "Heartbeat may still be gated on event_id"
  fi
else
  fail "No _send_cloud_heartbeat call in _cloud_status_loop"
fi

# ── 16. Banner shows "not configured" state ────────────────────
log "Step 16: Banner shows 'not configured' state"
if grep -q 'not_configured' "$PIT_DASH"; then
  pass "Banner handles not_configured state"
else
  fail "Banner missing not_configured state"
fi

# ── 17. Banner shows "event not live" state ────────────────────
log "Step 17: Banner shows 'event not live' state"
if grep -q 'event_not_live' "$PIT_DASH"; then
  pass "Banner handles event_not_live state"
else
  fail "Banner missing event_not_live state"
fi

# ── 18. Banner shows "auth rejected" state ─────────────────────
log "Step 18: Banner shows 'auth rejected' state"
if grep -q 'auth_rejected' "$PIT_DASH"; then
  pass "Banner handles auth_rejected state"
else
  fail "Banner missing auth_rejected state"
fi

# ── 19. Banner shows "connection lost" state ───────────────────
log "Step 19: Banner shows 'connection lost' state"
if grep -q 'connection lost' "$PIT_DASH"; then
  pass "Banner shows connection lost fallback"
else
  fail "Banner missing connection lost fallback"
fi

# ── 20. URL validation: adds http:// if no scheme ──────────────
log "Step 20: URL validation adds http:// if no scheme"
if grep -q "startswith.*http://" "$PIT_DASH"; then
  pass "URL validation checks for http:// scheme"
else
  fail "Missing URL scheme validation"
fi

# ── 21. URL validation: strips trailing slash ──────────────────
log "Step 21: URL validation strips trailing slash"
if grep -q "rstrip.*/" "$PIT_DASH"; then
  pass "URL validation strips trailing slash"
else
  fail "Missing trailing slash strip"
fi

# ── 22. URL validation applied in setup handler ────────────────
log "Step 22: URL validation in setup handler"
SETUP_FUNC=$(sed -n '/async def handle_setup(self, request/,/^    async def /p' "$PIT_DASH")
if echo "$SETUP_FUNC" | grep -q 'startswith.*http'; then
  pass "Setup handler has URL validation"
else
  fail "Setup handler missing URL validation"
fi

# ── 23. URL validation applied in settings handler ─────────────
log "Step 23: URL validation in settings handler"
SETTINGS_FUNC=$(sed -n '/async def handle_settings(self, request/,/^    async def /p' "$PIT_DASH")
if echo "$SETTINGS_FUNC" | grep -q 'startswith.*http'; then
  pass "Settings handler has URL validation"
else
  fail "Settings handler missing URL validation"
fi

# ═══════════════════════════════════════════════════════════════════
# SYNTAX
# ═══════════════════════════════════════════════════════════════════

# ── 24. Python syntax compiles ─────────────────────────────────
log "Step 24: Python syntax compiles"
SYNTAX_OK=true
for pyfile in "$TELEM_PY" "$PROD_PY" "$PIT_DASH"; do
  if ! python3 -c "import ast; ast.parse(open('$pyfile').read())" 2>/dev/null; then
    fail "Syntax error in $(basename "$pyfile")"
    SYNTAX_OK=false
  fi
done
if $SYNTAX_OK; then
  pass "All Python files compile"
fi

# ═══════════════════════════════════════════════════════════════════
# LIVE TESTS (optional — require running cloud)
# ═══════════════════════════════════════════════════════════════════

BASE_URL="${ARGUS_CLOUD_BASE_URL:-}"
TRUCK_TOKEN="${ARGUS_TEST_TRUCK_TOKEN:-}"

if [ -n "$BASE_URL" ] && [ -n "$TRUCK_TOKEN" ]; then
  # ── 25. POST /telemetry/heartbeat returns 200 or 400 ─────────
  log "Step 25: POST /telemetry/heartbeat returns 200 or 400"
  HTTP_CODE=$(curl -s -o /tmp/hb_resp.json -w '%{http_code}' \
    -X POST "$BASE_URL/api/v1/telemetry/heartbeat" \
    -H "X-Truck-Token: $TRUCK_TOKEN")
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "400" ]; then
    pass "Heartbeat returned HTTP $HTTP_CODE"
  else
    fail "Heartbeat returned unexpected HTTP $HTTP_CODE"
  fi

  # ── 26. Response includes event_status field ─────────────────
  log "Step 26: Response includes event_status field"
  if [ "$HTTP_CODE" = "200" ]; then
    if grep -q '"event_status"' /tmp/hb_resp.json 2>/dev/null; then
      pass "Response includes event_status"
    else
      fail "Response missing event_status"
    fi
  else
    skip "Skipped (heartbeat returned $HTTP_CODE)"
  fi
else
  skip "Steps 25-26: Set ARGUS_CLOUD_BASE_URL and ARGUS_TEST_TRUCK_TOKEN for live tests"
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
