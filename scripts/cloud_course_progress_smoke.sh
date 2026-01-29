#!/usr/bin/env bash
# cloud_course_progress_smoke.sh — Smoke test for PROGRESS-1: Course Progress Computation
#
# Validates (source-level):
#   1. geo.py compiles
#   2. gpx_parser.py compiles
#   3. schemas.py compiles
#   4. checkpoint_service.py compiles
#   5. telemetry.py compiles
#   6. METERS_PER_MILE constant defined in geo.py
#   7. project_onto_course function exists in geo.py
#   8. compute_progress_miles function exists in geo.py
#   9. course_cumulative_m in ParsedCourse TypedDict
#  10. cumulative_m stored in GeoJSON properties (parse_gpx)
#  11. cumulative_m stored in GeoJSON properties (parse_kml)
#  12. progress_miles field in LeaderboardEntry schema
#  13. miles_remaining field in LeaderboardEntry schema
#  14. course_length_miles field in LeaderboardResponse schema
#  15. progress_miles field in VehiclePosition schema
#  16. miles_remaining field in VehiclePosition schema
#  17. progress_miles field in SSEPositionEvent schema
#  18. compute_progress_miles imported in telemetry.py
#  19. progress_miles included in SSE broadcast (telemetry.py)
#  20. progress_miles included in Redis position cache (telemetry.py)
#  21. progress_miles included in leaderboard entries (checkpoint_service.py)
#  22. course_length_miles in LeaderboardResponse construction
#  23. METERS_PER_MILE imported in checkpoint_service.py
#  24. progress_miles in get_latest_positions response (telemetry.py)
#
# Usage:
#   bash scripts/cloud_course_progress_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GEO="$REPO_ROOT/cloud/app/services/geo.py"
GPX="$REPO_ROOT/cloud/app/services/gpx_parser.py"
SCHEMAS="$REPO_ROOT/cloud/app/schemas.py"
CHECKPOINT="$REPO_ROOT/cloud/app/services/checkpoint_service.py"
TELEMETRY="$REPO_ROOT/cloud/app/routes/telemetry.py"
FAIL=0

log()  { echo "[progress-smoke]  $*"; }
pass() { echo "[progress-smoke]    PASS: $*"; }
fail() { echo "[progress-smoke]    FAIL: $*"; FAIL=1; }

# ── 1. geo.py compiles ─────────────────────────────────────────
log "Step 1: geo.py compiles"

if python3 -c "import py_compile; py_compile.compile('$GEO', doraise=True)" 2>/dev/null; then
  pass "geo.py compiles"
else
  fail "geo.py syntax error"
fi

# ── 2. gpx_parser.py compiles ──────────────────────────────────
log "Step 2: gpx_parser.py compiles"

if python3 -c "import py_compile; py_compile.compile('$GPX', doraise=True)" 2>/dev/null; then
  pass "gpx_parser.py compiles"
else
  fail "gpx_parser.py syntax error"
fi

# ── 3. schemas.py compiles ─────────────────────────────────────
log "Step 3: schemas.py compiles"

if python3 -c "import py_compile; py_compile.compile('$SCHEMAS', doraise=True)" 2>/dev/null; then
  pass "schemas.py compiles"
else
  fail "schemas.py syntax error"
fi

# ── 4. checkpoint_service.py compiles ──────────────────────────
log "Step 4: checkpoint_service.py compiles"

if python3 -c "import py_compile; py_compile.compile('$CHECKPOINT', doraise=True)" 2>/dev/null; then
  pass "checkpoint_service.py compiles"
else
  fail "checkpoint_service.py syntax error"
fi

# ── 5. telemetry.py compiles ──────────────────────────────────
log "Step 5: telemetry.py compiles"

if python3 -c "import py_compile; py_compile.compile('$TELEMETRY', doraise=True)" 2>/dev/null; then
  pass "telemetry.py compiles"
else
  fail "telemetry.py syntax error"
fi

# ── 6. METERS_PER_MILE constant ───────────────────────────────
log "Step 6: METERS_PER_MILE constant"

if grep -q "METERS_PER_MILE = 1609" "$GEO"; then
  pass "METERS_PER_MILE defined in geo.py"
else
  fail "METERS_PER_MILE missing from geo.py"
fi

# ── 7. project_onto_course function ───────────────────────────
log "Step 7: project_onto_course function"

if grep -q "def project_onto_course" "$GEO"; then
  pass "project_onto_course function exists"
else
  fail "project_onto_course missing"
fi

if grep -q "cumulative_m" "$GEO"; then
  pass "project_onto_course uses cumulative_m parameter"
else
  fail "project_onto_course missing cumulative_m"
fi

# ── 8. compute_progress_miles function ────────────────────────
log "Step 8: compute_progress_miles function"

if grep -q "def compute_progress_miles" "$GEO"; then
  pass "compute_progress_miles function exists"
else
  fail "compute_progress_miles missing"
fi

if grep -A 20 "def compute_progress_miles" "$GEO" | grep -q "progress_miles"; then
  pass "compute_progress_miles returns progress_miles"
else
  fail "compute_progress_miles doesn't compute progress_miles"
fi

if grep -A 20 "def compute_progress_miles" "$GEO" | grep -q "miles_remaining"; then
  pass "compute_progress_miles returns miles_remaining"
else
  fail "compute_progress_miles doesn't compute miles_remaining"
fi

if grep -A 20 "def compute_progress_miles" "$GEO" | grep -q "course_length_miles"; then
  pass "compute_progress_miles returns course_length_miles"
else
  fail "compute_progress_miles doesn't compute course_length_miles"
fi

