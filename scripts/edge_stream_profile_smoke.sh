#!/usr/bin/env bash
# edge_stream_profile_smoke.sh — Smoke test for STREAM-1: Stream Profiles
#
# Validates (source-level):
#   1. stream_profiles.py exists and compiles
#   2. All four presets defined (1080p30, 720p30, 480p30, 360p30)
#   3. build_ffmpeg_cmd function exists
#   4. scale filter used for sub-1080 profiles
#   5. Bitrate set per profile
#   6. Persistence functions exist (load/save)
#   7. pit_crew_dashboard.py compiles
#   8. GET /api/stream/profile endpoint registered
#   9. POST /api/stream/profile endpoint registered
#  10. POST /api/stream/auto endpoint registered
#  11. handle_get_stream_profile handler exists
#  12. handle_set_stream_profile handler exists
#  13. handle_stream_auto handler exists
#  14. set_stream_profile method exists
#  15. _build_ffmpeg_cmd uses shared builder
#  16. Profile dropdown in stream control UI
#  17. handleProfileChange JS function exists
#  18. video_director.py compiles
#  19. video_director uses shared builder
#  20. stream_profile in streaming status response
#
# Usage:
#   bash scripts/edge_stream_profile_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SP="$REPO_ROOT/edge/stream_profiles.py"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
VD="$REPO_ROOT/edge/video_director.py"
FAIL=0

log()  { echo "[stream-profile]  $*"; }
pass() { echo "[stream-profile]    PASS: $*"; }
fail() { echo "[stream-profile]    FAIL: $*"; FAIL=1; }
warn() { echo "[stream-profile]    WARN: $*"; }

# ── 1. stream_profiles.py exists and compiles ─────────────────────
log "Step 1: stream_profiles.py exists and compiles"

if [ -f "$SP" ]; then
  pass "stream_profiles.py exists"
  if python3 -c "import py_compile; py_compile.compile('$SP', doraise=True)" 2>/dev/null; then
    pass "stream_profiles.py compiles"
  else
    fail "stream_profiles.py syntax error"
  fi
else
  fail "stream_profiles.py not found"
fi

# ── 2. All four presets defined ───────────────────────────────────
log "Step 2: Four stream presets defined"

for profile in 1080p30 720p30 480p30 360p30; do
  if grep -q "\"$profile\"" "$SP"; then
    pass "Profile '$profile' defined"
  else
    fail "Profile '$profile' missing"
  fi
done

# ── 3. build_ffmpeg_cmd function exists ───────────────────────────
log "Step 3: build_ffmpeg_cmd function"

if grep -q "def build_ffmpeg_cmd" "$SP"; then
  pass "build_ffmpeg_cmd function exists"
else
  fail "build_ffmpeg_cmd function missing"
fi

# ── 4. Scale filter for downscaling ──────────────────────────────
log "Step 4: Scale filter in ffmpeg builder"

if grep -q "scale=-2:" "$SP"; then
  pass "Scale filter uses scale=-2:<height> pattern"
else
  fail "Scale filter missing"
fi

# ── 5. Bitrate set per profile ────────────────────────────────────
log "Step 5: Bitrate varies per profile"

if grep -q '"4500k"' "$SP" && grep -q '"2500k"' "$SP" && grep -q '"1200k"' "$SP" && grep -q '"800k"' "$SP"; then
  pass "Four distinct bitrates defined (4500k, 2500k, 1200k, 800k)"
else
  fail "Not all four bitrates found"
fi

# ── 6. Persistence functions ─────────────────────────────────────
log "Step 6: Profile persistence"

if grep -q "def load_profile_state" "$SP"; then
  pass "load_profile_state function exists"
else
  fail "load_profile_state missing"
fi

if grep -q "def save_profile_state" "$SP"; then
  pass "save_profile_state function exists"
else
  fail "save_profile_state missing"
fi

# ── 7. pit_crew_dashboard.py compiles ─────────────────────────────
log "Step 7: pit_crew_dashboard.py compiles"

if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles"
else
  fail "pit_crew_dashboard.py syntax error"
fi

# ── 8. GET /api/stream/profile endpoint ───────────────────────────
log "Step 8: GET /api/stream/profile endpoint"

if grep -q "'/api/stream/profile'" "$DASHBOARD" && grep -q "add_get.*stream/profile" "$DASHBOARD"; then
  pass "GET /api/stream/profile registered"
else
  fail "GET /api/stream/profile missing"
fi

