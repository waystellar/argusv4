#!/usr/bin/env bash
# pit_cameras_state_smoke.sh — Smoke test for Cameras Tab Stream Control (PIT-4)
#
# Validates:
#   1. Live badge driven by streaming status (not production camera)
#   2. streamingStatus.status checked for 'live' in isLive computation
#   3. streamingStatus.camera checked for matching camera in isLive
#   4. Dropdown has onchange handler
#   5. handleCameraSelectChange JS function exists
#   6. Switch-camera API call in handleCameraSelectChange
#   7. updateStreamingUI triggers updateCameraDisplay
#   8. Stream status badge updates from streamingStatus
#   9. Start/stop stream functions exist
#  10. Backend switch-camera endpoint registered
#  11. Backend switch_camera method exists
#  12. Backend get_streaming_status checks FFmpeg process
#  13. No false isLive based on currentCamera alone
#  14. Python syntax check
#
# Usage:
#   bash scripts/pit_cameras_state_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[pit-cameras] $*"; }
pass() { echo "[pit-cameras]   PASS: $*"; }
fail() { echo "[pit-cameras]   FAIL: $*"; FAIL=1; }
warn() { echo "[pit-cameras]   WARN: $*"; }

# ── 1. Live badge uses streaming status ──────────────────────────
log "Step 1: Live badge driven by streaming status"

if [ -f "$DASHBOARD" ]; then
  if grep -q "streamingStatus.status === 'live'" "$DASHBOARD"; then
    pass "isLive checks streamingStatus.status === 'live'"
  else
    fail "isLive does not check streaming status"
  fi

  if grep -q "streamingStatus.camera === cam" "$DASHBOARD"; then
    pass "isLive checks streamingStatus.camera === cam"
  else
    fail "isLive does not check streaming camera"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. No false Live from currentCamera ─────────────────────────
log "Step 2: No false Live from currentCamera alone"

if [ -f "$DASHBOARD" ]; then
  if grep -q "const isLive = currentCamera === cam" "$DASHBOARD"; then
    fail "isLive still based on currentCamera (false Live bug)"
  else
    pass "isLive not based on currentCamera alone"
  fi
fi

# ── 3. Dropdown has onchange handler ────────────────────────────
log "Step 3: Dropdown onchange"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'streamCameraSelect.*onchange' "$DASHBOARD"; then
    pass "streamCameraSelect has onchange handler"
  else
    fail "streamCameraSelect missing onchange handler"
  fi

  if grep -q 'handleCameraSelectChange' "$DASHBOARD"; then
    pass "handleCameraSelectChange function exists"
  else
    fail "handleCameraSelectChange function missing"
  fi
fi

# ── 4. Camera switch calls API ──────────────────────────────────
log "Step 4: Camera switch API integration"

if [ -f "$DASHBOARD" ]; then
  if grep -q "api/streaming/switch-camera" "$DASHBOARD"; then
    pass "JS calls /api/streaming/switch-camera"
  else
    fail "JS missing switch-camera API call"
  fi

  # Only switches when streaming
  if grep -q "streamingStatus.status === 'live'" "$DASHBOARD" && grep -q "streamingStatus.status === 'starting'" "$DASHBOARD"; then
    pass "Camera switch only triggers when streaming"
  else
    fail "Camera switch not gated on streaming status"
  fi
fi

# ── 5. updateStreamingUI refreshes camera display ───────────────
log "Step 5: Streaming UI updates camera display"

if [ -f "$DASHBOARD" ]; then
  if grep -q "updateCameraDisplay()" "$DASHBOARD"; then
    pass "updateCameraDisplay function called"
  else
    fail "updateCameraDisplay not called"
  fi

  # Specifically in updateStreamingUI
  if grep -A 110 'function updateStreamingUI' "$DASHBOARD" | grep -q 'updateCameraDisplay'; then
    pass "updateStreamingUI calls updateCameraDisplay"
  else
    fail "updateStreamingUI does not call updateCameraDisplay"
  fi
fi

# ── 6. Stream status badge ──────────────────────────────────────
log "Step 6: Stream status badge"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'id="streamStatusBadge"' "$DASHBOARD"; then
    pass "streamStatusBadge element exists"
  else
    fail "streamStatusBadge missing"
  fi

  if grep -q "streamingStatus.status.toUpperCase()" "$DASHBOARD"; then
    pass "Badge text from streamingStatus"
  else
    fail "Badge text not from streamingStatus"
  fi
