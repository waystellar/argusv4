#!/usr/bin/env bash
# production_stream_quality_smoke.sh — Smoke test for STREAM-3: Per-Vehicle Stream Quality Command
#
# Validates (source-level):
#   1. production.py compiles
#   2. set_stream_profile in VALID_COMMANDS
#   3. VALID_STREAM_PROFILES set defined with 4 profiles
#   4. StreamProfileRequest schema exists
#   5. StreamProfileResponse schema exists
#   6. StreamProfileState schema exists
#   7. POST /stream-profile endpoint registered
#   8. GET /stream-profile endpoint registered
#   9. set_stream_profile validation in send_edge_command
#  10. Stream profile ACK handling in receive_edge_command_response
#  11. set_stream_profile_state Redis helper exists
#  12. get_stream_profile_state Redis helper exists
#  13. Edge handler: set_stream_profile command in _execute_command
#  14. Edge handler calls self.set_stream_profile
#  15. pit_crew_dashboard.py compiles
#  16. ControlRoom.tsx has StreamProfileStatus interface
#  17. ControlRoom.tsx has STREAM_PROFILE_LABELS
#  18. ControlRoom.tsx has setStreamProfile mutation
#  19. ControlRoom.tsx has stream-profile polling effect
#  20. ControlRoom.tsx has quality dropdown (streamProfileStates)
#
# Usage:
#   bash scripts/production_stream_quality_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
REDIS_PY="$REPO_ROOT/cloud/app/redis_client.py"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
CONTROL_ROOM="$REPO_ROOT/web/src/pages/ControlRoom.tsx"
FAIL=0

log()  { echo "[stream3-smoke]  $*"; }
pass() { echo "[stream3-smoke]    PASS: $*"; }
fail() { echo "[stream3-smoke]    FAIL: $*"; FAIL=1; }
warn() { echo "[stream3-smoke]    WARN: $*"; }

# ── 1. production.py compiles ──────────────────────────────────
log "Step 1: production.py compiles"

if python3 -c "import py_compile; py_compile.compile('$PROD_PY', doraise=True)" 2>/dev/null; then
  pass "production.py compiles"
else
  fail "production.py syntax error"
fi

# ── 2. set_stream_profile in VALID_COMMANDS ────────────────────
log "Step 2: set_stream_profile in VALID_COMMANDS"

if grep -q '"set_stream_profile"' "$PROD_PY" && grep -q 'VALID_COMMANDS.*set_stream_profile' "$PROD_PY"; then
  pass "set_stream_profile in VALID_COMMANDS"
else
  fail "set_stream_profile missing from VALID_COMMANDS"
fi

# ── 3. VALID_STREAM_PROFILES defined ──────────────────────────
log "Step 3: VALID_STREAM_PROFILES defined"

if grep -q 'VALID_STREAM_PROFILES' "$PROD_PY"; then
  pass "VALID_STREAM_PROFILES set defined"
else
  fail "VALID_STREAM_PROFILES missing"
fi

for p in "1080p30" "720p30" "480p30" "360p30"; do
  if grep -q "\"$p\"" "$PROD_PY"; then
    pass "Profile '$p' in VALID_STREAM_PROFILES"
  else
    fail "Profile '$p' missing"
  fi
done

# ── 4. StreamProfileRequest schema ────────────────────────────
log "Step 4: StreamProfileRequest schema"

if grep -q "class StreamProfileRequest" "$PROD_PY"; then
  pass "StreamProfileRequest schema exists"
else
  fail "StreamProfileRequest missing"
fi

# ── 5. StreamProfileResponse schema ──────────────────────────
log "Step 5: StreamProfileResponse schema"

if grep -q "class StreamProfileResponse" "$PROD_PY"; then
  pass "StreamProfileResponse schema exists"
else
  fail "StreamProfileResponse missing"
fi

# ── 6. StreamProfileState schema ─────────────────────────────
log "Step 6: StreamProfileState schema"

if grep -q "class StreamProfileState" "$PROD_PY"; then
  pass "StreamProfileState schema exists"
else
  fail "StreamProfileState missing"
fi

# ── 7. POST /stream-profile endpoint ─────────────────────────
log "Step 7: POST /stream-profile endpoint"

if grep -q "async def set_stream_profile" "$PROD_PY"; then
  pass "POST set_stream_profile endpoint exists"
else
  fail "POST set_stream_profile endpoint missing"
fi

if grep -q "stream-profile" "$PROD_PY" && grep -q "response_model=StreamProfileResponse" "$PROD_PY"; then
  pass "stream-profile route with StreamProfileResponse"
else
  fail "stream-profile route configuration missing"
fi

# ── 8. GET /stream-profile endpoint ──────────────────────────
log "Step 8: GET /stream-profile endpoint"

