#!/usr/bin/env bash
# cloud_edge_presence_smoke.sh - Smoke test for CLOUD-EDGE-STATUS-1: Simple Heartbeat
#
# Validates:
#   1. Source: /api/v1/telemetry/heartbeat endpoint exists
#   2. Source: heartbeat endpoint calls set_vehicle_last_seen
#   3. Source: heartbeat auto-discovers event_id from truck token
#   4. Source: pit_crew_dashboard calls simple heartbeat
#   5. Source: UI diagnostics handles online/offline/unknown states
#   6. Live (optional): simple heartbeat → diagnostics returns online
#
# The key improvement in CLOUD-EDGE-STATUS-1:
#   - New /api/v1/telemetry/heartbeat endpoint that auto-discovers event from token
#   - Edge no longer needs event_id configured to send heartbeats
#   - Works immediately after provisioning with just truck_token
#
# Environment variables (for live tests only):
#   ARGUS_CLOUD_BASE_URL   - Cloud API base (default: http://localhost)
#   ARGUS_TEST_TRUCK_TOKEN - Truck token for auth (required for live tests)
#
# Usage:
#   bash scripts/cloud_edge_presence_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TELEMETRY_PY="$REPO_ROOT/cloud/app/routes/telemetry.py"
PIT_DASH_PY="$REPO_ROOT/edge/pit_crew_dashboard.py"
TEAM_PY="$REPO_ROOT/cloud/app/routes/team.py"
TEAM_DASH="$REPO_ROOT/web/src/pages/TeamDashboard.tsx"
FAIL=0

log()  { echo "[edge-presence]  $*"; }
pass() { echo "[edge-presence]    PASS: $*"; }
fail() { echo "[edge-presence]    FAIL: $*"; FAIL=1; }
skip() { echo "[edge-presence]    SKIP: $*"; }

log "CLOUD-EDGE-STATUS-1: Simple Heartbeat Smoke Test"
echo ""

# ── 1. Simple heartbeat endpoint exists ───────────────────────
log "Step 1: Simple heartbeat endpoint exists in telemetry.py"

if [ -f "$TELEMETRY_PY" ]; then
  if grep -q '@router.post("/telemetry/heartbeat")' "$TELEMETRY_PY"; then
    pass "POST /telemetry/heartbeat route exists"
  else
    fail "POST /telemetry/heartbeat route NOT found"
  fi

  if grep -q 'def telemetry_heartbeat' "$TELEMETRY_PY"; then
    pass "telemetry_heartbeat function exists"
  else
    fail "telemetry_heartbeat function NOT found"
  fi

  if grep -q 'CLOUD-EDGE-STATUS-1' "$TELEMETRY_PY"; then
    pass "CLOUD-EDGE-STATUS-1 comment marker present"
  else
    fail "CLOUD-EDGE-STATUS-1 comment marker missing"
  fi
else
  fail "telemetry.py not found"
fi

# ── 2. Heartbeat calls set_vehicle_last_seen ──────────────────
log "Step 2: Heartbeat endpoint updates last_seen"

if [ -f "$TELEMETRY_PY" ]; then
  # Check that the heartbeat function calls set_vehicle_last_seen
  # EDGE-CLOUD-1: Increased context window since heartbeat now has inline validation
  if grep -A 80 'def telemetry_heartbeat' "$TELEMETRY_PY" | grep -q 'set_vehicle_last_seen'; then
    pass "telemetry_heartbeat calls set_vehicle_last_seen"
  else
    fail "telemetry_heartbeat does NOT call set_vehicle_last_seen"
  fi
fi

# ── 3. Heartbeat auto-discovers event from token ──────────────
log "Step 3: Heartbeat uses validate_truck_token (auto-discovers event)"

if [ -f "$TELEMETRY_PY" ]; then
  if grep -A 30 'def telemetry_heartbeat' "$TELEMETRY_PY" | grep -q 'validate_truck_token'; then
    pass "telemetry_heartbeat uses validate_truck_token"
  else
    fail "telemetry_heartbeat does NOT use validate_truck_token"
  fi

  # Ensure it doesn't require event_id in the URL (no {event_id} in route)
  if grep '@router.post("/telemetry/heartbeat")' "$TELEMETRY_PY" | grep -q '{event_id}'; then
    fail "heartbeat route should NOT have {event_id} in path"
  else
    pass "heartbeat route has no {event_id} parameter (auto-discovered)"
  fi
fi

# ── 4. pit_crew_dashboard uses simple heartbeat ───────────────
log "Step 4: pit_crew_dashboard calls simple heartbeat endpoint"

if [ -f "$PIT_DASH_PY" ]; then
  if grep -q '/api/v1/telemetry/heartbeat' "$PIT_DASH_PY"; then
    pass "pit_crew_dashboard calls /api/v1/telemetry/heartbeat"
  else
    fail "pit_crew_dashboard does NOT call /api/v1/telemetry/heartbeat"
  fi

  if grep -q 'CLOUD-EDGE-STATUS-1' "$PIT_DASH_PY"; then
    pass "CLOUD-EDGE-STATUS-1 comment marker in pit_crew_dashboard"
  else
    fail "CLOUD-EDGE-STATUS-1 comment marker missing in pit_crew_dashboard"
  fi

  # Check it auto-discovers event_id from response
  if grep -q 'Auto-discover' "$PIT_DASH_PY" || grep -q 'auto-discover' "$PIT_DASH_PY"; then
    pass "pit_crew_dashboard auto-discovers event_id from response"
  else
    fail "pit_crew_dashboard missing event_id auto-discovery"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 5. UI diagnostics handles all states ──────────────────────