fi

# ── 7. Start/stop stream functions ──────────────────────────────
log "Step 7: Stream control functions"

if [ -f "$DASHBOARD" ]; then
  if grep -q 'async function startStream' "$DASHBOARD"; then
    pass "startStream function exists"
  else
    fail "startStream missing"
  fi

  if grep -q 'async function stopStream' "$DASHBOARD"; then
    pass "stopStream function exists"
  else
    fail "stopStream missing"
  fi

  if grep -q "api/streaming/start" "$DASHBOARD"; then
    pass "startStream calls /api/streaming/start"
  else
    fail "Missing streaming start API call"
  fi

  if grep -q "api/streaming/stop" "$DASHBOARD"; then
    pass "stopStream calls /api/streaming/stop"
  else
    fail "Missing streaming stop API call"
  fi
fi

# ── 8. Backend endpoints ────────────────────────────────────────
log "Step 8: Backend streaming endpoints"

if [ -f "$DASHBOARD" ]; then
  if grep -q "api/streaming/status.*handle_streaming_status" "$DASHBOARD"; then
    pass "Streaming status endpoint registered"
  else
    fail "Streaming status endpoint missing"
  fi

  if grep -q "api/streaming/start.*handle_streaming_start" "$DASHBOARD"; then
    pass "Streaming start endpoint registered"
  else
    fail "Streaming start endpoint missing"
  fi

  if grep -q "api/streaming/stop.*handle_streaming_stop" "$DASHBOARD"; then
    pass "Streaming stop endpoint registered"
  else
    fail "Streaming stop endpoint missing"
  fi

  if grep -q "api/streaming/switch-camera.*handle_streaming_switch_camera" "$DASHBOARD"; then
    pass "Switch camera endpoint registered"
  else
    fail "Switch camera endpoint missing"
  fi
fi

# ── 9. Backend streaming state model ────────────────────────────
log "Step 9: Backend streaming state"

if [ -f "$DASHBOARD" ]; then
  if grep -q "_streaming_state" "$DASHBOARD"; then
    pass "_streaming_state dict exists"
  else
    fail "_streaming_state missing"
  fi

  if grep -q "'status': 'idle'" "$DASHBOARD"; then
    pass "Default streaming status is idle"
  else
    fail "Default streaming status not idle"
  fi

  if grep -q "def get_streaming_status" "$DASHBOARD"; then
    pass "get_streaming_status method exists"
  else
    fail "get_streaming_status missing"
  fi

  if grep -q "async def switch_camera" "$DASHBOARD"; then
    pass "switch_camera method exists"
  else
    fail "switch_camera missing"
  fi
fi

# ── 10. Camera live badges in HTML ──────────────────────────────
log "Step 10: Camera live badge elements"

if [ -f "$DASHBOARD" ]; then
  for cam in chase pov roof front; do
    if grep -q "id=\"${cam}-live-badge\"" "$DASHBOARD"; then
      pass "${cam}-live-badge element exists"
    else
      fail "${cam}-live-badge element missing"
    fi
  done
fi

# ── 11. Streaming status polling ────────────────────────────────
log "Step 11: Streaming status polling"

if [ -f "$DASHBOARD" ]; then
  if grep -q "pollStreamingStatus" "$DASHBOARD"; then
    pass "Streaming status polling exists"
  else
    fail "Streaming status polling missing"
  fi

  if grep -q "api/streaming/status" "$DASHBOARD"; then
    pass "Polls /api/streaming/status"
  else
    fail "Not polling streaming status endpoint"
  fi
fi

# ── 12. FFmpeg process check in status ──────────────────────────
log "Step 12: FFmpeg process monitoring"

if [ -f "$DASHBOARD" ]; then
  if grep -q "_ffmpeg_process" "$DASHBOARD"; then
    pass "FFmpeg process tracking exists"
  else
    fail "FFmpeg process tracking missing"
  fi

  if grep -q "poll_result" "$DASHBOARD" && grep -q "_ffmpeg_process.poll()" "$DASHBOARD"; then
    pass "FFmpeg process exit detection"
  else
    fail "FFmpeg exit detection missing"
  fi
fi

# ── 13. Python syntax check ─────────────────────────────────────
log "Step 13: Python syntax"

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
