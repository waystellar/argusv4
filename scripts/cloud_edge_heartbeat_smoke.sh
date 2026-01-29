#!/usr/bin/env bash
# cloud_edge_heartbeat_smoke.sh - Smoke test for Edge→Cloud heartbeat contract
#
# CLOUD-MANAGE-0: Validates the heartbeat contract between edge and cloud:
#   - Simple heartbeat sends edge_url + capabilities
#   - Cloud stores edge_url in vehicle-scoped presence
#   - Detailed heartbeat sends full status payload
#   - Cloud stores detailed status in event-scoped Redis key
#
# Validates:
#   Simple Heartbeat (Edge→Cloud):
#     1.  Edge sends JSON body in simple heartbeat (not empty)
#     2.  Simple heartbeat body includes edge_url
#     3.  Simple heartbeat body includes capabilities list
#     4.  Simple heartbeat built from _detect_lan_ip
#   Cloud Simple Heartbeat Endpoint:
#     5.  POST /telemetry/heartbeat endpoint exists
#     6.  Endpoint accepts X-Truck-Token header
#     7.  Endpoint parses optional JSON body
#     8.  Endpoint calls set_edge_presence on valid body
#     9.  Endpoint returns event_id in response
#    10.  Endpoint returns event_status in response
#   Cloud Edge Presence Storage:
#    11.  set_edge_presence function exists in redis_client
#    12.  get_edge_presence function exists in redis_client
#    13.  Presence key uses vehicle_id (not event_id)
#    14.  Presence TTL is >= 30 seconds
#   Detailed Heartbeat (Edge→Cloud):
#    15.  Detailed heartbeat includes edge_url in payload
#    16.  Detailed heartbeat includes streaming_status
#    17.  Detailed heartbeat includes cameras list
#    18.  Cloud stores edge_url via set_edge_status
#   Team Diagnostics Integration:
#    19.  get_diagnostics reads edge_presence (vehicle-scoped)
#    20.  get_diagnostics returns edge_url field
#   Heartbeat Infrastructure:
#    21.  Heartbeat stores heartbeat_ts
#    22.  Heartbeat calls set_vehicle_last_seen
#    23.  Redis edge status has TTL
#   Syntax:
#    24.  Python syntax compiles (telemetry.py)
#    25.  Python syntax compiles (team.py)
#    26.  Python syntax compiles (redis_client.py)
#    27.  Python syntax compiles (pit_crew_dashboard.py)
#
# Usage:
#   bash scripts/cloud_edge_heartbeat_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[heartbeat]  $*"; }
pass() { echo "[heartbeat]    PASS: $*"; }
fail() { echo "[heartbeat]    FAIL: $*"; FAIL=1; }

TELEMETRY_PY="$REPO_ROOT/cloud/app/routes/telemetry.py"
TEAM_PY="$REPO_ROOT/cloud/app/routes/team.py"
REDIS_PY="$REPO_ROOT/cloud/app/redis_client.py"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "CLOUD-MANAGE-0: Edge→Cloud Heartbeat Contract Smoke Test"
echo ""

for f in "$TELEMETRY_PY" "$TEAM_PY" "$REDIS_PY" "$PROD_PY" "$PIT_DASH"; do
  if [ ! -f "$f" ]; then
    fail "$(basename "$f") not found"
    exit 1
  fi
done

# ═══════════════════════════════════════════════════════════════════
# SIMPLE HEARTBEAT (EDGE→CLOUD)
# ═══════════════════════════════════════════════════════════════════

# ── 1. Edge sends JSON body in simple heartbeat ────────────────────
log "Step 1: Edge sends JSON body in simple heartbeat"
if grep -A 10 'telemetry/heartbeat' "$PIT_DASH" | grep -q 'json='; then
  pass "Simple heartbeat sends JSON body"
else
  fail "Simple heartbeat missing JSON body"
fi

# ── 2. Simple heartbeat body includes edge_url ─────────────────────
log "Step 2: Simple heartbeat body includes edge_url"
if grep -A 5 'simple_payload' "$PIT_DASH" | grep -q 'edge_url'; then
  pass "Simple heartbeat includes edge_url"
else
  fail "Simple heartbeat missing edge_url"
fi

# ── 3. Simple heartbeat body includes capabilities ─────────────────
log "Step 3: Simple heartbeat body includes capabilities"
if grep -A 5 'simple_payload' "$PIT_DASH" | grep -q 'capabilities'; then
  pass "Simple heartbeat includes capabilities"