# ── 9. POST /api/stream/profile endpoint ──────────────────────────
log "Step 9: POST /api/stream/profile endpoint"

if grep -q "add_post.*stream/profile.*handle_set_stream_profile" "$DASHBOARD"; then
  pass "POST /api/stream/profile registered"
else
  fail "POST /api/stream/profile missing"
fi

# ── 10. POST /api/stream/auto endpoint ────────────────────────────
log "Step 10: POST /api/stream/auto endpoint"

if grep -q "'/api/stream/auto'" "$DASHBOARD"; then
  pass "POST /api/stream/auto registered"
else
  fail "POST /api/stream/auto missing"
fi

# ── 11. handle_get_stream_profile handler ─────────────────────────
log "Step 11: handle_get_stream_profile handler"

if grep -q "async def handle_get_stream_profile" "$DASHBOARD"; then
  pass "handle_get_stream_profile handler exists"
else
  fail "handle_get_stream_profile missing"
fi

# ── 12. handle_set_stream_profile handler ─────────────────────────
log "Step 12: handle_set_stream_profile handler"

if grep -q "async def handle_set_stream_profile" "$DASHBOARD"; then
  pass "handle_set_stream_profile handler exists"
else
  fail "handle_set_stream_profile missing"
fi

# ── 13. handle_stream_auto handler ────────────────────────────────
log "Step 13: handle_stream_auto handler"

if grep -q "async def handle_stream_auto" "$DASHBOARD"; then
  pass "handle_stream_auto handler exists"
else
  fail "handle_stream_auto missing"
fi

# ── 14. set_stream_profile method ─────────────────────────────────
log "Step 14: set_stream_profile business logic"

if grep -q "async def set_stream_profile" "$DASHBOARD"; then
  pass "set_stream_profile method exists"
else
  fail "set_stream_profile missing"
fi

if grep -q "save_profile_state" "$DASHBOARD"; then
  pass "Calls save_profile_state for persistence"
else
  fail "Not persisting profile changes"
fi

# ── 15. _build_ffmpeg_cmd uses shared builder ─────────────────────
log "Step 15: Dashboard ffmpeg builder uses shared module"

if grep -A 10 "def _build_ffmpeg_cmd" "$DASHBOARD" | grep -q "build_ffmpeg_cmd"; then
  pass "Dashboard _build_ffmpeg_cmd delegates to shared builder"
else
  fail "Dashboard not using shared builder"
fi

if grep -A 10 "def _build_ffmpeg_cmd" "$DASHBOARD" | grep -q "get_profile"; then
  pass "Dashboard passes current profile to builder"
else
  fail "Dashboard not passing profile"
fi

# ── 16. Profile dropdown in stream control UI ────────────────────
log "Step 16: Profile dropdown in HTML"

if grep -q "streamProfileSelect" "$DASHBOARD"; then
  pass "streamProfileSelect dropdown exists"
else
  fail "streamProfileSelect dropdown missing"
fi

if grep -q "handleProfileChange" "$DASHBOARD"; then
  pass "handleProfileChange JS function referenced"
else
  fail "handleProfileChange missing from UI"
fi

# ── 17. handleProfileChange JS function ──────────────────────────
log "Step 17: handleProfileChange JS implementation"

if grep -q "async function handleProfileChange" "$DASHBOARD"; then
  pass "handleProfileChange async function defined"
else
  fail "handleProfileChange function not defined"
fi

# ── 18. video_director.py compiles ────────────────────────────────
log "Step 18: video_director.py compiles"

if python3 -c "import py_compile; py_compile.compile('$VD', doraise=True)" 2>/dev/null; then
  pass "video_director.py compiles"
else
  fail "video_director.py syntax error"
fi

# ── 19. video_director uses shared builder ────────────────────────
log "Step 19: video_director uses shared builder"

if grep -A 10 "def _build_ffmpeg_command" "$VD" | grep -q "build_ffmpeg_cmd"; then
  pass "video_director delegates to shared build_ffmpeg_cmd"
else
  fail "video_director not using shared builder"
fi

if grep -A 10 "def _build_ffmpeg_command" "$VD" | grep -q "load_profile_state"; then
  pass "video_director reads persisted profile"
else
  fail "video_director not reading profile state"
fi

# ── 20. stream_profile in status response ─────────────────────────
log "Step 20: stream_profile in streaming status"

if grep -q '"stream_profile"' "$DASHBOARD"; then
  pass "stream_profile field in status response"
else
  fail "stream_profile missing from status response"
fi

# ── Summary ──────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
