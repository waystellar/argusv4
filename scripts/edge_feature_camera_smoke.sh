#!/usr/bin/env bash
# edge_feature_camera_smoke.sh — Smoke test for PROD-3: Edge Featured Camera Command Handler
#
# Validates (source-level):
#   1. Desired camera persistence: _get_desired_camera_path, _load_desired_camera, _save_desired_camera
#   2. Camera mappings loaded on startup: _load_camera_mappings
#   3. Desired camera loaded on init (reboot recovery)
#   4. Rate limiting: _last_camera_switch_at, _camera_switch_cooldown_s
#   5. set_active_camera validates camera_id against valid set
#   6. set_active_camera persists desired camera before switch
#   7. set_active_camera rate limits repeated switches
#   8. set_active_camera logs with [camera-switch] prefix
#   9. start_stream uses persisted desired camera
#  10. Cloud command handler logs with [edge-cmd] prefix
#  11. ACK sender logs with [edge-ack] prefix
#  12. SSE command listener exists
#  13. _send_command_response sends ACK to cloud
#  14. switch_camera restarts stream for camera change
#  15. desired_camera_state.json file referenced
#  16. camera_mappings.json loaded on startup
#  17. Python syntax check
#
# Usage:
#   bash scripts/edge_feature_camera_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[edge-feature-cam] $*"; }
pass() { echo "[edge-feature-cam]   PASS: $*"; }
fail() { echo "[edge-feature-cam]   FAIL: $*"; FAIL=1; }

# ── 1. Desired camera persistence methods ─────────────────────
log "Step 1: Desired camera persistence methods"

if [ -f "$DASHBOARD" ]; then
  if grep -q "def _get_desired_camera_path" "$DASHBOARD"; then
    pass "_get_desired_camera_path method exists"
  else
    fail "_get_desired_camera_path missing"
  fi

  if grep -q "def _load_desired_camera" "$DASHBOARD"; then
    pass "_load_desired_camera method exists"
  else
    fail "_load_desired_camera missing"
  fi

  if grep -q "def _save_desired_camera" "$DASHBOARD"; then
    pass "_save_desired_camera method exists"
  else
    fail "_save_desired_camera missing"
  fi

  if grep -q "desired_camera_state.json" "$DASHBOARD"; then
    pass "Persists to desired_camera_state.json"
  else
    fail "desired_camera_state.json reference missing"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. Camera mappings loaded on startup ──────────────────────
log "Step 2: Camera mappings loaded on startup"

if [ -f "$DASHBOARD" ]; then
  if grep -q "def _load_camera_mappings" "$DASHBOARD"; then
    pass "_load_camera_mappings method exists"
  else
    fail "_load_camera_mappings missing"
  fi

  if grep -q "self._load_camera_mappings()" "$DASHBOARD"; then
    pass "_load_camera_mappings called in __init__"
  else
    fail "_load_camera_mappings not called in __init__"
  fi

  if grep -A 15 "def _load_camera_mappings" "$DASHBOARD" | grep -q "camera_mappings.json"; then
    pass "_load_camera_mappings reads camera_mappings.json"
  else
    fail "_load_camera_mappings not reading camera_mappings.json"
  fi
fi

# ── 3. Desired camera loaded on init (reboot recovery) ────────
log "Step 3: Reboot recovery"

if [ -f "$DASHBOARD" ]; then
  if grep -q "self._load_desired_camera()" "$DASHBOARD"; then
    pass "_load_desired_camera called in __init__"
  else
    fail "_load_desired_camera not called in __init__"
  fi

  if grep -A 15 "def _load_desired_camera" "$DASHBOARD" | grep -q "_streaming_state\['camera'\]"; then
    pass "_load_desired_camera restores streaming_state camera"
  else
    fail "_load_desired_camera not restoring camera to streaming_state"
  fi

  # Validates camera value on load
  if grep -A 15 "def _load_desired_camera" "$DASHBOARD" | grep -q "chase.*pov.*roof.*front"; then
    pass "_load_desired_camera validates camera names"
  else
    fail "_load_desired_camera not validating camera names"
  fi
fi

