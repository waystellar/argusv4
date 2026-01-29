#!/usr/bin/env bash
# team_edge_presence_smoke.sh — Smoke test for TEAM-EDGE-1: Edge Presence / Online Status
#
# Validates:
#   1. Source: heartbeat endpoint calls set_vehicle_last_seen
#   2. Source: diagnostics computes online/stale/offline from age
#   3. Source: diagnostics returns required fields
#   4. Source: TeamDashboard renders edge_status defensively
#   5. Source: TeamDashboard shows offline alert with causes
#   6. Live (optional): heartbeat → diagnostics returns online
#   7. Live (optional): after threshold → diagnostics returns offline
#
# Environment variables (for live tests only):
#   ARGUS_CLOUD_BASE_URL   — Cloud API base (default: http://localhost)
#   ARGUS_TEST_EVENT_ID    — Event ID for test
#   ARGUS_TEST_VEHICLE_ID  — Vehicle ID for test
#   ARGUS_TEST_TRUCK_TOKEN — Truck token for auth
#   ARGUS_TEST_TEAM_TOKEN  — Team JWT for diagnostics endpoint
#
# Usage:
#   bash scripts/team_edge_presence_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
TEAM_PY="$REPO_ROOT/cloud/app/routes/team.py"
REDIS_PY="$REPO_ROOT/cloud/app/redis_client.py"
TEAM_DASH="$REPO_ROOT/web/src/pages/TeamDashboard.tsx"
FAIL=0

log()  { echo "[edge-presence]  $*"; }
pass() { echo "[edge-presence]    PASS: $*"; }
fail() { echo "[edge-presence]    FAIL: $*"; FAIL=1; }
skip() { echo "[edge-presence]    SKIP: $*"; }

# ── 1. Heartbeat writes last_seen ─────────────────────────────
log "Step 1: Heartbeat endpoint persists last_seen"

if [ -f "$PROD_PY" ]; then
  if grep -A 10 'set_edge_status' "$PROD_PY" | grep -q 'set_vehicle_last_seen'; then
    pass "heartbeat calls set_vehicle_last_seen after set_edge_status"
  else
    fail "heartbeat does NOT call set_vehicle_last_seen"
  fi

  if grep -q 'edge_heartbeat_received' "$PROD_PY"; then
    pass "heartbeat has structured log line"
  else
    fail "heartbeat missing structured log"
  fi
else
  fail "production.py not found"
fi

# ── 2. Diagnostics computes online/offline server-side ────────
log "Step 2: Diagnostics endpoint computes online/stale/offline"

if [ -f "$TEAM_PY" ]; then
  if grep -q 'age_s <= 30' "$TEAM_PY"; then
    pass "online threshold <= 30s"
  else
    fail "missing 30s online threshold"
  fi

  if grep -q 'age_s <= 60' "$TEAM_PY"; then
    pass "stale threshold <= 60s"
  else
    fail "missing 60s stale threshold"
  fi

  if grep -q '"offline"' "$TEAM_PY" && grep -q '"online"' "$TEAM_PY" && grep -q '"stale"' "$TEAM_PY"; then
    pass "all three status values: online, stale, offline"
  else
    fail "missing one or more status values"
  fi

  if grep -q '"unknown"' "$TEAM_PY"; then
    pass "unknown status for null last_seen"
  else
    fail "missing unknown status fallback"
  fi
else
  fail "team.py not found"
fi

# ── 3. Diagnostics returns required fields ────────────────────
log "Step 3: Diagnostics response fields"

if [ -f "$TEAM_PY" ]; then
  for field in '"edge_status"' '"is_online"' '"edge_last_seen_ms"' '"edge_ip"' '"edge_version"'; do
    if grep -q "$field" "$TEAM_PY"; then
      pass "response includes $field"
    else
      fail "response missing $field"
    fi
  done
fi

# ── 4. Frontend renders defensively ──────────────────────────
log "Step 4: TeamDashboard defensive rendering"

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'diagnostics?.edge_status' "$TEAM_DASH"; then
    pass "optional chaining on edge_status"
  else
    fail "missing optional chaining on edge_status"
  fi

  if grep -q 'diagnostics?.edge_last_seen_ms' "$TEAM_DASH"; then
    pass "optional chaining on edge_last_seen_ms"
  else
    fail "missing optional chaining on edge_last_seen_ms"
  fi

  if grep -q "Edge Status" "$TEAM_DASH"; then
    pass "shows Edge Status label"
  else
    fail "missing Edge Status label"
  fi

  if grep -q "'Never'" "$TEAM_DASH" || grep -q '"Never"' "$TEAM_DASH"; then
    pass "shows 'Never' for null last_seen"
  else
    fail "missing 'Never' fallback text"
  fi
else
  fail "TeamDashboard.tsx not found"
fi