else
  fail "Simple heartbeat missing capabilities"
fi

# ── 4. Simple heartbeat uses _detect_lan_ip ────────────────────────
log "Step 4: Simple heartbeat built from _detect_lan_ip"
if grep -B 20 'simple_payload' "$PIT_DASH" | grep -q '_detect_lan_ip'; then
  pass "Simple heartbeat uses _detect_lan_ip for edge_url"
else
  fail "Simple heartbeat not using _detect_lan_ip"
fi

# ═══════════════════════════════════════════════════════════════════
# CLOUD SIMPLE HEARTBEAT ENDPOINT
# ═══════════════════════════════════════════════════════════════════

# ── 5. POST /telemetry/heartbeat endpoint exists ───────────────────
log "Step 5: POST /telemetry/heartbeat endpoint exists"
if grep -q 'post.*"/telemetry/heartbeat"' "$TELEMETRY_PY"; then
  pass "POST /telemetry/heartbeat endpoint exists"
else
  fail "POST /telemetry/heartbeat endpoint missing"
fi

# ── 6. Endpoint accepts X-Truck-Token ──────────────────────────────
log "Step 6: Endpoint accepts X-Truck-Token header"
if grep -A 10 'telemetry_heartbeat' "$TELEMETRY_PY" | grep -q 'X-Truck-Token'; then
  pass "Endpoint accepts X-Truck-Token"
else
  fail "Endpoint missing X-Truck-Token"
fi

# ── 7. Endpoint parses optional JSON body ──────────────────────────
log "Step 7: Endpoint parses optional JSON body"
if grep -q 'request.json()' "$TELEMETRY_PY"; then
  pass "Endpoint parses JSON body"
else
  fail "Endpoint does not parse JSON body"
fi

# ── 8. Endpoint calls set_edge_presence ────────────────────────────
log "Step 8: Endpoint calls set_edge_presence on valid body"
if grep -q 'set_edge_presence' "$TELEMETRY_PY"; then
  pass "Endpoint calls set_edge_presence"
else
  fail "Endpoint missing set_edge_presence call"
fi

# ── 9. Endpoint returns event_id ───────────────────────────────────
log "Step 9: Endpoint returns event_id in response"
if grep -q '"event_id"' "$TELEMETRY_PY"; then
  pass "Response includes event_id"
else
  fail "Response missing event_id"
fi

# ── 10. Endpoint returns event_status ──────────────────────────────
log "Step 10: Endpoint returns event_status in response"
if grep -q '"event_status"' "$TELEMETRY_PY"; then
  pass "Response includes event_status"
else
  fail "Response missing event_status"
fi

# ═══════════════════════════════════════════════════════════════════
# CLOUD EDGE PRESENCE STORAGE
# ═══════════════════════════════════════════════════════════════════

# ── 11. set_edge_presence function exists ──────────────────────────
log "Step 11: set_edge_presence function exists in redis_client"
if grep -q 'async def set_edge_presence' "$REDIS_PY"; then
  pass "set_edge_presence function exists"
else
  fail "set_edge_presence function missing"
fi

# ── 12. get_edge_presence function exists ──────────────────────────
log "Step 12: get_edge_presence function exists in redis_client"
if grep -q 'async def get_edge_presence' "$REDIS_PY"; then
  pass "get_edge_presence function exists"
else
  fail "get_edge_presence function missing"
fi

# ── 13. Presence key uses vehicle_id ───────────────────────────────
log "Step 13: Presence key uses vehicle_id (not event_id)"
if grep -q 'edge_presence:{vehicle_id}' "$REDIS_PY"; then
  pass "Presence key is vehicle-scoped"
else
  fail "Presence key not vehicle-scoped"
fi

# ── 14. Presence TTL >= 30s ────────────────────────────────────────
log "Step 14: Presence TTL is >= 30 seconds"
TTL=$(grep -A 10 'def set_edge_presence' "$REDIS_PY" | grep -oE 'ex=[0-9]+' | grep -oE '[0-9]+')
if [ -n "$TTL" ] && [ "$TTL" -ge 30 ]; then
  pass "Presence TTL is ${TTL}s"
else
  fail "Presence TTL too short: ${TTL:-unknown}s"
fi

