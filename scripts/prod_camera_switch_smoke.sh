#!/usr/bin/env bash
# prod_camera_switch_smoke.sh - Smoke test for Production Camera Switching Pipeline
#
# Validates end-to-end camera switch pipeline:
#   Cloud (production.py):
#     1.  VALID_CAMERAS has canonical 4 slots
#     2.  CAMERA_SLOT_ALIASES maps legacy names
#     3.  normalize_camera_slot function exists
#     4.  POST /featured-camera returns 202
#     5.  POST validates camera_id against VALID_CAMERAS
#     6.  Featured camera state stored in Redis
#     7.  Edge command published via Redis pub/sub
#     8.  GET auto-timeout detection with timeout_at
#     9.  Timeout includes request_id for correlation
#    10.  FEATURED_CAMERA_TIMEOUT_S = 15
#    11.  Command-response endpoint exists
#    12.  Command-response validates X-Truck-Token
#    13.  Command-response updates featured camera on success
#    14.  Command-response handles failure status
#    15.  Idempotency for same-camera requests
#    16.  CANONICAL_CAMERAS list has 4 entries
#   Edge (pit_crew_dashboard.py):
#    17.  Edge handles set_active_camera command
#    18.  Edge validates canonical + legacy camera names
#    19.  Edge normalizes legacy names via _normalize_camera_slot
#    20.  Edge rate limits camera switches (cooldown)
#    21.  Edge sends command-response ack to cloud
#    22.  Edge ack includes command_id correlation
#    23.  Edge ack sends X-Truck-Token header
#   ControlRoom (ControlRoom.tsx):
#    24.  setFeaturedCamera mutation exists
#    25.  POST to /featured-camera endpoint
#    26.  Polls pending state
#    27.  Auto-clears transient states
#    28.  Camera labels (Main Cam, Cockpit, Chase Cam, Suspension)
#   Syntax:
#    29.  Python syntax compiles
#   Live (optional):
#    30.  Cameras endpoint returns entries
#    31.  Switch command returns 202 + request_id
#    32.  GET status shows desired_camera
#
# Environment variables (for live tests only):
#   ARGUS_CLOUD_BASE_URL   - Cloud API base (default: http://localhost)
#   ARGUS_TEST_EVENT_ID    - Event ID for test
#   ARGUS_TEST_VEHICLE_ID  - Vehicle ID for test
#   ARGUS_TEST_ADMIN_TOKEN - Admin token for authenticated endpoints
#
# Usage:
#   bash scripts/prod_camera_switch_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[prod-cam-switch]  $*"; }
pass() { echo "[prod-cam-switch]    PASS: $*"; }
fail() { echo "[prod-cam-switch]    FAIL: $*"; FAIL=1; }
skip() { echo "[prod-cam-switch]    SKIP: $*"; }

PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"
CONTROL_TSX="$REPO_ROOT/web/src/pages/ControlRoom.tsx"
NGINX_CONF="$REPO_ROOT/web/nginx.conf"

log "PROD-CAM: Production Camera Switching Pipeline Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# CLOUD (production.py)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$PROD_PY" ]; then
  fail "production.py not found"
  exit 1
fi

# ── 1. VALID_CAMERAS canonical 4 slots ────────────────────────────
log "Step 1: Cloud VALID_CAMERAS has canonical 4 slots"

for cam in main cockpit chase suspension; do
  if grep -q "VALID_CAMERAS.*$cam" "$PROD_PY"; then
    pass "VALID_CAMERAS includes '$cam'"
  else
    fail "VALID_CAMERAS missing '$cam'"
  fi
done

# ── 2. CAMERA_SLOT_ALIASES maps legacy names ─────────────────────
log "Step 2: Cloud CAMERA_SLOT_ALIASES maps legacy names"

for alias in pov roof front rear; do
  if grep -q "\"$alias\"" "$PROD_PY"; then
    pass "Alias '$alias' defined"
  else
    fail "Missing alias '$alias'"
  fi
done

# ── 3. normalize_camera_slot function ─────────────────────────────
log "Step 3: Cloud normalize_camera_slot function"

if grep -q "def normalize_camera_slot" "$PROD_PY"; then
  pass "normalize_camera_slot exists"