# ── 5. Offline alert with causes ─────────────────────────────
log "Step 5: Offline alert with troubleshooting causes"

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'Edge Device Offline' "$TEAM_DASH"; then
    pass "offline alert heading"
  else
    fail "missing 'Edge Device Offline' alert"
  fi

  if grep -q 'truck token' "$TEAM_DASH"; then
    pass "offline causes mention truck token"
  else
    fail "offline causes missing truck token"
  fi

  if grep -q 'cloud URL' "$TEAM_DASH"; then
    pass "offline causes mention cloud URL"
  else
    fail "offline causes missing cloud URL"
  fi
fi

# ── 6. Redis client has required functions ────────────────────
log "Step 6: Redis client functions"

if [ -f "$REDIS_PY" ]; then
  for fn in 'def set_vehicle_last_seen' 'def get_vehicle_last_seen' 'def set_edge_status' 'def get_edge_status'; do
    if grep -q "$fn" "$REDIS_PY"; then
      pass "redis_client has $fn"
    else
      fail "redis_client missing $fn"
    fi
  done
else
  fail "redis_client.py not found"
fi

# ── 7. Live test: heartbeat → online (optional) ──────────────
BASE_URL="${ARGUS_CLOUD_BASE_URL:-http://localhost}"
EVENT_ID="${ARGUS_TEST_EVENT_ID:-}"
VEHICLE_ID="${ARGUS_TEST_VEHICLE_ID:-}"
TRUCK_TOKEN="${ARGUS_TEST_TRUCK_TOKEN:-}"
TEAM_TOKEN="${ARGUS_TEST_TEAM_TOKEN:-}"

if [ -n "$EVENT_ID" ] && [ -n "$VEHICLE_ID" ] && [ -n "$TRUCK_TOKEN" ] && [ -n "$TEAM_TOKEN" ]; then
  log "Step 7: Live heartbeat → online test"

  NOW_MS=$(($(date +%s) * 1000))
  HB_BODY="{\"streaming_status\":\"idle\",\"streaming_camera\":null,\"streaming_started_at\":null,\"streaming_error\":null,\"cameras\":[],\"last_can_ts\":null,\"last_gps_ts\":null,\"youtube_configured\":false,\"youtube_url\":null}"

  HB_RESP=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Truck-Token: $TRUCK_TOKEN" \
    -d "$HB_BODY" \
    "$BASE_URL/api/v1/production/events/$EVENT_ID/edge/heartbeat" 2>/dev/null || echo "000")

  if [ "$HB_RESP" = "200" ]; then
    pass "heartbeat accepted (HTTP 200)"
  else
    fail "heartbeat rejected (HTTP $HB_RESP)"
  fi

  # Check diagnostics within 5s
  sleep 2

  DIAG_RESP=$(curl -s \
    -H "Authorization: Bearer $TEAM_TOKEN" \
    "$BASE_URL/api/v1/team/diagnostics" 2>/dev/null || echo "{}")

  DIAG_STATUS=$(echo "$DIAG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('edge_status',''))" 2>/dev/null || echo "")
  DIAG_ONLINE=$(echo "$DIAG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('is_online',''))" 2>/dev/null || echo "")
  DIAG_SEEN=$(echo "$DIAG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('edge_last_seen_ms',''))" 2>/dev/null || echo "")

  if [ "$DIAG_STATUS" = "online" ]; then
    pass "diagnostics edge_status = online"
  else
    fail "diagnostics edge_status = '$DIAG_STATUS' (expected 'online')"
  fi

  if [ "$DIAG_ONLINE" = "True" ]; then
    pass "diagnostics is_online = True"
  else
    fail "diagnostics is_online = '$DIAG_ONLINE' (expected True)"
  fi

  if [ -n "$DIAG_SEEN" ] && [ "$DIAG_SEEN" != "None" ] && [ "$DIAG_SEEN" != "null" ]; then
    pass "diagnostics edge_last_seen_ms is set ($DIAG_SEEN)"
  else
    fail "diagnostics edge_last_seen_ms is null/unset"
  fi

  # ── 8. Live test: wait for offline threshold ──────────────
  log "Step 8: Wait for offline threshold (65s) — verifying status flip"

  sleep 65

  DIAG_RESP2=$(curl -s \
    -H "Authorization: Bearer $TEAM_TOKEN" \
    "$BASE_URL/api/v1/team/diagnostics" 2>/dev/null || echo "{}")

  DIAG_STATUS2=$(echo "$DIAG_RESP2" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('edge_status',''))" 2>/dev/null || echo "")

  if [ "$DIAG_STATUS2" = "offline" ]; then
    pass "diagnostics edge_status flipped to offline after 65s"
  else
    fail "diagnostics edge_status = '$DIAG_STATUS2' after 65s (expected 'offline')"
  fi
else
  skip "Live tests skipped — set ARGUS_TEST_EVENT_ID, ARGUS_TEST_VEHICLE_ID, ARGUS_TEST_TRUCK_TOKEN, and ARGUS_TEST_TEAM_TOKEN to enable"
fi

# ── Summary ────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
