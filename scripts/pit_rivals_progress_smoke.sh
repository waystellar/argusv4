#!/usr/bin/env bash
# pit_rivals_progress_smoke.sh — Smoke test for PROGRESS-3: Edge Pit Crew Rivals + Miles Remaining
#
# Validates in edge/pit_crew_dashboard.py:
#   1. Python syntax check passes
#   2. Poll interval default is 60 (leaderboard_poll_seconds)
#   3. ARGUS_LEADERBOARD_POLL_SECONDS env var override exists
#   4. No placeholder "Vehicle ahead" text in competitor UI
#   5. No placeholder "Vehicle behind" text in competitor UI
#   6. UI contains "mi ahead" text
#   7. UI contains "mi behind" text
#   8. UI contains "mi remaining" text
#   9. "YOU ARE LEADING" text for P1 edge case
#  10. "No vehicle behind" text for last-place edge case
#  11. "No course progress available" for missing progress
#  12. competitor_ahead in to_dict / JSON payload
#  13. competitor_behind in to_dict / JSON payload
#  14. progress_miles field in to_dict / TelemetryState
#  15. miles_remaining field in to_dict / TelemetryState
#  16. course_length_miles field in to_dict / TelemetryState
#  17. _compute_competitors method exists
#  18. gap_miles computed in _compute_competitors
#
# Usage:
#   bash scripts/pit_rivals_progress_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PIT="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[rivals-progress-smoke]  $*"; }
pass() { echo "[rivals-progress-smoke]    PASS: $*"; }
fail() { echo "[rivals-progress-smoke]    FAIL: $*"; FAIL=1; }

# ── 1. Python syntax check ──────────────────────────────────
log "Step 1: pit_crew_dashboard.py compiles"

if python3 -c "import py_compile; py_compile.compile('$PIT', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles"
else
  fail "pit_crew_dashboard.py syntax error"
fi

# ── 2. Poll interval default is 60 ──────────────────────────
log "Step 2: leaderboard_poll_seconds default 60"

if grep -q "leaderboard_poll_seconds.*=.*60" "$PIT"; then
  pass "leaderboard_poll_seconds default is 60"
else
  fail "leaderboard_poll_seconds default not 60"
fi

# ── 3. Env var override ─────────────────────────────────────
log "Step 3: ARGUS_LEADERBOARD_POLL_SECONDS env var"

if grep -q "ARGUS_LEADERBOARD_POLL_SECONDS" "$PIT"; then
  pass "ARGUS_LEADERBOARD_POLL_SECONDS env var override"
else
  fail "ARGUS_LEADERBOARD_POLL_SECONDS missing"
fi

# ── 4. No placeholder "Vehicle ahead" ───────────────────────
log "Step 4: No placeholder Vehicle ahead text"

if grep -q '"Vehicle ahead"' "$PIT"; then
  fail "Placeholder 'Vehicle ahead' still present"
else
  pass "No placeholder Vehicle ahead"
fi

# ── 5. No placeholder "Vehicle behind" ──────────────────────
log "Step 5: No placeholder Vehicle behind text"

if grep -q '"Vehicle behind"' "$PIT"; then
  fail "Placeholder 'Vehicle behind' still present"
else
  pass "No placeholder Vehicle behind"
fi

# ── 6. UI contains "mi ahead" ───────────────────────────────
log "Step 6: mi ahead in UI"

if grep -q "mi ahead" "$PIT"; then
  pass "mi ahead text in UI"
else
  fail "mi ahead missing from UI"
fi

# ── 7. UI contains "mi behind" ──────────────────────────────
log "Step 7: mi behind in UI"

if grep -q "mi behind" "$PIT"; then
  pass "mi behind text in UI"
else
  fail "mi behind missing from UI"
fi

# ── 8. UI contains "mi remaining" ───────────────────────────
log "Step 8: mi remaining in UI"

if grep -q "mi remaining" "$PIT"; then
  pass "mi remaining text in UI"
else
  fail "mi remaining missing from UI"
fi

# ── 9. "YOU ARE LEADING" for P1 ─────────────────────────────
log "Step 9: YOU ARE LEADING edge case"

if grep -q "YOU ARE LEADING" "$PIT"; then
  pass "YOU ARE LEADING text present"
else
  fail "YOU ARE LEADING missing"
fi

# ── 10. "No vehicle behind" for last place ──────────────────
log "Step 10: No vehicle behind edge case"

if grep -q "No vehicle behind" "$PIT"; then
  pass "No vehicle behind text present"
else
  fail "No vehicle behind missing"
fi

# ── 11. "No course progress available" ──────────────────────
log "Step 11: No course progress available fallback"

if grep -q "No course progress available" "$PIT"; then
  pass "No course progress available text present"
else
  fail "No course progress available missing"
fi

# ── 12. competitor_ahead in JSON payload ────────────────────
log "Step 12: competitor_ahead in to_dict"

if grep -q '"competitor_ahead"' "$PIT"; then
  pass "competitor_ahead in JSON payload"
else
  fail "competitor_ahead missing from JSON payload"
fi

# ── 13. competitor_behind in JSON payload ───────────────────
log "Step 13: competitor_behind in to_dict"

if grep -q '"competitor_behind"' "$PIT"; then
  pass "competitor_behind in JSON payload"
else
  fail "competitor_behind missing from JSON payload"
fi

# ── 14. progress_miles in TelemetryState/to_dict ────────────
log "Step 14: progress_miles field"

if grep -q '"progress_miles"' "$PIT"; then
  pass "progress_miles in JSON payload"
else
  fail "progress_miles missing from JSON payload"
fi

# ── 15. miles_remaining in TelemetryState/to_dict ───────────
log "Step 15: miles_remaining field"

if grep -q '"miles_remaining"' "$PIT"; then
  pass "miles_remaining in JSON payload"
else
  fail "miles_remaining missing from JSON payload"
fi

# ── 16. course_length_miles in TelemetryState/to_dict ───────
log "Step 16: course_length_miles field"

if grep -q '"course_length_miles"' "$PIT"; then
  pass "course_length_miles in JSON payload"
else
  fail "course_length_miles missing from JSON payload"
fi

# ── 17. _compute_competitors method ─────────────────────────
log "Step 17: _compute_competitors method exists"

if grep -q "def _compute_competitors" "$PIT"; then
  pass "_compute_competitors method exists"
else
  fail "_compute_competitors method missing"
fi

# ── 18. gap_miles computed ──────────────────────────────────
log "Step 18: gap_miles in _compute_competitors"

if grep -A 30 "def _compute_competitors" "$PIT" | grep -q "gap_miles"; then
  pass "gap_miles computed in _compute_competitors"
else
  fail "gap_miles missing from _compute_competitors"
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
