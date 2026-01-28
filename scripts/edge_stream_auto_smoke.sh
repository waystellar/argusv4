#!/usr/bin/env bash
# edge_stream_auto_smoke.sh — Smoke test for STREAM-4: Auto-Downshift Health Monitor
#
# Validates (source-level):
#   1. pit_crew_dashboard.py compiles
#   2. stream_profiles.py compiles
#   3. _stream_health dict initialized with expected keys
#   4. ffmpeg -progress pipe:1 flag added to command
#   5. _read_ffmpeg_progress method exists (parses speed=)
#   6. _is_stream_unhealthy method exists
#   7. AUTO_SPEED_THRESHOLD defined (0.90)
#   8. AUTO_UNHEALTHY_DURATION_S defined (20)
#   9. AUTO_HEALTHY_DURATION_S defined (120)
#  10. AUTO_RESTART_THRESHOLD defined (3)
#  11. _auto_downshift_loop method exists
#  12. _auto_downshift_loop registered as background task
#  13. _step_down_profile method exists
#  14. _step_up_profile method exists
#  15. auto_profile_ceiling tracked (manual sets ceiling)
#  16. _auto_apply_profile preserves auto_mode=True
#  17. get_stream_health_summary method exists
#  18. Health fields in GET /api/stream/profile response
#  19. current_speed field in health summary
#  20. recent_restarts field in health summary
#  21. last_error_summary field in health summary
#  22. Auto mode handler sets ceiling on enable
#  23. PROFILE_ORDER defined with 4 profiles
#
# Usage:
#   bash scripts/edge_stream_auto_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
SP="$REPO_ROOT/edge/stream_profiles.py"
FAIL=0

log()  { echo "[stream-auto]  $*"; }
pass() { echo "[stream-auto]    PASS: $*"; }
fail() { echo "[stream-auto]    FAIL: $*"; FAIL=1; }

# ── 1. py_compile dashboard ───────────────────────────────────
log "Step 1: pit_crew_dashboard.py compiles"

if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles"
else
  fail "pit_crew_dashboard.py syntax error"
fi

# ── 2. py_compile stream_profiles ─────────────────────────────
log "Step 2: stream_profiles.py compiles"

if python3 -c "import py_compile; py_compile.compile('$SP', doraise=True)" 2>/dev/null; then
  pass "stream_profiles.py compiles"
else
  fail "stream_profiles.py syntax error"
fi

# ── 3. _stream_health dict initialized ────────────────────────
log "Step 3: _stream_health dict initialized"

if grep -q "_stream_health" "$DASHBOARD"; then
  pass "_stream_health dict exists"
else
  fail "_stream_health missing"
fi

for key in "speed_samples" "restart_timestamps" "last_error_summary" "current_speed" "healthy_since" "auto_profile_ceiling"; do
  if grep -q "\"$key\"" "$DASHBOARD"; then
    pass "Health key '$key' present"
  else
    fail "Health key '$key' missing"
  fi
done

# ── 4. ffmpeg -progress pipe:1 ─────────────────────────────────
log "Step 4: ffmpeg -progress pipe:1 flag"

if grep -q '"-progress", "pipe:1"' "$DASHBOARD"; then
  pass "ffmpeg launched with -progress pipe:1"
else
  fail "-progress pipe:1 missing from ffmpeg launch"
fi

# ── 5. _read_ffmpeg_progress method ────────────────────────────
log "Step 5: _read_ffmpeg_progress method"

if grep -q "async def _read_ffmpeg_progress" "$DASHBOARD"; then
  pass "_read_ffmpeg_progress method exists"
else
  fail "_read_ffmpeg_progress missing"
fi

if grep -q 'speed=' "$DASHBOARD"; then
  pass "Parses speed= from ffmpeg output"
else
  fail "speed= parsing missing"
fi

# ── 6. _is_stream_unhealthy method ─────────────────────────────
log "Step 6: _is_stream_unhealthy method"

if grep -q "def _is_stream_unhealthy" "$DASHBOARD"; then
  pass "_is_stream_unhealthy method exists"
else
  fail "_is_stream_unhealthy missing"
fi

# ── 7. AUTO_SPEED_THRESHOLD ────────────────────────────────────
log "Step 7: AUTO_SPEED_THRESHOLD"

if grep -q "AUTO_SPEED_THRESHOLD = 0.90" "$DASHBOARD"; then
  pass "AUTO_SPEED_THRESHOLD = 0.90"
else
  fail "AUTO_SPEED_THRESHOLD not 0.90"
fi

# ── 8. AUTO_UNHEALTHY_DURATION_S ───────────────────────────────
log "Step 8: AUTO_UNHEALTHY_DURATION_S"

if grep -q "AUTO_UNHEALTHY_DURATION_S = 20" "$DASHBOARD"; then
  pass "AUTO_UNHEALTHY_DURATION_S = 20"
else
  fail "AUTO_UNHEALTHY_DURATION_S not 20"
fi

# ── 9. AUTO_HEALTHY_DURATION_S ─────────────────────────────────
log "Step 9: AUTO_HEALTHY_DURATION_S"

if grep -q "AUTO_HEALTHY_DURATION_S = 120" "$DASHBOARD"; then
  pass "AUTO_HEALTHY_DURATION_S = 120"
else
  fail "AUTO_HEALTHY_DURATION_S not 120"
fi

# ── 10. AUTO_RESTART_THRESHOLD ─────────────────────────────────
log "Step 10: AUTO_RESTART_THRESHOLD"