# ── 4. Rate limiting ─────────────────────────────────────────
log "Step 4: Rate limiting"

if [ -f "$DASHBOARD" ]; then
  if grep -q "_last_camera_switch_at" "$DASHBOARD"; then
    pass "_last_camera_switch_at tracking variable exists"
  else
    fail "_last_camera_switch_at missing"
  fi

  if grep -q "_camera_switch_cooldown_s" "$DASHBOARD"; then
    pass "_camera_switch_cooldown_s constant exists"
  else
    fail "_camera_switch_cooldown_s missing"
  fi

  if grep -q "Rate limited" "$DASHBOARD"; then
    pass "Rate limit response message exists"
  else
    fail "Rate limit response missing"
  fi
fi

# ── 5. Camera validation in set_active_camera ─────────────────
log "Step 5: Camera ID validation"

if [ -f "$DASHBOARD" ]; then
  if grep -q "valid_cameras" "$DASHBOARD"; then
    pass "valid_cameras set defined in handler"
  else
    fail "valid_cameras missing"
  fi

  if grep -q "camera not in valid_cameras" "$DASHBOARD"; then
    pass "Camera validated against valid_cameras set"
  else
    fail "Camera validation check missing"
  fi
fi

# ── 6. Desired camera persisted before switch ─────────────────
log "Step 6: Desired camera persisted before switch"

if [ -f "$DASHBOARD" ]; then
  # _save_desired_camera called inside set_active_camera handler
  if grep -A 60 '"set_active_camera"' "$DASHBOARD" | grep -q "_save_desired_camera"; then
    pass "_save_desired_camera called in set_active_camera handler"
  else
    fail "_save_desired_camera not called in handler"
  fi
fi

# ── 7. Rate limiting applied ─────────────────────────────────
log "Step 7: Rate limit enforced in handler"

if [ -f "$DASHBOARD" ]; then
  if grep -A 60 '"set_active_camera"' "$DASHBOARD" | grep -q "_camera_switch_cooldown_s"; then
    pass "Cooldown checked in set_active_camera handler"
  else
    fail "Cooldown not checked in handler"
  fi

  if grep -A 60 '"set_active_camera"' "$DASHBOARD" | grep -q "_last_camera_switch_at"; then
    pass "Last switch time tracked in handler"
  else
    fail "Last switch time not tracked"
  fi
fi

# ── 8. Camera switch logging ─────────────────────────────────
log "Step 8: Camera switch diagnostics logging"

if [ -f "$DASHBOARD" ]; then
  if grep -q '\[camera-switch\].*Received' "$DASHBOARD"; then
    pass "[camera-switch] receive log exists"
  else
    fail "[camera-switch] receive log missing"
  fi

  if grep -q '\[camera-switch\].*Success' "$DASHBOARD"; then
    pass "[camera-switch] success log exists"
  else
    fail "[camera-switch] success log missing"
  fi

  if grep -q '\[camera-switch\].*Failed' "$DASHBOARD"; then
    pass "[camera-switch] failure log exists"
  else
    fail "[camera-switch] failure log missing"
  fi

  if grep -q '\[camera-switch\].*Rate limited' "$DASHBOARD"; then
    pass "[camera-switch] rate limit log exists"
  else
    fail "[camera-switch] rate limit log missing"
  fi
fi

# ── 9. Start stream uses desired camera ───────────────────────
log "Step 9: Start stream uses persisted camera"

if [ -f "$DASHBOARD" ]; then
  if grep -A 5 'command == "start_stream"' "$DASHBOARD" | grep -q "streaming_state.get.*camera"; then
    pass "start_stream uses persisted camera from streaming_state"
  else
    fail "start_stream not using persisted camera"
  fi

  if grep -q '\[stream-start\]' "$DASHBOARD"; then
    pass "[stream-start] log exists"
  else
    fail "[stream-start] log missing"
  fi
fi

# ── 10. Cloud command handler logging ─────────────────────────
log "Step 10: Cloud command handler diagnostics"

