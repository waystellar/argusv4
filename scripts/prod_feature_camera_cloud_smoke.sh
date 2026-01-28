#!/usr/bin/env bash
# prod_feature_camera_cloud_smoke.sh — Smoke test for PROD-CAM-1: Cloud Featured Camera API
#
# Validates (source-level) that the cloud API has:
#   1. POST featured-camera endpoint registered
#   2. GET featured-camera endpoint registered
#   3. FeaturedCameraRequest / FeaturedCameraResponse / FeaturedCameraState schemas
#   4. set_featured_camera handler with 202 status
#   5. Camera validation against VALID_CAMERAS
#   6. Idempotency for pending requests
#   7. Edge command broadcast via publish_edge_command
#   8. Command type is set_active_camera
#   9. Edge ACK endpoint (command-response)
#  10. ACK wiring: featured_camera_state updated on ACK
#  11. ACK correlates by request_id
#  12. Redis helpers: set/get_featured_camera_state
#  13. Redis helpers: set/get_edge_command, publish_edge_command
#  14. GET stream-states endpoint exists
#  15. Auto-timeout on GET when past deadline
#  16. FEATURED_CAMERA_TIMEOUT_S constant
#  17. Broadcast state updated for fans
#  18. Python syntax check: production.py
#  19. Python syntax check: redis_client.py
#  20. Module-level logger (not local-only)
#
# Usage:
#   bash scripts/prod_feature_camera_cloud_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
REDIS_PY="$REPO_ROOT/cloud/app/redis_client.py"
STREAM_PY="$REPO_ROOT/cloud/app/routes/stream.py"
FAIL=0

log()  { echo "[cloud-feature-cam] $*"; }
pass() { echo "[cloud-feature-cam]   PASS: $*"; }
fail() { echo "[cloud-feature-cam]   FAIL: $*"; FAIL=1; }

# ── 1. POST featured-camera endpoint ──────────────────────────────
log "Step 1: POST featured-camera endpoint"

if [ -f "$PROD_PY" ]; then
  if grep -q 'vehicles/{vehicle_id}/featured-camera' "$PROD_PY"; then
    pass "featured-camera URL path registered"
  else
    fail "featured-camera URL path missing"
  fi

  if grep -q "status_code=202" "$PROD_PY"; then
    pass "Returns 202 Accepted"
  else
    fail "Missing 202 status code"
  fi
else
  fail "production.py not found"
fi

# ── 2. GET featured-camera endpoint ────────────────────────────────
log "Step 2: GET featured-camera endpoint"

if [ -f "$PROD_PY" ]; then
  if grep -q "async def get_featured_camera" "$PROD_PY"; then
    pass "get_featured_camera handler exists"
  else
    fail "get_featured_camera handler missing"
  fi

  if grep -q "response_model=FeaturedCameraState" "$PROD_PY"; then
    pass "GET returns FeaturedCameraState model"
  else
    fail "GET response model not set"
  fi
fi

# ── 3. Schemas ─────────────────────────────────────────────────────
log "Step 3: Featured camera schemas"

if [ -f "$PROD_PY" ]; then
  for schema in FeaturedCameraRequest FeaturedCameraResponse FeaturedCameraState; do
    if grep -q "class $schema" "$PROD_PY"; then
      pass "$schema schema exists"
    else
      fail "$schema schema missing"
    fi
  done

  if grep -q "desired_camera" "$PROD_PY"; then
    pass "desired_camera field exists"
  else
    fail "desired_camera field missing"
  fi

  if grep -q "active_camera" "$PROD_PY"; then
    pass "active_camera field exists"
  else
    fail "active_camera field missing"
  fi

  if grep -q "request_id: str" "$PROD_PY"; then
    pass "request_id field in response"
  else
    fail "request_id field missing"
  fi
fi

# ── 4. Handler with 202 ───────────────────────────────────────────
log "Step 4: set_featured_camera handler"

if [ -f "$PROD_PY" ]; then
  if grep -q "async def set_featured_camera" "$PROD_PY"; then
    pass "set_featured_camera handler exists"
  else
    fail "set_featured_camera handler missing"
  fi

  if grep -q "response_model=FeaturedCameraResponse" "$PROD_PY"; then
    pass "Response model is FeaturedCameraResponse"
  else
    fail "Response model not set"
  fi
