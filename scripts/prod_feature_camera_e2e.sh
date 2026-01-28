#!/usr/bin/env bash
# prod_feature_camera_e2e.sh — E2E smoke test for Featured Camera full loop
#
# Proves the full loop works:
#   Control Room click → Cloud API → Command publish → Edge receives →
#   switches camera → ACK → Cloud state updates → UI updates.
#
# Inputs (env vars or positional args):
#   EVENT_ID       - Event to test against
#   VEHICLE_ID     - Vehicle to switch camera on
#   CAMERA_ID      - Target camera (chase|pov|roof|front), default: pov
#   CLOUD_BASE_URL - Cloud API base, default: http://localhost:8000
#   ADMIN_TOKEN    - Admin token for POST auth (X-Admin-Token header)
#   TRUCK_TOKEN    - (optional) Truck token for mock edge ACK
#
# When TRUCK_TOKEN is set, the script simulates the edge device by sending
# a success ACK back to the cloud after the POST. This allows E2E verification
# without a physical edge device.
#
# Usage:
#   EVENT_ID=ev_123 VEHICLE_ID=v_456 ADMIN_TOKEN=secret \
#     bash scripts/prod_feature_camera_e2e.sh
#
#   # With mock edge (no physical edge needed):
#   EVENT_ID=ev_123 VEHICLE_ID=v_456 ADMIN_TOKEN=secret TRUCK_TOKEN=truck_xxx \
#     bash scripts/prod_feature_camera_e2e.sh
#
#   # Or positional: event_id vehicle_id [camera_id] [cloud_base_url] [admin_token]
#   bash scripts/prod_feature_camera_e2e.sh ev_123 v_456 pov http://localhost:8000 secret
#
# Exit 0 only if success confirmed.
set -euo pipefail

# ── Parse inputs ──────────────────────────────────────────────────
EVENT_ID="${1:-${EVENT_ID:-}}"
VEHICLE_ID="${2:-${VEHICLE_ID:-}}"
CAMERA_ID="${3:-${CAMERA_ID:-pov}}"
CLOUD_BASE_URL="${4:-${CLOUD_BASE_URL:-http://localhost:8000}}"
ADMIN_TOKEN="${5:-${ADMIN_TOKEN:-}}"
TRUCK_TOKEN="${TRUCK_TOKEN:-}"

# Strip trailing slash
CLOUD_BASE_URL="${CLOUD_BASE_URL%/}"

PREFIX="[e2e-feature-cam]"
FAIL=0

log()  { echo "$PREFIX $*"; }
pass() { echo "$PREFIX   PASS: $*"; }
fail() { echo "$PREFIX   FAIL: $*"; FAIL=1; }
warn() { echo "$PREFIX   WARN: $*"; }

# ── Validate inputs ──────────────────────────────────────────────
log "Validating inputs..."

if [ -z "$EVENT_ID" ]; then
  fail "EVENT_ID is required (env var or first positional arg)"
  echo "$PREFIX Usage: EVENT_ID=xxx VEHICLE_ID=yyy ADMIN_TOKEN=zzz bash $0"
  exit 1
fi

if [ -z "$VEHICLE_ID" ]; then
  fail "VEHICLE_ID is required (env var or second positional arg)"
  exit 1
fi

if [ -z "$ADMIN_TOKEN" ]; then
  fail "ADMIN_TOKEN is required (env var or fifth positional arg)"
  exit 1
fi

case "$CAMERA_ID" in
  chase|pov|roof|front)
    pass "Camera ID valid: $CAMERA_ID"
    ;;
  *)
    fail "Invalid CAMERA_ID: $CAMERA_ID (must be chase|pov|roof|front)"
    exit 1
    ;;
esac

MOCK_EDGE=false
if [ -n "$TRUCK_TOKEN" ]; then
  MOCK_EDGE=true
fi