# ═══════════════════════════════════════════════════════════════════
# DETAILED HEARTBEAT (EDGE→CLOUD)
# ═══════════════════════════════════════════════════════════════════

# ── 15. Detailed heartbeat includes edge_url ───────────────────────
log "Step 15: Detailed heartbeat includes edge_url in payload"
if grep -A 30 'Build detailed payload' "$PIT_DASH" | grep -q '"edge_url"'; then
  pass "Detailed heartbeat includes edge_url"
else
  fail "Detailed heartbeat missing edge_url"
fi

# ── 16. Detailed heartbeat includes streaming_status ───────────────
log "Step 16: Detailed heartbeat includes streaming_status"
if grep -A 30 'Build detailed payload' "$PIT_DASH" | grep -q '"streaming_status"'; then
  pass "Detailed heartbeat includes streaming_status"
else
  fail "Detailed heartbeat missing streaming_status"
fi

# ── 17. Detailed heartbeat includes cameras list ───────────────────
log "Step 17: Detailed heartbeat includes cameras list"
if grep -A 30 'Build detailed payload' "$PIT_DASH" | grep -q '"cameras"'; then
  pass "Detailed heartbeat includes cameras"
else
  fail "Detailed heartbeat missing cameras"
fi

# ── 18. Cloud stores edge_url via set_edge_status ──────────────────
log "Step 18: Cloud stores edge_url via set_edge_status"
if grep -q '"edge_url".*data.edge_url' "$PROD_PY"; then
  pass "Cloud stores edge_url in edge status"
else
  fail "Cloud not storing edge_url"
fi

# ═══════════════════════════════════════════════════════════════════
# TEAM DIAGNOSTICS INTEGRATION
# ═══════════════════════════════════════════════════════════════════

# ── 19. get_diagnostics reads edge_presence ────────────────────────
log "Step 19: get_diagnostics reads edge_presence (vehicle-scoped)"
if grep -q 'get_edge_presence' "$TEAM_PY"; then
  pass "get_diagnostics reads edge_presence"
else
  fail "get_diagnostics not reading edge_presence"
fi

# ── 20. get_diagnostics returns edge_url ───────────────────────────
log "Step 20: get_diagnostics returns edge_url field"
if grep -q '"edge_url"' "$TEAM_PY"; then
  pass "get_diagnostics returns edge_url"
else
  fail "get_diagnostics missing edge_url in response"
fi

# ═══════════════════════════════════════════════════════════════════
# HEARTBEAT INFRASTRUCTURE
# ═══════════════════════════════════════════════════════════════════

# ── 21. Heartbeat stores heartbeat_ts ──────────────────────────────
log "Step 21: Heartbeat stores heartbeat_ts"
if grep -q '"heartbeat_ts"' "$PROD_PY"; then
  pass "Heartbeat handler stores heartbeat_ts"
else
  fail "Heartbeat handler missing heartbeat_ts"
fi

# ── 22. Heartbeat calls set_vehicle_last_seen ──────────────────────
log "Step 22: Heartbeat calls set_vehicle_last_seen"
if grep -q 'set_vehicle_last_seen' "$PROD_PY"; then
  pass "Heartbeat calls set_vehicle_last_seen"
else
  fail "Heartbeat missing set_vehicle_last_seen call"
fi

# ── 23. Redis edge status has TTL ─────────────────────────────────
log "Step 23: Redis edge status has TTL"
if grep -A 10 'def set_edge_status' "$REDIS_PY" | grep -q 'ex='; then
  pass "Edge status Redis key has TTL"
else
  fail "Edge status Redis key missing TTL"
fi

# ═══════════════════════════════════════════════════════════════════
# SYNTAX
# ═══════════════════════════════════════════════════════════════════

# ── 24-27. Python syntax compiles ──────────────────────────────────
STEP=24
for pyfile in "$TELEMETRY_PY" "$TEAM_PY" "$REDIS_PY" "$PIT_DASH"; do
  BASENAME=$(basename "$pyfile")
  log "Step $STEP: Python syntax compiles ($BASENAME)"
  if python3 -c "import ast; ast.parse(open('$pyfile').read())" 2>/dev/null; then
    pass "Python syntax OK ($BASENAME)"
  else
    fail "Python syntax error ($BASENAME)"
  fi
  STEP=$((STEP + 1))
done

# ═══════════════════════════════════════════════════════════════════
echo ""
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