if grep -q "async def get_stream_profile" "$PROD_PY"; then
  pass "GET get_stream_profile endpoint exists"
else
  fail "GET get_stream_profile endpoint missing"
fi

if grep -q "response_model=StreamProfileState" "$PROD_PY"; then
  pass "GET endpoint returns StreamProfileState"
else
  fail "GET endpoint missing StreamProfileState response model"
fi

# ── 9. set_stream_profile validation in send_edge_command ────
log "Step 9: Profile validation in send_edge_command"

if grep -A 5 'cmd.command == "set_stream_profile"' "$PROD_PY" | grep -q "VALID_STREAM_PROFILES"; then
  pass "set_stream_profile validation uses VALID_STREAM_PROFILES"
else
  fail "set_stream_profile validation missing"
fi

# ── 10. ACK handling in receive_edge_command_response ────────
log "Step 10: Stream profile ACK handling"

if grep -q 'command\["command"\] == "set_stream_profile"' "$PROD_PY"; then
  pass "ACK handler checks for set_stream_profile command"
else
  fail "ACK handler missing set_stream_profile"
fi

if grep -A 25 'command\["command"\] == "set_stream_profile"' "$PROD_PY" | grep -q "set_stream_profile_state"; then
  pass "ACK handler persists stream profile state"
else
  fail "ACK handler not persisting state"
fi

# ── 11. set_stream_profile_state Redis helper ────────────────
log "Step 11: set_stream_profile_state Redis helper"

if grep -q "async def set_stream_profile_state" "$REDIS_PY"; then
  pass "set_stream_profile_state helper exists"
else
  fail "set_stream_profile_state missing from redis_client"
fi

# ── 12. get_stream_profile_state Redis helper ────────────────
log "Step 12: get_stream_profile_state Redis helper"

if grep -q "async def get_stream_profile_state" "$REDIS_PY"; then
  pass "get_stream_profile_state helper exists"
else
  fail "get_stream_profile_state missing from redis_client"
fi

# ── 13. Edge: set_stream_profile in _execute_command ─────────
log "Step 13: Edge handler for set_stream_profile"

if grep -q 'command == "set_stream_profile"' "$DASHBOARD"; then
  pass "set_stream_profile command handler in edge"
else
  fail "set_stream_profile handler missing from edge"
fi

# ── 14. Edge handler calls set_stream_profile ────────────────
log "Step 14: Edge handler calls self.set_stream_profile"

if grep -A 15 'command == "set_stream_profile"' "$DASHBOARD" | grep -q "self.set_stream_profile"; then
  pass "Edge handler delegates to self.set_stream_profile"
else
  fail "Edge handler not calling set_stream_profile"
fi

# ── 15. pit_crew_dashboard.py compiles ───────────────────────
log "Step 15: pit_crew_dashboard.py compiles"

if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles"
else
  fail "pit_crew_dashboard.py syntax error"
fi

# ── 16. ControlRoom StreamProfileStatus interface ────────────
log "Step 16: StreamProfileStatus in ControlRoom"

if grep -q "interface StreamProfileStatus" "$CONTROL_ROOM"; then
  pass "StreamProfileStatus interface exists"
else
  fail "StreamProfileStatus interface missing"
fi

# ── 17. STREAM_PROFILE_LABELS constant ───────────────────────
log "Step 17: STREAM_PROFILE_LABELS in ControlRoom"

if grep -q "STREAM_PROFILE_LABELS" "$CONTROL_ROOM"; then
  pass "STREAM_PROFILE_LABELS constant exists"
else
  fail "STREAM_PROFILE_LABELS missing"
fi

# ── 18. setStreamProfile mutation ────────────────────────────
log "Step 18: setStreamProfile mutation"

if grep -q "setStreamProfile" "$CONTROL_ROOM" && grep -q "stream-profile" "$CONTROL_ROOM"; then
  pass "setStreamProfile mutation with stream-profile endpoint"
else
  fail "setStreamProfile mutation missing"
fi

# ── 19. Stream profile polling effect ────────────────────────
log "Step 19: Stream profile polling effect"

if grep -q "streamProfileStates" "$CONTROL_ROOM" && grep -q "stream-profile" "$CONTROL_ROOM"; then
  pass "Stream profile polling effect exists"
else
  fail "Stream profile polling missing"
fi

# ── 20. Quality dropdown in vehicle tiles ────────────────────
log "Step 20: Quality dropdown in UI"

if grep -q "STREAM_PROFILE_OPTIONS" "$CONTROL_ROOM"; then
  pass "STREAM_PROFILE_OPTIONS used in dropdown"
else
  fail "STREAM_PROFILE_OPTIONS missing from UI"
fi

if grep -q "Quality:" "$CONTROL_ROOM"; then
  pass "Quality label in vehicle tile"
else
  fail "Quality label missing from vehicle tile"
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