else
  fail "normalize_camera_slot missing"
fi

# ── 4. POST /featured-camera returns 202 ─────────────────────────
log "Step 4: POST /featured-camera returns 202"

if grep -q 'status_code=202' "$PROD_PY"; then
  pass "POST returns 202 Accepted"
else
  fail "POST not returning 202"
fi

# ── 5. POST validates camera_id ──────────────────────────────────
log "Step 5: POST validates camera_id"

if grep -q 'camera_id not in VALID_CAMERAS' "$PROD_PY"; then
  pass "Validates camera_id against VALID_CAMERAS"
else
  fail "Not validating camera_id"
fi

# ── 6. Featured camera state in Redis ─────────────────────────────
log "Step 6: Featured camera state stored in Redis"

if grep -q 'set_featured_camera_state' "$PROD_PY"; then
  pass "Uses set_featured_camera_state"
else
  fail "Missing set_featured_camera_state"
fi

# ── 7. Edge command published via pub/sub ─────────────────────────
log "Step 7: Edge command published via Redis pub/sub"

if grep -q 'publish_edge_command' "$PROD_PY"; then
  pass "Publishes via publish_edge_command"
else
  fail "Missing publish_edge_command"
fi

# ── 8. GET auto-timeout detection ─────────────────────────────────
log "Step 8: GET auto-timeout detection"

if grep -q 'timeout_at' "$PROD_PY"; then
  pass "Auto-timeout uses timeout_at"
else
  fail "Missing timeout_at check"
fi

# ── 9. Timeout includes request_id for correlation ────────────────
log "Step 9: Timeout includes request_id for correlation"

if grep -q 'request_id=.*rid\|request_id=' "$PROD_PY" && grep -q 'featured_camera_timeout' "$PROD_PY"; then
  pass "Timeout log includes request_id correlation"
else
  fail "Timeout missing request_id correlation"
fi

# ── 10. FEATURED_CAMERA_TIMEOUT_S = 15 ───────────────────────────
log "Step 10: FEATURED_CAMERA_TIMEOUT_S = 15"

if grep -q 'FEATURED_CAMERA_TIMEOUT_S = 15' "$PROD_PY"; then
  pass "FEATURED_CAMERA_TIMEOUT_S = 15"
else
  fail "FEATURED_CAMERA_TIMEOUT_S not 15"
fi

# ── 11. Command-response endpoint ─────────────────────────────────
log "Step 11: Command-response endpoint exists"

if grep -q 'edge/command-response' "$PROD_PY"; then
  pass "Command-response endpoint exists"
else
  fail "Command-response endpoint missing"
fi

# ── 12. Command-response validates X-Truck-Token ─────────────────
log "Step 12: Command-response validates X-Truck-Token"

if grep -q 'X-Truck-Token' "$PROD_PY"; then
  pass "Validates X-Truck-Token"
else
  fail "Not validating X-Truck-Token"
fi

# ── 13. Command-response updates featured camera on success ───────
log "Step 13: Command-response updates featured camera on success"

if grep -q "featured_state\[.status.\] = .success." "$PROD_PY"; then
  pass "ACK updates state to success"
else
  fail "ACK not updating to success"
fi

# ── 14. Command-response handles failure ──────────────────────────
log "Step 14: Command-response handles failure"

if grep -q "featured_state\[.status.\] = .failed." "$PROD_PY"; then
  pass "ACK updates state to failed"
else
  fail "ACK not handling failure"
fi

# ── 15. Idempotency for same-camera requests ─────────────────────
log "Step 15: Idempotency for same-camera requests"

if grep -q 'idempotent\|Same camera already pending' "$PROD_PY"; then
  pass "Idempotency check exists"
else
  fail "Missing idempotency check"
fi

# ── 16. CANONICAL_CAMERAS list ────────────────────────────────────
log "Step 16: CANONICAL_CAMERAS list has 4 entries"

if grep -q 'CANONICAL_CAMERAS = \[' "$PROD_PY"; then
  CAM_LINE=$(grep 'CANONICAL_CAMERAS = \[' "$PROD_PY" | head -1)
  CAM_COUNT=$(echo "$CAM_LINE" | grep -o '"[a-z]*"' | wc -l | tr -d ' ')
  if [ "$CAM_COUNT" -eq 4 ]; then
    pass "CANONICAL_CAMERAS has 4 entries"
  else
    fail "CANONICAL_CAMERAS has $CAM_COUNT entries (expected 4)"
  fi