if grep -q "AUTO_RESTART_THRESHOLD = 3" "$DASHBOARD"; then
  pass "AUTO_RESTART_THRESHOLD = 3"
else
  fail "AUTO_RESTART_THRESHOLD not 3"
fi

# ── 11. _auto_downshift_loop method ────────────────────────────
log "Step 11: _auto_downshift_loop method"

if grep -q "async def _auto_downshift_loop" "$DASHBOARD"; then
  pass "_auto_downshift_loop method exists"
else
  fail "_auto_downshift_loop missing"
fi

# ── 12. Registered as background task ──────────────────────────
log "Step 12: _auto_downshift_loop in background tasks"

if grep -q "_auto_downshift_loop" "$DASHBOARD" && grep -q "create_task.*_auto_downshift_loop" "$DASHBOARD"; then
  pass "_auto_downshift_loop registered as background task"
else
  fail "_auto_downshift_loop not in background tasks"
fi

# ── 13. _step_down_profile method ──────────────────────────────
log "Step 13: _step_down_profile method"

if grep -q "def _step_down_profile" "$DASHBOARD"; then
  pass "_step_down_profile method exists"
else
  fail "_step_down_profile missing"
fi

# ── 14. _step_up_profile method ────────────────────────────────
log "Step 14: _step_up_profile method"

if grep -q "def _step_up_profile" "$DASHBOARD"; then
  pass "_step_up_profile method exists"
else
  fail "_step_up_profile missing"
fi

# ── 15. auto_profile_ceiling (manual sets ceiling) ─────────────
log "Step 15: auto_profile_ceiling tracked"

if grep -q "auto_profile_ceiling" "$DASHBOARD"; then
  pass "auto_profile_ceiling tracked"
else
  fail "auto_profile_ceiling missing"
fi

# Manual set_stream_profile updates ceiling
if grep -A 20 "def set_stream_profile" "$DASHBOARD" | grep -q "auto_profile_ceiling"; then
  pass "Manual profile change sets ceiling"
else
  fail "Manual profile change doesn't set ceiling"
fi

# ── 16. _auto_apply_profile preserves auto_mode ────────────────
log "Step 16: _auto_apply_profile preserves auto_mode"

if grep -q "async def _auto_apply_profile" "$DASHBOARD"; then
  pass "_auto_apply_profile method exists"
else
  fail "_auto_apply_profile missing"
fi

if grep -A 10 "def _auto_apply_profile" "$DASHBOARD" | grep -q "auto_mode=True"; then
  pass "_auto_apply_profile keeps auto_mode=True"
else
  fail "_auto_apply_profile doesn't preserve auto_mode"
fi

# ── 17. get_stream_health_summary method ───────────────────────
log "Step 17: get_stream_health_summary method"

if grep -q "def get_stream_health_summary" "$DASHBOARD"; then
  pass "get_stream_health_summary method exists"
else
  fail "get_stream_health_summary missing"
fi

# ── 18. Health in GET /api/stream/profile response ─────────────
log "Step 18: Health in API response"

if grep -A 15 "handle_get_stream_profile" "$DASHBOARD" | grep -q "health"; then
  pass "Health included in GET /api/stream/profile response"
else
  fail "Health missing from API response"
fi

if grep -A 15 "handle_get_stream_profile" "$DASHBOARD" | grep -q "get_stream_health_summary"; then
  pass "Uses get_stream_health_summary in response"
else
  fail "Not using get_stream_health_summary"
fi

# ── 19. current_speed in health summary ────────────────────────
log "Step 19: current_speed in health summary"

if grep -A 15 "def get_stream_health_summary" "$DASHBOARD" | grep -q "current_speed"; then
  pass "current_speed in health summary"
else
  fail "current_speed missing from health summary"
fi

# ── 20. recent_restarts in health summary ──────────────────────
log "Step 20: recent_restarts in health summary"

if grep -A 15 "def get_stream_health_summary" "$DASHBOARD" | grep -q "recent_restarts"; then
  pass "recent_restarts in health summary"
else
  fail "recent_restarts missing from health summary"
fi

# ── 21. last_error_summary in health summary ───────────────────
log "Step 21: last_error_summary in health summary"

if grep -A 15 "def get_stream_health_summary" "$DASHBOARD" | grep -q "last_error_summary"; then
  pass "last_error_summary in health summary"
else
  fail "last_error_summary missing from health summary"
fi

# ── 22. Auto mode handler sets ceiling ─────────────────────────
log "Step 22: Auto mode handler sets ceiling on enable"

if grep -A 20 "handle_stream_auto" "$DASHBOARD" | grep -q "auto_profile_ceiling"; then
  pass "Auto mode enable sets ceiling"
else
  fail "Auto mode enable doesn't set ceiling"
fi

# ── 23. PROFILE_ORDER defined ──────────────────────────────────
log "Step 23: PROFILE_ORDER defined"

if grep -q "PROFILE_ORDER" "$DASHBOARD"; then
  pass "PROFILE_ORDER defined"
else
  fail "PROFILE_ORDER missing"
fi

for p in "1080p30" "720p30" "480p30" "360p30"; do
  if grep "PROFILE_ORDER" "$DASHBOARD" | grep -q "$p"; then
    pass "PROFILE_ORDER contains '$p'"
  else
    fail "PROFILE_ORDER missing '$p'"
  fi
done

# ── Summary ──────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