fi

# ── 5. Camera validation ──────────────────────────────────────────
log "Step 5: Camera ID validation"

if [ -f "$PROD_PY" ]; then
  if grep -q "VALID_CAMERAS" "$PROD_PY"; then
    pass "VALID_CAMERAS constant exists"
  else
    fail "VALID_CAMERAS missing"
  fi

  for cam in chase pov roof front; do
    if grep -q "\"$cam\"" "$PROD_PY"; then
      pass "Camera '$cam' in VALID_CAMERAS"
    else
      fail "Camera '$cam' missing"
    fi
  done

  if grep -q "camera_id not in VALID_CAMERAS" "$PROD_PY"; then
    pass "Validates camera_id against VALID_CAMERAS"
  else
    fail "Camera validation check missing"
  fi
fi

# ── 6. Idempotency ────────────────────────────────────────────────
log "Step 6: Idempotency for pending requests"

if [ -f "$PROD_PY" ]; then
  if grep -q "featured_camera_idempotent" "$PROD_PY"; then
    pass "Idempotency log marker exists"
  else
    fail "Idempotency path missing"
  fi
fi

# ── 7. Edge command broadcast ─────────────────────────────────────
log "Step 7: Edge command broadcast"

if [ -f "$PROD_PY" ]; then
  if grep -A 120 "async def set_featured_camera" "$PROD_PY" | grep -q "publish_edge_command"; then
    pass "Publishes edge command via publish_edge_command"
  else
    fail "Edge command publish missing"
  fi
fi

# ── 8. Command type ───────────────────────────────────────────────
log "Step 8: Command type"

if [ -f "$PROD_PY" ]; then
  if grep -A 120 "async def set_featured_camera" "$PROD_PY" | grep -q "set_active_camera"; then
    pass "Command type is set_active_camera"
  else
    fail "Command type not set_active_camera"
  fi
fi

# ── 9. Edge ACK endpoint ──────────────────────────────────────────
log "Step 9: Edge ACK endpoint"

if [ -f "$PROD_PY" ]; then
  if grep -q "edge/command-response" "$PROD_PY"; then
    pass "Edge command-response endpoint registered"
  else
    fail "Edge command-response endpoint missing"
  fi

  if grep -q "async def receive_edge_command_response" "$PROD_PY"; then
    pass "receive_edge_command_response handler exists"
  else
    fail "receive_edge_command_response handler missing"
  fi

  if grep -q "X-Truck-Token" "$PROD_PY"; then
    pass "Truck token auth required for ACK"
  else
    fail "Truck token auth missing"
  fi
fi

# ── 10. ACK wiring ────────────────────────────────────────────────
log "Step 10: ACK updates featured camera state"

if [ -f "$PROD_PY" ]; then
  if grep -q "Update featured camera state on set_active_camera ACK" "$PROD_PY"; then
    pass "ACK wiring section exists"
  else
    fail "ACK wiring missing"
  fi

  if grep -q 'get_featured_camera_state(event_id, vehicle_id)' "$PROD_PY"; then
    pass "ACK reads current featured state"
  else
    fail "ACK not reading featured state"
  fi

  if grep -q 'set_featured_camera_state(event_id, vehicle_id, featured_state)' "$PROD_PY"; then
    pass "ACK persists updated state"
  else
    fail "ACK not persisting state"
  fi
fi

# ── 11. ACK request_id correlation ────────────────────────────────
log "Step 11: ACK correlates by request_id"

if [ -f "$PROD_PY" ]; then
  if grep -q 'featured_state.get("request_id") == response.command_id' "$PROD_PY"; then
    pass "ACK correlates by request_id"
  else
    fail "ACK not correlating by request_id"
  fi
fi

# ── 12. Redis featured camera helpers ─────────────────────────────
log "Step 12: Redis featured camera helpers"