# ── 9. course_cumulative_m in ParsedCourse ────────────────────
log "Step 9: course_cumulative_m in ParsedCourse"

if grep -q "course_cumulative_m" "$GPX"; then
  pass "course_cumulative_m in ParsedCourse TypedDict"
else
  fail "course_cumulative_m missing from ParsedCourse"
fi

# ── 10. cumulative_m in GeoJSON (parse_gpx) ───────────────────
log "Step 10: cumulative_m in GeoJSON (parse_gpx)"

if grep -A 5 "def parse_gpx" "$GPX" >/dev/null && grep -q '"cumulative_m"' "$GPX"; then
  pass "cumulative_m stored in GeoJSON properties"
else
  fail "cumulative_m missing from GeoJSON properties"
fi

# ── 11. cumulative_m in GeoJSON (parse_kml) ───────────────────
log "Step 11: cumulative_m in GeoJSON (parse_kml)"

if grep -A 200 "def parse_kml" "$GPX" | grep -q '"cumulative_m"'; then
  pass "cumulative_m in parse_kml GeoJSON"
else
  fail "cumulative_m missing from parse_kml"
fi

# ── 12. progress_miles in LeaderboardEntry ────────────────────
log "Step 12: progress_miles in LeaderboardEntry"

if grep -A 15 "class LeaderboardEntry" "$SCHEMAS" | grep -q "progress_miles"; then
  pass "progress_miles field in LeaderboardEntry"
else
  fail "progress_miles missing from LeaderboardEntry"
fi

# ── 13. miles_remaining in LeaderboardEntry ───────────────────
log "Step 13: miles_remaining in LeaderboardEntry"

if grep -A 15 "class LeaderboardEntry" "$SCHEMAS" | grep -q "miles_remaining"; then
  pass "miles_remaining field in LeaderboardEntry"
else
  fail "miles_remaining missing from LeaderboardEntry"
fi

# ── 14. course_length_miles in LeaderboardResponse ────────────
log "Step 14: course_length_miles in LeaderboardResponse"

if grep -A 10 "class LeaderboardResponse" "$SCHEMAS" | grep -q "course_length_miles"; then
  pass "course_length_miles field in LeaderboardResponse"
else
  fail "course_length_miles missing from LeaderboardResponse"
fi

# ── 15. progress_miles in VehiclePosition ─────────────────────
log "Step 15: progress_miles in VehiclePosition"

if grep -A 15 "class VehiclePosition" "$SCHEMAS" | grep -q "progress_miles"; then
  pass "progress_miles field in VehiclePosition"
else
  fail "progress_miles missing from VehiclePosition"
fi

# ── 16. miles_remaining in VehiclePosition ────────────────────
log "Step 16: miles_remaining in VehiclePosition"

if grep -A 15 "class VehiclePosition" "$SCHEMAS" | grep -q "miles_remaining"; then
  pass "miles_remaining field in VehiclePosition"
else
  fail "miles_remaining missing from VehiclePosition"
fi

# ── 17. progress_miles in SSEPositionEvent ────────────────────
log "Step 17: progress_miles in SSEPositionEvent"

if grep -A 15 "class SSEPositionEvent" "$SCHEMAS" | grep -q "progress_miles"; then
  pass "progress_miles field in SSEPositionEvent"
else
  fail "progress_miles missing from SSEPositionEvent"
fi

# ── 18. compute_progress_miles imported in telemetry.py ───────
log "Step 18: compute_progress_miles imported in telemetry.py"

if grep -q "compute_progress_miles" "$TELEMETRY"; then
  pass "compute_progress_miles imported in telemetry.py"
else
  fail "compute_progress_miles not imported in telemetry.py"
fi

# ── 19. progress_miles in SSE broadcast ───────────────────────
log "Step 19: progress_miles in SSE broadcast"

if grep -q "progress_data" "$TELEMETRY" && grep -q "sse_data.update(progress_data)" "$TELEMETRY"; then
  pass "progress_miles included in SSE broadcast"
else
  fail "progress_miles missing from SSE broadcast"
fi

# ── 20. progress_miles in Redis cache ─────────────────────────
log "Step 20: progress_miles in Redis position cache"

if grep -q "last_pos.update(progress_data)" "$TELEMETRY"; then
  pass "progress_miles stored in Redis position cache"
else
  fail "progress_miles missing from Redis cache"
fi

# ── 21. progress_miles in leaderboard entries ─────────────────
log "Step 21: progress_miles in leaderboard entries"

if grep -q 'progress_miles=pos.get("progress_miles")' "$CHECKPOINT"; then
  pass "progress_miles in leaderboard entries"
else
  fail "progress_miles missing from leaderboard entries"
fi

# ── 22. course_length_miles in LeaderboardResponse construction
log "Step 22: course_length_miles in response"

if grep -q "course_length_miles=course_length_miles" "$CHECKPOINT"; then
  pass "course_length_miles in LeaderboardResponse construction"
else
  fail "course_length_miles missing from response construction"
fi

# ── 23. METERS_PER_MILE imported in checkpoint_service.py ─────
log "Step 23: METERS_PER_MILE in checkpoint_service.py"

if grep -q "METERS_PER_MILE" "$CHECKPOINT"; then
  pass "METERS_PER_MILE imported in checkpoint_service.py"
else
  fail "METERS_PER_MILE missing from checkpoint_service.py"
fi

# ── 24. progress_miles in get_latest_positions ────────────────
log "Step 24: progress_miles in get_latest_positions response"

if grep -A 45 "async def get_latest_positions" "$TELEMETRY" | grep -q "progress_miles"; then
  pass "progress_miles in get_latest_positions response"
else
  fail "progress_miles missing from get_latest_positions"
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