if [ -f "$DASHBOARD" ]; then
  if grep -q '\[edge-cmd\].*Received' "$DASHBOARD"; then
    pass "[edge-cmd] receive log exists"
  else
    fail "[edge-cmd] receive log missing"
  fi

  if grep -q '\[edge-cmd\].*Result' "$DASHBOARD"; then
    pass "[edge-cmd] result log exists"
  else
    fail "[edge-cmd] result log missing"
  fi
fi

# ── 11. ACK sender logging ───────────────────────────────────
log "Step 11: ACK sender diagnostics"

if [ -f "$DASHBOARD" ]; then
  if grep -q '\[edge-ack\].*ACK sent' "$DASHBOARD"; then
    pass "[edge-ack] send log exists"
  else
    fail "[edge-ack] send log missing"
  fi

  if grep -q '\[edge-ack\].*ACK failed' "$DASHBOARD"; then
    pass "[edge-ack] failure log exists"
  else
    fail "[edge-ack] failure log missing"
  fi
fi

# ── 12. SSE command listener exists ───────────────────────────
log "Step 12: SSE command listener"

if [ -f "$DASHBOARD" ]; then
  if grep -q "_cloud_command_listener" "$DASHBOARD"; then
    pass "SSE command listener method exists"
  else
    fail "SSE command listener missing"
  fi

  if grep -q "edge_command" "$DASHBOARD"; then
    pass "Filters for edge_command event type"
  else
    fail "edge_command filter missing"
  fi
fi

# ── 13. ACK sender sends to cloud ────────────────────────────
log "Step 13: ACK response to cloud"

if [ -f "$DASHBOARD" ]; then
  if grep -q "_send_command_response" "$DASHBOARD"; then
    pass "_send_command_response method exists"
  else
    fail "_send_command_response missing"
  fi

  if grep -q "edge/command-response" "$DASHBOARD"; then
    pass "ACK posts to edge/command-response endpoint"
  else
    fail "ACK endpoint missing"
  fi

  if grep -q '"command_id": command_id' "$DASHBOARD"; then
    pass "ACK includes command_id for correlation"
  else
    fail "ACK missing command_id"
  fi
fi

# ── 14. switch_camera restarts stream ─────────────────────────
log "Step 14: Camera switch mechanism"

if [ -f "$DASHBOARD" ]; then
  if grep -q "async def switch_camera" "$DASHBOARD"; then
    pass "switch_camera async method exists"
  else
    fail "switch_camera missing"
  fi

  if grep -A 15 "async def switch_camera" "$DASHBOARD" | grep -q "stop_streaming"; then
    pass "switch_camera stops stream before restart"
  else
    fail "switch_camera not stopping stream"
  fi

  if grep -A 15 "async def switch_camera" "$DASHBOARD" | grep -q "start_streaming"; then
    pass "switch_camera starts stream with new camera"
  else
    fail "switch_camera not starting stream"
  fi
fi

# ── 15. desired_camera_state.json persistence ─────────────────
log "Step 15: Desired camera state file"

if [ -f "$DASHBOARD" ]; then
  if grep -q "'desired_camera'" "$DASHBOARD"; then
    pass "desired_camera field in saved state"
  else
    fail "desired_camera field missing"
  fi

  if grep -A 10 "def _save_desired_camera" "$DASHBOARD" | grep -q "json.dump"; then
    pass "_save_desired_camera writes JSON"
  else
    fail "_save_desired_camera not writing JSON"
  fi
fi

# ── 16. Camera mappings loaded ────────────────────────────────
log "Step 16: Camera mappings loaded at startup"

if [ -f "$DASHBOARD" ]; then
  if grep -A 15 "def _load_camera_mappings" "$DASHBOARD" | grep -q "camera_mappings.json"; then
    pass "Loads from camera_mappings.json"
  else
    fail "Not loading camera_mappings.json"
  fi

  for role in chase pov roof front; do
    if grep -A 15 "def _load_camera_mappings" "$DASHBOARD" | grep -q "'$role'"; then
      pass "Loads $role camera mapping"
    else
      fail "$role camera mapping not loaded"
    fi
  done
fi

# ── 17. Python syntax check ──────────────────────────────────
log "Step 17: Python syntax"

if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "Python syntax valid"
else
  fail "Python syntax error"
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