if [ -f "$REDIS_PY" ]; then
  if grep -q "async def set_featured_camera_state" "$REDIS_PY"; then
    pass "set_featured_camera_state function exists"
  else
    fail "set_featured_camera_state missing"
  fi

  if grep -q "async def get_featured_camera_state" "$REDIS_PY"; then
    pass "get_featured_camera_state function exists"
  else
    fail "get_featured_camera_state missing"
  fi

  if grep -q 'featured_camera:{event_id}:{vehicle_id}' "$REDIS_PY"; then
    pass "Redis key pattern correct"
  else
    fail "Redis key pattern missing"
  fi
else
  fail "redis_client.py not found"
fi

# ── 13. Redis edge command helpers ─────────────────────────────────
log "Step 13: Redis edge command helpers"

if [ -f "$REDIS_PY" ]; then
  for fn in set_edge_command get_edge_command publish_edge_command; do
    if grep -q "async def $fn" "$REDIS_PY"; then
      pass "$fn function exists"
    else
      fail "$fn missing"
    fi
  done
fi

# ── 14. GET stream-states endpoint ─────────────────────────────────
log "Step 14: GET stream-states endpoint"

if [ -f "$PROD_PY" ]; then
  if grep -q "stream-states" "$PROD_PY"; then
    pass "stream-states endpoint registered"
  else
    fail "stream-states endpoint missing"
  fi

  if grep -q "RacerStreamStateList" "$PROD_PY"; then
    pass "RacerStreamStateList response model exists"
  else
    fail "RacerStreamStateList missing"
  fi
fi

# ── 15. Auto-timeout on GET ───────────────────────────────────────
log "Step 15: Auto-timeout on GET"

if [ -f "$PROD_PY" ]; then
  if grep -A 30 "async def get_featured_camera" "$PROD_PY" | grep -q "timeout_at"; then
    pass "GET checks timeout_at"
  else
    fail "GET missing timeout_at check"
  fi

  if grep -A 30 "async def get_featured_camera" "$PROD_PY" | grep -q '"timeout"'; then
    pass "Status set to timeout when past deadline"
  else
    fail "Timeout status not set"
  fi
fi

# ── 16. Timeout constant ──────────────────────────────────────────
log "Step 16: Timeout constant"

if [ -f "$PROD_PY" ]; then
  if grep -q "FEATURED_CAMERA_TIMEOUT_S" "$PROD_PY"; then
    pass "FEATURED_CAMERA_TIMEOUT_S constant defined"
  else
    fail "FEATURED_CAMERA_TIMEOUT_S missing"
  fi
fi

# ── 17. Broadcast state ───────────────────────────────────────────
log "Step 17: Broadcast state updated for fans"

if [ -f "$PROD_PY" ]; then
  if grep -A 130 "async def set_featured_camera" "$PROD_PY" | grep -q "featured_vehicle_id"; then
    pass "Broadcast includes featured_vehicle_id"
  else
    fail "Broadcast missing featured_vehicle_id"
  fi
fi

# ── 18. Python syntax: production.py ───────────────────────────────
log "Step 18: Python syntax (production.py)"

if python3 -c "import py_compile; py_compile.compile('$PROD_PY', doraise=True)" 2>/dev/null; then
  pass "production.py syntax valid"
else
  fail "production.py syntax error"
fi

# ── 19. Python syntax: redis_client.py ─────────────────────────────
log "Step 19: Python syntax (redis_client.py)"

if python3 -c "import py_compile; py_compile.compile('$REDIS_PY', doraise=True)" 2>/dev/null; then
  pass "redis_client.py syntax valid"
else
  fail "redis_client.py syntax error"
fi

# ── 20. Module-level logger ────────────────────────────────────────
log "Step 20: Module-level logger"

if [ -f "$PROD_PY" ]; then
  # Logger should be at module level (first 40 lines), not only inside functions
  if head -40 "$PROD_PY" | grep -q "logger = structlog.get_logger()"; then
    pass "Module-level logger defined"
  else
    fail "Module-level logger missing (was local-only bug)"
  fi

  if head -40 "$PROD_PY" | grep -q "import structlog"; then
    pass "structlog imported at module level"
  else
    fail "structlog not imported at module level"
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
