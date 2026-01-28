#!/usr/bin/env bash
# prod_feature_camera_e2e_smoke.sh — Integration smoke: Cloud + Web + Edge contract
#
# Proves the full featured-camera contract is implemented across all three layers
# without needing a real truck online.
#
# Steps:
#   1. Web build (npm run build) — if node available
#   2. Cloud smoke (prod_feature_camera_cloud_smoke.sh)
#   3. UI smoke (prod_feature_camera_ui_smoke.sh)
#   4. Edge smoke (edge_feature_camera_smoke.sh)
#   5. Cross-layer contract: command schema string in both cloud and edge
#   6. Cross-layer contract: ACK endpoint exists in cloud, called by edge
#
# Usage:
#   bash scripts/prod_feature_camera_e2e_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

PREFIX="[e2e-contract]"
log()  { echo "$PREFIX $*"; }
pass() { echo "$PREFIX   PASS: $*"; }
fail() { echo "$PREFIX   FAIL: $*"; FAIL=1; }
warn() { echo "$PREFIX   WARN: $*"; }

# ── Step 1: Web build ───────────────────────────────────────────────
log "Step 1: Web build (npm run build)"

if command -v node >/dev/null 2>&1; then
  if [ -f "$REPO_ROOT/web/package.json" ]; then
    if (cd "$REPO_ROOT/web" && npm run build 2>&1); then
      pass "Web build succeeded"
    else
      fail "Web build failed"
    fi
  else
    fail "web/package.json not found"
  fi
else
  warn "Node.js not available — skipping web build (source-level checks substitute)"
fi

echo ""

# ── Step 2: Cloud smoke ─────────────────────────────────────────────
log "Step 2: Cloud smoke test"

if [ -f "$SCRIPT_DIR/prod_feature_camera_cloud_smoke.sh" ]; then
  if bash "$SCRIPT_DIR/prod_feature_camera_cloud_smoke.sh" 2>&1; then
    pass "Cloud smoke passed"
  else
    fail "Cloud smoke failed"
  fi
else
  fail "prod_feature_camera_cloud_smoke.sh not found"
fi

echo ""

# ── Step 3: UI smoke ────────────────────────────────────────────────
log "Step 3: UI smoke test"

if [ -f "$SCRIPT_DIR/prod_feature_camera_ui_smoke.sh" ]; then
  if bash "$SCRIPT_DIR/prod_feature_camera_ui_smoke.sh" 2>&1; then
    pass "UI smoke passed"
  else
    fail "UI smoke failed"
  fi
else
  fail "prod_feature_camera_ui_smoke.sh not found"
fi

echo ""

# ── Step 4: Edge smoke ──────────────────────────────────────────────
log "Step 4: Edge smoke test"

if [ -f "$SCRIPT_DIR/edge_feature_camera_smoke.sh" ]; then
  if bash "$SCRIPT_DIR/edge_feature_camera_smoke.sh" 2>&1; then
    pass "Edge smoke passed"
  else
    fail "Edge smoke failed"
  fi
else
  fail "edge_feature_camera_smoke.sh not found"
fi

echo ""

# ── Step 5: Cross-layer contract — command schema ────────────────────
log "Step 5: Command schema contract (cloud ↔ edge)"

PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
EDGE_PY="$REPO_ROOT/edge/pit_crew_dashboard.py"

# 5a: "set_active_camera" command type in both layers
if [ -f "$PROD_PY" ] && [ -f "$EDGE_PY" ]; then
  CLOUD_HAS=$(grep -c "set_active_camera" "$PROD_PY" || true)
  EDGE_HAS=$(grep -c "set_active_camera" "$EDGE_PY" || true)

  if [ "$CLOUD_HAS" -ge 1 ] && [ "$EDGE_HAS" -ge 1 ]; then
    pass "set_active_camera command type in both cloud ($CLOUD_HAS refs) and edge ($EDGE_HAS refs)"
  else
    fail "set_active_camera missing: cloud=$CLOUD_HAS, edge=$EDGE_HAS"
  fi
else
  [ ! -f "$PROD_PY" ] && fail "production.py not found"
  [ ! -f "$EDGE_PY" ] && fail "pit_crew_dashboard.py not found"
fi

