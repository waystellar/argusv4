#!/usr/bin/env bash
# prod_feature_api_smoke.sh — Smoke test for PROD-1: Featured Camera State Machine
#
# Validates (source-level):
#   1. Redis helpers: set_featured_camera_state / get_featured_camera_state
#   2. FeaturedCameraRequest / FeaturedCameraResponse / FeaturedCameraState schemas
#   3. POST endpoint registered at /featured-camera (202)
#   4. GET endpoint registered at /featured-camera
#   5. Camera validation against VALID_CAMERAS
#   6. Vehicle existence check
#   7. Idempotency: pending+same camera returns existing request_id
#   8. Request ID format (fc_<hex>)
#   9. Edge command published via publish_edge_command
#  10. Broadcast state updated for fans
#  11. Auto-timeout on GET when past deadline
#  12. ACK wiring: featured_camera_state updated on set_active_camera ACK
#  13. ACK success path sets active_camera + status=success
#  14. ACK failure path sets status=failed + last_error
#  15. FEATURED_CAMERA_TIMEOUT_S constant defined
#  16. Python syntax check for production.py
#  17. Python syntax check for redis_client.py
#
# Usage:
#   bash scripts/prod_feature_api_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
REDIS_PY="$REPO_ROOT/cloud/app/redis_client.py"
FAIL=0

log()  { echo "[prod-featured] $*"; }
pass() { echo "[prod-featured]   PASS: $*"; }
fail() { echo "[prod-featured]   FAIL: $*"; FAIL=1; }

# ── 1. Redis helpers ──────────────────────────────────────────
log "Step 1: Redis featured camera helpers"

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

  if grep -q 'json.dumps(state)' "$REDIS_PY"; then
    pass "State serialized with json.dumps"
  else
    fail "State serialization missing"
  fi

  if grep -q 'json.loads(data)' "$REDIS_PY"; then
    pass "State deserialized with json.loads"
  else
    fail "State deserialization missing"
  fi
else
  fail "redis_client.py not found"
fi

# ── 2. Pydantic schemas ──────────────────────────────────────
log "Step 2: Featured camera schemas"

if [ -f "$PROD_PY" ]; then
  if grep -q "class FeaturedCameraRequest" "$PROD_PY"; then
    pass "FeaturedCameraRequest schema exists"
  else
    fail "FeaturedCameraRequest missing"
  fi

  if grep -q "class FeaturedCameraResponse" "$PROD_PY"; then
    pass "FeaturedCameraResponse schema exists"
  else
    fail "FeaturedCameraResponse missing"
  fi

  if grep -q "class FeaturedCameraState" "$PROD_PY"; then
    pass "FeaturedCameraState schema exists"
  else
    fail "FeaturedCameraState missing"
  fi

  # Response fields
  if grep -q "request_id: str" "$PROD_PY"; then
    pass "request_id field in response"
  else
    fail "request_id field missing"
  fi

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
else
  fail "production.py not found"
fi

# ── 3. POST endpoint ─────────────────────────────────────────
log "Step 3: POST featured-camera endpoint"

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

  if grep -q "async def set_featured_camera" "$PROD_PY"; then
    pass "set_featured_camera handler exists"
  else
    fail "set_featured_camera handler missing"
  fi

  if grep -q "FeaturedCameraRequest" "$PROD_PY" && grep -q "data: FeaturedCameraRequest" "$PROD_PY"; then
    pass "Handler accepts FeaturedCameraRequest body"
  else
    fail "Handler not accepting FeaturedCameraRequest"
  fi

  if grep -q "response_model=FeaturedCameraResponse" "$PROD_PY"; then
    pass "Response model is FeaturedCameraResponse"
  else
    fail "Response model not set"
  fi
fi

# ── 4. GET endpoint ───────────────────────────────────────────
log "Step 4: GET featured-camera endpoint"

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

# ── 5. Camera validation ─────────────────────────────────────
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
      fail "Camera '$cam' missing from VALID_CAMERAS"
    fi
  done

  if grep -q "camera_id not in VALID_CAMERAS" "$PROD_PY"; then
    pass "Validates camera_id against VALID_CAMERAS"
  else
    fail "Camera validation check missing"
  fi
fi

# ── 6. Vehicle existence check ────────────────────────────────
log "Step 6: Vehicle existence check"

if [ -f "$PROD_PY" ]; then
  if grep -A 50 "async def set_featured_camera" "$PROD_PY" | grep -q "Vehicle not found"; then
    pass "Returns 404 if vehicle not in event"
  else
    fail "Vehicle existence check missing"
  fi
fi

# ── 7. Idempotency ───────────────────────────────────────────
log "Step 7: Idempotency for pending requests"

if [ -f "$PROD_PY" ]; then
  if grep -q "featured_camera_idempotent" "$PROD_PY"; then
    pass "Idempotency log marker exists"
  else
    fail "Idempotency path missing"
  fi

  if grep -A 5 'status.*pending' "$PROD_PY" | grep -q 'desired_camera.*camera_id'; then
    pass "Idempotency checks pending + same camera"
  else
    fail "Idempotency condition missing"
  fi
fi

# ── 8. Request ID format ─────────────────────────────────────
log "Step 8: Request ID format"