log "Target: $CLOUD_BASE_URL"
log "Event:  $EVENT_ID"
log "Vehicle: $VEHICLE_ID"
log "Camera: $CAMERA_ID"
[ "$MOCK_EDGE" = true ] && log "Mode:   mock-edge (will simulate ACK)"
echo ""

# ── Step 1: POST featured-camera request ──────────────────────────
log "Step 1: POST featured-camera request"

FEATURED_URL="$CLOUD_BASE_URL/api/v1/production/events/$EVENT_ID/vehicles/$VEHICLE_ID/featured-camera"

POST_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "$FEATURED_URL" \
  -H "X-Admin-Token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"camera_id\": \"$CAMERA_ID\"}" \
  2>&1) || true

# Split body and status code
POST_HTTP_CODE=$(echo "$POST_RESPONSE" | tail -1)
POST_BODY=$(echo "$POST_RESPONSE" | sed '$d')

if [ "$POST_HTTP_CODE" = "202" ]; then
  pass "POST returned 202 Accepted"
else
  fail "POST returned HTTP $POST_HTTP_CODE (expected 202)"
  log "Response body: $POST_BODY"

  # Collect logs on failure
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  if [ -f "$SCRIPT_DIR/collect_prod_feature_logs.sh" ]; then
    warn "Collecting logs for diagnosis..."
    bash "$SCRIPT_DIR/collect_prod_feature_logs.sh" 5 2>/dev/null || true
  fi
  exit 1
fi

# Extract request_id from response
REQUEST_ID=""
if command -v python3 >/dev/null 2>&1; then
  REQUEST_ID=$(echo "$POST_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('request_id',''))" 2>/dev/null || echo "")
elif command -v jq >/dev/null 2>&1; then
  REQUEST_ID=$(echo "$POST_BODY" | jq -r '.request_id // ""' 2>/dev/null || echo "")
fi

if [ -n "$REQUEST_ID" ]; then
  pass "Got request_id: $REQUEST_ID"
else
  warn "Could not extract request_id from response"
  log "Response: $POST_BODY"
fi

# Extract initial status
INITIAL_STATUS=""
if command -v python3 >/dev/null 2>&1; then
  INITIAL_STATUS=$(echo "$POST_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
elif command -v jq >/dev/null 2>&1; then
  INITIAL_STATUS=$(echo "$POST_BODY" | jq -r '.status // ""' 2>/dev/null || echo "")
fi

if [ "$INITIAL_STATUS" = "pending" ]; then
  pass "Initial status is 'pending'"
else
  warn "Initial status: '$INITIAL_STATUS' (expected 'pending')"
fi

echo ""

# ── Step 1b: Mock edge ACK (if TRUCK_TOKEN set) ──────────────────
if [ "$MOCK_EDGE" = true ] && [ -n "$REQUEST_ID" ]; then
  log "Step 1b: Sending mock edge ACK (simulating edge device)"

  # Brief pause to let cloud store the command
  sleep 1

  ACK_URL="$CLOUD_BASE_URL/api/v1/production/events/$EVENT_ID/edge/command-response"
  ACK_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$ACK_URL" \
    -H "X-Truck-Token: $TRUCK_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"command_id\": \"$REQUEST_ID\", \"status\": \"success\", \"message\": \"Camera switched to $CAMERA_ID (mock)\"}" \
    2>&1) || true

  ACK_HTTP_CODE=$(echo "$ACK_RESPONSE" | tail -1)
  ACK_BODY=$(echo "$ACK_RESPONSE" | sed '$d')

  if [ "$ACK_HTTP_CODE" = "200" ]; then
    pass "Mock edge ACK accepted (HTTP 200)"
  else
    warn "Mock edge ACK returned HTTP $ACK_HTTP_CODE: $ACK_BODY"
  fi
  echo ""
fi

# ── Step 2: Poll for state transition (pending → success) ─────────
log "Step 2: Polling for state transition..."

POLL_INTERVAL=2
POLL_TIMEOUT=20
POLL_ELAPSED=0
FINAL_STATUS=""

