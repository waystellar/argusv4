#!/usr/bin/env bash
# edge_program_state_smoke.sh - Smoke test for EDGE-PROG-3: Program State
#
# Validates (source-level):
#   1. Edge: GET /api/program/status endpoint registered
#   2. Edge: POST /api/program/switch endpoint registered
#   3. Edge: pit_crew_dashboard.py has _program_state dict
#   4. Edge: pit_crew_dashboard.py has _load_program_state function
#   5. Edge: pit_crew_dashboard.py has _save_program_state function
#   6. Edge: pit_crew_dashboard.py has _update_program_state function
#   7. Edge: video_director.py (v4) has _update_program_state_file function
#   8. Edge: video_director.py (v3) has _update_program_state_file function
#   9. UI: pollStreamingStatus uses /api/program/status
#  10. UI: handleCameraSelectChange uses /api/program/switch
#  11. Python syntax check on pit_crew_dashboard.py
#  12. Python syntax check on v4 video_director.py
#  13. Python syntax check on v3 video_director.py
#
# Usage:
#   bash scripts/edge_program_state_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Edge paths
PIT_CREW_PY="$REPO_ROOT/edge/pit_crew_dashboard.py"
VIDEO_DIRECTOR_V4="$REPO_ROOT/edge/video_director.py"
VIDEO_DIRECTOR_V3="${REPO_ROOT}/../argus_timing_v3/edge/video_director.py"

FAIL=0

log()  { echo "[edge-prog-state]  $*"; }
pass() { echo "[edge-prog-state]    PASS: $*"; }
fail() { echo "[edge-prog-state]    FAIL: $*"; FAIL=1; }

# ── 1. GET /api/program/status endpoint registered ───────────
log "Step 1: GET /api/program/status endpoint registered"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "add_get.*'/api/program/status'" "$PIT_CREW_PY"; then
    pass "GET /api/program/status route registered"
  else
    fail "GET /api/program/status route NOT registered"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. POST /api/program/switch endpoint registered ──────────
log "Step 2: POST /api/program/switch endpoint registered"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "add_post.*'/api/program/switch'" "$PIT_CREW_PY"; then
    pass "POST /api/program/switch route registered"
  else
    fail "POST /api/program/switch route NOT registered"
  fi
fi

# ── 3. _program_state dict exists ────────────────────────────
log "Step 3: _program_state dict exists in pit_crew_dashboard.py"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "self._program_state" "$PIT_CREW_PY"; then
    pass "_program_state dict exists"
  else
    fail "_program_state dict NOT found"
  fi
fi

# ── 4. _load_program_state function exists ───────────────────
log "Step 4: _load_program_state function exists"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "def _load_program_state" "$PIT_CREW_PY"; then
    pass "_load_program_state function exists"
  else
    fail "_load_program_state function NOT found"
  fi
fi

# ── 5. _save_program_state function exists ───────────────────
log "Step 5: _save_program_state function exists"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "def _save_program_state" "$PIT_CREW_PY"; then
    pass "_save_program_state function exists"
  else
    fail "_save_program_state function NOT found"
  fi
fi

# ── 6. _update_program_state function exists ─────────────────
log "Step 6: _update_program_state function exists"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "def _update_program_state" "$PIT_CREW_PY"; then
    pass "_update_program_state function exists"
  else
    fail "_update_program_state function NOT found"
  fi
fi

# ── 7. video_director.py (v4) has _update_program_state_file ─
log "Step 7: video_director.py (v4) has _update_program_state_file"

if [ -f "$VIDEO_DIRECTOR_V4" ]; then
  if grep -q "def _update_program_state_file" "$VIDEO_DIRECTOR_V4"; then
    pass "v4 video_director has _update_program_state_file"
  else
    fail "v4 video_director MISSING _update_program_state_file"
  fi
else
  fail "v4 video_director.py not found"
fi

# ── 8. video_director.py (v3) has _update_program_state_file ─
log "Step 8: video_director.py (v3) has _update_program_state_file"

if [ -f "$VIDEO_DIRECTOR_V3" ]; then
  if grep -q "def _update_program_state_file" "$VIDEO_DIRECTOR_V3"; then
    pass "v3 video_director has _update_program_state_file"
  else
    fail "v3 video_director MISSING _update_program_state_file"
  fi
else
  log "SKIP: v3 video_director.py not found (optional)"
fi

# ── 9. UI uses /api/program/status ───────────────────────────
log "Step 9: UI pollStreamingStatus uses /api/program/status"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "fetch.*'/api/program/status'" "$PIT_CREW_PY"; then
    pass "UI polls /api/program/status"
  else
    fail "UI does NOT poll /api/program/status"
  fi
fi

# ── 10. UI uses /api/program/switch ──────────────────────────
log "Step 10: UI handleCameraSelectChange uses /api/program/switch"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "fetch.*'/api/program/switch'" "$PIT_CREW_PY"; then
    pass "UI uses /api/program/switch for camera changes"
  else
    fail "UI does NOT use /api/program/switch"
  fi
fi

# ── 11. Python syntax check on pit_crew_dashboard.py ─────────
log "Step 11: Python syntax check on pit_crew_dashboard.py"

if python3 -c "import py_compile; py_compile.compile('$PIT_CREW_PY', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py syntax valid"
else
  fail "pit_crew_dashboard.py syntax ERROR"
fi

# ── 12. Python syntax check on v4 video_director.py ──────────
log "Step 12: Python syntax check on v4 video_director.py"

if [ -f "$VIDEO_DIRECTOR_V4" ]; then
  if python3 -c "import py_compile; py_compile.compile('$VIDEO_DIRECTOR_V4', doraise=True)" 2>/dev/null; then
    pass "v4 video_director.py syntax valid"
  else
    fail "v4 video_director.py syntax ERROR"
  fi
fi

# ── 13. Python syntax check on v3 video_director.py ──────────
log "Step 13: Python syntax check on v3 video_director.py"

if [ -f "$VIDEO_DIRECTOR_V3" ]; then
  if python3 -c "import py_compile; py_compile.compile('$VIDEO_DIRECTOR_V3', doraise=True)" 2>/dev/null; then
    pass "v3 video_director.py syntax valid"
  else
    fail "v3 video_director.py syntax ERROR"
  fi
else
  log "SKIP: v3 video_director.py not found (optional)"
fi

# ── 14. PROGRAM_STATE_FILE constant in video_director (v4) ───
log "Step 14: PROGRAM_STATE_FILE constant defined in v4"

if [ -f "$VIDEO_DIRECTOR_V4" ]; then
  if grep -q "PROGRAM_STATE_FILE" "$VIDEO_DIRECTOR_V4"; then
    pass "PROGRAM_STATE_FILE constant defined in v4"
  else
    fail "PROGRAM_STATE_FILE constant NOT found in v4"
  fi
fi

# ── 15. handle_program_status function exists ────────────────
log "Step 15: handle_program_status handler exists"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "async def handle_program_status" "$PIT_CREW_PY"; then
    pass "handle_program_status handler exists"
  else
    fail "handle_program_status handler NOT found"
  fi
fi

# ── 16. handle_program_switch function exists ────────────────
log "Step 16: handle_program_switch handler exists"

if [ -f "$PIT_CREW_PY" ]; then
  if grep -q "async def handle_program_switch" "$PIT_CREW_PY"; then
    pass "handle_program_switch handler exists"
  else
    fail "handle_program_switch handler NOT found"
  fi
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