if [ -f "$PROD_PY" ]; then
  if grep -q 'fc_.*uuid' "$PROD_PY"; then
    pass "Request ID uses fc_ prefix with uuid"
  else
    fail "Request ID format missing"
  fi
fi

# ── 9. Edge command published ─────────────────────────────────
log "Step 9: Edge command published"

if [ -f "$PROD_PY" ]; then
  if grep -A 120 "async def set_featured_camera" "$PROD_PY" | grep -q "publish_edge_command"; then
    pass "Publishes edge command via publish_edge_command"
  else
    fail "Edge command publish missing"
  fi

  if grep -A 120 "async def set_featured_camera" "$PROD_PY" | grep -q "set_active_camera"; then
    pass "Command type is set_active_camera"
  else
    fail "Command type not set_active_camera"
  fi

  if grep -A 120 "async def set_featured_camera" "$PROD_PY" | grep -q "set_edge_command"; then
    pass "Command stored for correlation via set_edge_command"
  else
    fail "Command not stored for correlation"
  fi
fi

# ── 10. Broadcast state updated ───────────────────────────────
log "Step 10: Broadcast state for fans"

if [ -f "$PROD_PY" ]; then
  if grep -A 130 "async def set_featured_camera" "$PROD_PY" | grep -q "broadcast:"; then
    pass "Broadcast state updated for fans"
  else
    fail "Broadcast state not updated"
  fi

  if grep -A 130 "async def set_featured_camera" "$PROD_PY" | grep -q "featured_vehicle_id"; then
    pass "Broadcast includes featured_vehicle_id"
  else
    fail "Broadcast missing featured_vehicle_id"
  fi
fi

# ── 11. Auto-timeout ─────────────────────────────────────────
log "Step 11: Auto-timeout on GET"

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

  if grep -q "Edge did not respond within timeout" "$PROD_PY"; then
    pass "Timeout error message set"
  else
    fail "Timeout error message missing"
  fi
fi

# ── 12. ACK wiring ───────────────────────────────────────────
log "Step 12: ACK ingestion updates featured camera state"

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

  if grep -q 'featured_state.get("request_id") == response.command_id' "$PROD_PY"; then
    pass "ACK correlates by request_id"
  else
    fail "ACK not correlating by request_id"
  fi

  if grep -q 'set_featured_camera_state(event_id, vehicle_id, featured_state)' "$PROD_PY"; then
    pass "ACK persists updated state"
  else
    fail "ACK not persisting state"
  fi
fi

# ── 13. ACK success path ─────────────────────────────────────
log "Step 13: ACK success path"

if [ -f "$PROD_PY" ]; then
  if grep -A 20 "Update featured camera state" "$PROD_PY" | grep -q '"success"'; then
    pass "ACK sets status=success on success"
  else
    fail "ACK success status missing"
  fi

  if grep -A 20 "Update featured camera state" "$PROD_PY" | grep -q '"active_camera"'; then
    pass "ACK sets active_camera on success"
  else
    fail "ACK active_camera update missing"
  fi

  if grep -q "Featured camera switch confirmed" "$PROD_PY"; then
    pass "Success logging present"
  else
    fail "Success logging missing"
  fi
fi

# ── 14. ACK failure path ─────────────────────────────────────
log "Step 14: ACK failure path"

if [ -f "$PROD_PY" ]; then
  if grep -A 30 "Update featured camera state" "$PROD_PY" | grep -q '"failed"'; then
    pass "ACK sets status=failed on error"
  else
    fail "ACK failure status missing"
  fi

  if grep -A 30 "Update featured camera state" "$PROD_PY" | grep -q '"last_error"'; then
    pass "ACK sets last_error on failure"
  else
    fail "ACK last_error missing"
  fi

  if grep -q "Featured camera switch failed" "$PROD_PY"; then
    pass "Failure logging present"
  else
    fail "Failure logging missing"
  fi
fi

# ── 15. Timeout constant ─────────────────────────────────────
log "Step 15: Timeout constant"

if [ -f "$PROD_PY" ]; then
  if grep -q "FEATURED_CAMERA_TIMEOUT_S" "$PROD_PY"; then
    pass "FEATURED_CAMERA_TIMEOUT_S constant defined"
  else
    fail "FEATURED_CAMERA_TIMEOUT_S missing"
  fi

  if grep -q "FEATURED_CAMERA_TIMEOUT_S = 15" "$PROD_PY"; then
    pass "Timeout is 15 seconds"
  else
    fail "Timeout not 15 seconds"
  fi
fi

# ── 16. Python syntax: production.py ──────────────────────────
log "Step 16: Python syntax (production.py)"

if python3 -c "import py_compile; py_compile.compile('$PROD_PY', doraise=True)" 2>/dev/null; then
  pass "production.py syntax valid"
else
  fail "production.py syntax error"
fi

# ── 17. Python syntax: redis_client.py ────────────────────────
log "Step 17: Python syntax (redis_client.py)"

if python3 -c "import py_compile; py_compile.compile('$REDIS_PY', doraise=True)" 2>/dev/null; then
  pass "redis_client.py syntax valid"
else
  fail "redis_client.py syntax error"
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