# 5b: "camera_id" / "camera" param in both layers
if [ -f "$PROD_PY" ] && [ -f "$EDGE_PY" ]; then
  if grep -q "camera_id" "$PROD_PY" && grep -q "camera" "$EDGE_PY"; then
    pass "Camera param exists in both cloud (camera_id) and edge (camera)"
  else
    fail "Camera param missing in one or both layers"
  fi
fi

# 5c: "request_id" / "command_id" correlation in both layers
if [ -f "$PROD_PY" ] && [ -f "$EDGE_PY" ]; then
  CLOUD_RID=$(grep -c "request_id" "$PROD_PY" || true)
  EDGE_CID=$(grep -c "command_id" "$EDGE_PY" || true)

  if [ "$CLOUD_RID" -ge 1 ] && [ "$EDGE_CID" -ge 1 ]; then
    pass "Correlation IDs: cloud uses request_id ($CLOUD_RID refs), edge uses command_id ($EDGE_CID refs)"
  else
    fail "Correlation ID missing: cloud request_id=$CLOUD_RID, edge command_id=$EDGE_CID"
  fi
fi

# 5d: Valid camera set matches between cloud and edge
if [ -f "$PROD_PY" ] && [ -f "$EDGE_PY" ]; then
  MATCH=true
  for cam in chase pov roof front; do
    if ! grep -q "\"$cam\"" "$PROD_PY"; then
      MATCH=false
      fail "Camera '$cam' missing from cloud VALID_CAMERAS"
    fi
    if ! grep -q "'$cam'" "$EDGE_PY"; then
      MATCH=false
      fail "Camera '$cam' missing from edge valid_cameras"
    fi
  done
  if [ "$MATCH" = true ]; then
    pass "Valid cameras {chase, pov, roof, front} match in both layers"
  fi
fi

echo ""

# ── Step 6: Cross-layer contract — ACK endpoint ─────────────────────
log "Step 6: ACK endpoint contract (edge → cloud)"

# 6a: Cloud defines the ACK endpoint
if [ -f "$PROD_PY" ]; then
  if grep -q "edge/command-response" "$PROD_PY"; then
    pass "Cloud registers edge/command-response endpoint"
  else
    fail "Cloud missing edge/command-response endpoint"
  fi

  if grep -q "async def receive_edge_command_response" "$PROD_PY"; then
    pass "Cloud has receive_edge_command_response handler"
  else
    fail "Cloud missing ACK handler"
  fi
fi

# 6b: Edge calls the ACK endpoint
if [ -f "$EDGE_PY" ]; then
  if grep -q "edge/command-response" "$EDGE_PY"; then
    pass "Edge posts to edge/command-response endpoint"
  else
    fail "Edge not calling ACK endpoint"
  fi

  if grep -q "_send_command_response" "$EDGE_PY"; then
    pass "Edge has _send_command_response method"
  else
    fail "Edge missing ACK sender"
  fi
fi

# 6c: ACK payload contract — both use command_id and status
if [ -f "$PROD_PY" ] && [ -f "$EDGE_PY" ]; then
  if grep -q "command_id" "$PROD_PY" && grep -q "command_id" "$EDGE_PY"; then
    pass "ACK payload: command_id in both cloud and edge"
  else
    fail "ACK payload: command_id mismatch"
  fi

  # Cloud checks for "success" status from edge
  if grep -A 50 "receive_edge_command_response" "$PROD_PY" | grep -q "status" && \
     grep -A 20 "_send_command_response" "$EDGE_PY" | grep -q "status"; then
    pass "ACK payload: status field in both cloud handler and edge sender"
  else
    fail "ACK payload: status field mismatch"
  fi
fi

# 6d: Auth contract — edge sends X-Truck-Token, cloud checks it
if [ -f "$PROD_PY" ] && [ -f "$EDGE_PY" ]; then
  if grep -q "X-Truck-Token" "$PROD_PY" && grep -q "X-Truck-Token" "$EDGE_PY"; then
    pass "Auth: X-Truck-Token header in both cloud and edge"
  else
    fail "Auth: X-Truck-Token mismatch"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "E2E CONTRACT SMOKE: ALL PASSED"
  exit 0
else
  log "E2E CONTRACT SMOKE: SOME CHECKS FAILED"
  exit 1
fi