else
  fail "CANONICAL_CAMERAS not defined"
fi

# ═══════════════════════════════════════════════════════════════════
# EDGE (pit_crew_dashboard.py)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ── 17. Edge handles set_active_camera ────────────────────────────
log "Step 17: Edge handles set_active_camera command"

if grep -q 'set_active_camera' "$PIT_DASH"; then
  pass "Edge handles set_active_camera"
else
  fail "Edge missing set_active_camera"
fi

# ── 18. Edge validates canonical + legacy names ───────────────────
log "Step 18: Edge validates canonical + legacy camera names"

if grep -q 'all_valid_cameras' "$PIT_DASH"; then
  pass "Edge has all_valid_cameras set"
else
  fail "Edge missing camera validation set"
fi

for cam in main cockpit chase suspension pov roof front; do
  if grep -q "'$cam'" "$PIT_DASH"; then
    pass "Edge recognizes '$cam'"
  else
    fail "Edge missing '$cam'"
  fi
done

# ── 19. Edge normalizes legacy names ──────────────────────────────
log "Step 19: Edge normalizes legacy camera names"

if grep -q '_normalize_camera_slot' "$PIT_DASH"; then
  pass "Edge has _normalize_camera_slot"
else
  fail "Edge missing _normalize_camera_slot"
fi

# ── 20. Edge rate limits camera switches ──────────────────────────
log "Step 20: Edge rate limits camera switches"

if grep -q 'camera_switch_cooldown' "$PIT_DASH"; then
  pass "Edge has camera switch cooldown"
else
  fail "Edge missing camera switch cooldown"
fi

# ── 21. Edge sends command-response ack ───────────────────────────
log "Step 21: Edge sends command-response ack to cloud"

if grep -q '_send_command_response' "$PIT_DASH"; then
  pass "Edge has _send_command_response"
else
  fail "Edge missing _send_command_response"
fi

if grep -q 'command-response' "$PIT_DASH"; then
  pass "Edge posts to command-response endpoint"
else
  fail "Edge not posting to command-response"
fi

# ── 22. Edge ack includes command_id ──────────────────────────────
log "Step 22: Edge ack includes command_id correlation"

if grep -q '"command_id"' "$PIT_DASH"; then
  pass "Edge ack sends command_id"
else
  fail "Edge ack missing command_id"
fi

# ── 23. Edge ack sends X-Truck-Token ─────────────────────────────
log "Step 23: Edge ack sends X-Truck-Token"

if grep -q 'X-Truck-Token.*truck_token\|"X-Truck-Token"' "$PIT_DASH"; then
  pass "Edge ack includes X-Truck-Token"
else
  fail "Edge ack missing X-Truck-Token"
fi

# ═══════════════════════════════════════════════════════════════════
# CONTROLROOM (ControlRoom.tsx)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$CONTROL_TSX" ]; then
  fail "ControlRoom.tsx not found"
  exit 1
fi

# ── 24. setFeaturedCamera mutation ────────────────────────────────
log "Step 24: ControlRoom setFeaturedCamera mutation"

if grep -q 'setFeaturedCamera' "$CONTROL_TSX"; then
  pass "setFeaturedCamera mutation exists"
else
  fail "setFeaturedCamera missing"
fi

# ── 25. POST to /featured-camera ─────────────────────────────────
log "Step 25: ControlRoom POST to /featured-camera"

if grep -q 'featured-camera' "$CONTROL_TSX"; then
  pass "Posts to /featured-camera"
else
  fail "Not posting to /featured-camera"
fi

# ── 26. Polls pending state ───────────────────────────────────────
log "Step 26: ControlRoom polls pending state"

if grep -q 'pendingVehicles' "$CONTROL_TSX"; then
  pass "Tracks pending vehicles for polling"
else
  fail "Not tracking pending state"
fi

# ── 27. Auto-clears transient states ─────────────────────────────
log "Step 27: ControlRoom auto-clears transient states"

if grep -q 'transientStates' "$CONTROL_TSX"; then
  pass "Auto-clears transient states"