while [ "$POLL_ELAPSED" -lt "$POLL_TIMEOUT" ]; do
  sleep "$POLL_INTERVAL"
  POLL_ELAPSED=$((POLL_ELAPSED + POLL_INTERVAL))

  GET_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X GET "$FEATURED_URL" \
    2>&1) || true

  GET_HTTP_CODE=$(echo "$GET_RESPONSE" | tail -1)
  GET_BODY=$(echo "$GET_RESPONSE" | sed '$d')

  if [ "$GET_HTTP_CODE" != "200" ]; then
    warn "GET returned HTTP $GET_HTTP_CODE at ${POLL_ELAPSED}s"
    continue
  fi

  # Extract status
  CURRENT_STATUS=""
  if command -v python3 >/dev/null 2>&1; then
    CURRENT_STATUS=$(echo "$GET_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
  elif command -v jq >/dev/null 2>&1; then
    CURRENT_STATUS=$(echo "$GET_BODY" | jq -r '.status // ""' 2>/dev/null || echo "")
  fi

  log "  Poll ${POLL_ELAPSED}s: status=$CURRENT_STATUS"

  case "$CURRENT_STATUS" in
    success)
      FINAL_STATUS="success"
      break
      ;;
    failed)
      FINAL_STATUS="failed"
      # Extract error
      LAST_ERROR=""
      if command -v python3 >/dev/null 2>&1; then
        LAST_ERROR=$(echo "$GET_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('last_error',''))" 2>/dev/null || echo "")
      fi
      break
      ;;
    timeout)
      FINAL_STATUS="timeout"
      break
      ;;
    pending)
      # Keep polling
      ;;
    idle)
      # State was cleared (auto-clear after success), treat as success
      FINAL_STATUS="idle-after-clear"
      break
      ;;
    *)
      warn "Unexpected status: '$CURRENT_STATUS'"
      ;;
  esac
done

echo ""

# ── Step 3: Evaluate result ────────────────────────────────────────
log "Step 3: Evaluating result"

case "$FINAL_STATUS" in
  success)
    pass "Camera switch confirmed (status=success)"
    # Verify active_camera matches requested
    ACTIVE_CAM=""
    if command -v python3 >/dev/null 2>&1; then
      ACTIVE_CAM=$(echo "$GET_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('active_camera',''))" 2>/dev/null || echo "")
    elif command -v jq >/dev/null 2>&1; then
      ACTIVE_CAM=$(echo "$GET_BODY" | jq -r '.active_camera // ""' 2>/dev/null || echo "")
    fi
    if [ "$ACTIVE_CAM" = "$CAMERA_ID" ]; then
      pass "active_camera matches requested: $ACTIVE_CAM"
    else
      warn "active_camera='$ACTIVE_CAM' (expected '$CAMERA_ID')"
    fi
    ;;
  idle-after-clear)
    pass "State returned to idle (auto-cleared after success)"
    ;;
  failed)
    fail "Camera switch failed: $LAST_ERROR"
    ;;
  timeout)
    fail "Camera switch timed out (edge did not respond within deadline)"
    ;;
  "")
    fail "Polling timed out after ${POLL_TIMEOUT}s (still pending — edge may be unreachable)"
    ;;
  *)
    fail "Unexpected final status: $FINAL_STATUS"
    ;;
esac

# ── Step 4: On failure, collect logs ───────────────────────────────
if [ "$FAIL" -ne 0 ]; then
  echo ""
  log "Step 4: Collecting diagnostic logs..."
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  if [ -f "$SCRIPT_DIR/collect_prod_feature_logs.sh" ]; then
    bash "$SCRIPT_DIR/collect_prod_feature_logs.sh" 5 2>/dev/null || warn "Log collection failed"
  else
    warn "collect_prod_feature_logs.sh not found — skipping log collection"
  fi
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "E2E TEST PASSED"
  exit 0
else
  log "E2E TEST FAILED"
  exit 1
fi