log "Step 5: UI and backend handle online/offline/unknown states"

if [ -f "$TEAM_PY" ]; then
  for state in '"online"' '"offline"' '"unknown"'; do
    if grep -q "$state" "$TEAM_PY"; then
      pass "team.py returns $state"
    else
      fail "team.py missing $state state"
    fi
  done
fi

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'edge_status' "$TEAM_DASH"; then
    pass "TeamDashboard renders edge_status"
  else
    fail "TeamDashboard missing edge_status"
  fi

  if grep -q 'edge_last_seen_ms' "$TEAM_DASH"; then
    pass "TeamDashboard renders edge_last_seen_ms"
  else
    fail "TeamDashboard missing edge_last_seen_ms"
  fi
fi

# ── 6. Live test: simple heartbeat → online (optional) ────────
BASE_URL="${ARGUS_CLOUD_BASE_URL:-http://localhost}"
TRUCK_TOKEN="${ARGUS_TEST_TRUCK_TOKEN:-}"

if [ -n "$TRUCK_TOKEN" ]; then
  log "Step 6: Live test - simple heartbeat (no event_id needed)"

  # Call simple heartbeat (should auto-discover event from token)
  HB_RESP=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "X-Truck-Token: $TRUCK_TOKEN" \
    "$BASE_URL/api/v1/telemetry/heartbeat" 2>/dev/null || echo -e "\n000")

  HB_BODY=$(echo "$HB_RESP" | head -n -1)
  HB_CODE=$(echo "$HB_RESP" | tail -n 1)

  if [ "$HB_CODE" = "200" ]; then
    pass "simple heartbeat accepted (HTTP 200)"

    # Check response contains vehicle_id and event_id
    HB_VID=$(echo "$HB_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('vehicle_id',''))" 2>/dev/null || echo "")
    HB_EID=$(echo "$HB_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('event_id',''))" 2>/dev/null || echo "")
    HB_TS=$(echo "$HB_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('server_ts_ms',''))" 2>/dev/null || echo "")

    if [ -n "$HB_VID" ] && [ "$HB_VID" != "None" ]; then
      pass "heartbeat returned vehicle_id: $HB_VID"
    else
      fail "heartbeat missing vehicle_id in response"
    fi

    if [ -n "$HB_EID" ] && [ "$HB_EID" != "None" ]; then
      pass "heartbeat returned event_id: $HB_EID"
    else
      fail "heartbeat missing event_id in response"
    fi

    if [ -n "$HB_TS" ] && [ "$HB_TS" != "None" ]; then
      pass "heartbeat returned server_ts_ms: $HB_TS"
    else
      fail "heartbeat missing server_ts_ms in response"
    fi

    # Now call heartbeat again to verify it's repeatable
    sleep 1
    HB_RESP2=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST \
      -H "X-Truck-Token: $TRUCK_TOKEN" \
      "$BASE_URL/api/v1/telemetry/heartbeat" 2>/dev/null || echo "000")

    if [ "$HB_RESP2" = "200" ]; then
      pass "second heartbeat also accepted (HTTP 200)"
    else
      fail "second heartbeat failed (HTTP $HB_RESP2)"
    fi

    # If we have a team token, verify diagnostics shows online
    TEAM_TOKEN="${ARGUS_TEST_TEAM_TOKEN:-}"
    if [ -n "$TEAM_TOKEN" ]; then
      log "Step 7: Live test - diagnostics shows online after heartbeat"

      sleep 2  # Allow time for Redis to update

      DIAG_RESP=$(curl -s \
        -H "Authorization: Bearer $TEAM_TOKEN" \
        "$BASE_URL/api/v1/team/diagnostics" 2>/dev/null || echo "{}")

      DIAG_STATUS=$(echo "$DIAG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('edge_status',''))" 2>/dev/null || echo "")
      DIAG_SEEN=$(echo "$DIAG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('edge_last_seen_ms',''))" 2>/dev/null || echo "")

      if [ "$DIAG_STATUS" = "online" ]; then
        pass "diagnostics edge_status = online"
      else
        fail "diagnostics edge_status = '$DIAG_STATUS' (expected 'online')"
      fi

      if [ -n "$DIAG_SEEN" ] && [ "$DIAG_SEEN" != "None" ] && [ "$DIAG_SEEN" != "null" ]; then
        pass "diagnostics edge_last_seen_ms is set (not 'Never')"
      else
        fail "diagnostics edge_last_seen_ms is null (would show 'Never')"
      fi
    else
      skip "Diagnostics verification skipped - set ARGUS_TEST_TEAM_TOKEN to enable"
    fi

  elif [ "$HB_CODE" = "401" ]; then
    fail "heartbeat rejected - invalid truck token (HTTP 401)"
  elif [ "$HB_CODE" = "400" ]; then
    fail "heartbeat rejected - vehicle not registered for event (HTTP 400)"
  elif [ "$HB_CODE" = "000" ]; then
    fail "heartbeat failed - could not connect to $BASE_URL"
  else
    fail "heartbeat rejected (HTTP $HB_CODE)"
  fi

else
  skip "Live tests skipped - set ARGUS_TEST_TRUCK_TOKEN to enable"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