else
  fail "Not auto-clearing transient states"
fi

# ── 28. Camera labels ─────────────────────────────────────────────
log "Step 28: ControlRoom camera labels"

for label in "Main Cam" "Cockpit" "Chase Cam" "Suspension"; do
  if grep -q "$label" "$CONTROL_TSX"; then
    pass "Label '$label' present"
  else
    fail "Label '$label' missing"
  fi
done

# ═══════════════════════════════════════════════════════════════════
# SYNTAX CHECKS
# ═══════════════════════════════════════════════════════════════════

log "Step 29: Python syntax compiles"

for pyfile in "$PROD_PY" "$PIT_DASH"; do
  basename=$(basename "$pyfile")
  if python3 -m py_compile "$pyfile" 2>/dev/null; then
    pass "$basename compiles"
  else
    fail "$basename has syntax errors"
  fi
done

# ═══════════════════════════════════════════════════════════════════
# LIVE TESTS (optional)
# ═══════════════════════════════════════════════════════════════════

BASE_URL="${ARGUS_CLOUD_BASE_URL:-http://localhost}"
EVENT_ID="${ARGUS_TEST_EVENT_ID:-}"
VEHICLE_ID="${ARGUS_TEST_VEHICLE_ID:-}"
ADMIN_TOKEN="${ARGUS_TEST_ADMIN_TOKEN:-}"

if [ -n "$EVENT_ID" ]; then
  log "Step 30: Live - cameras endpoint"

  CAM_RESP=$(curl -s "$BASE_URL/api/v1/production/events/$EVENT_ID/cameras" 2>/dev/null || echo "[]")
  CAM_COUNT=$(echo "$CAM_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")

  if [ "$CAM_COUNT" -ge 4 ]; then
    pass "Cameras endpoint returned $CAM_COUNT cameras (>= 4)"
  elif [ "$CAM_COUNT" -gt 0 ]; then
    pass "Cameras endpoint returned $CAM_COUNT cameras"
  else
    fail "Cameras endpoint returned 0 cameras"
  fi
else
  skip "Live cameras test skipped - set ARGUS_TEST_EVENT_ID"
fi

if [ -n "$EVENT_ID" ] && [ -n "$VEHICLE_ID" ] && [ -n "$ADMIN_TOKEN" ]; then
  log "Step 31: Live - switch command returns 202"

  SWITCH_RESP=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Admin-Token: $ADMIN_TOKEN" \
    -d '{"camera_id": "cockpit"}' \
    "$BASE_URL/api/v1/production/events/$EVENT_ID/vehicles/$VEHICLE_ID/featured-camera" 2>/dev/null || echo -e "\n000")

  SWITCH_BODY=$(echo "$SWITCH_RESP" | head -n -1)
  SWITCH_CODE=$(echo "$SWITCH_RESP" | tail -n 1)

  if [ "$SWITCH_CODE" = "202" ]; then
    pass "Switch command accepted (HTTP 202)"
    REQUEST_ID=$(echo "$SWITCH_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('request_id',''))" 2>/dev/null || echo "")
    if [ -n "$REQUEST_ID" ] && [ "$REQUEST_ID" != "None" ]; then
      pass "Response contains request_id: $REQUEST_ID"
    else
      fail "Response missing request_id"
    fi
  else
    fail "Switch command failed (HTTP $SWITCH_CODE)"
  fi

  log "Step 32: Live - GET status shows desired_camera"

  sleep 1
  STATUS_RESP=$(curl -s "$BASE_URL/api/v1/production/events/$EVENT_ID/vehicles/$VEHICLE_ID/featured-camera" 2>/dev/null || echo "{}")
  STATUS=$(echo "$STATUS_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || echo "")

  if [ "$STATUS" = "pending" ] || [ "$STATUS" = "success" ] || [ "$STATUS" = "timeout" ]; then
    pass "Status is valid: $STATUS"
  else
    fail "Status is '$STATUS' (expected pending/success/timeout)"
  fi
else
  skip "Live switch/status tests skipped - set ARGUS_TEST_EVENT_ID, ARGUS_TEST_VEHICLE_ID, ARGUS_TEST_ADMIN_TOKEN"
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
