#!/usr/bin/env bash
# cloud_control_room_leaderboard_smoke.sh — Smoke test for CLOUD-LEADERBOARD-0
#
# Validates that the Control Room leaderboard does not show "laps" language
# and correctly renders position, vehicle number, delta, and checkpoint.
#
# Validates:
#   ControlRoom.tsx (Leaderboard section):
#     1.  Leaderboard header badge does NOT contain "laps"
#     2.  Leaderboard header badge shows "Live order"
#     3.  Leaderboard heading text is "Leaderboard"
#     4.  LeaderboardRow renders position number
#     5.  LeaderboardRow renders vehicle number (#{entry.vehicle_number})
#     6.  LeaderboardRow renders delta (entry.delta_formatted) for non-leaders
#     7.  LeaderboardRow renders "Leader" for position 1
#     8.  LeaderboardRow renders checkpoint (CP {entry.last_checkpoint})
#     9.  LeaderboardRow has position-based color coding (gold/silver/bronze)
#    10.  Leaderboard shows top 10 (slice(0, 10))
#    11.  Empty state message present ("No timing data yet")
#
# Usage:
#   bash scripts/cloud_control_room_leaderboard_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[leaderboard]  $*"; }
pass() { echo "[leaderboard]    PASS: $*"; }
fail() { echo "[leaderboard]    FAIL: $*"; FAIL=1; }

CONTROL_ROOM="$REPO_ROOT/web/src/pages/ControlRoom.tsx"

log "CLOUD-LEADERBOARD-0: Control Room Leaderboard Smoke Test"
echo ""

if [ ! -f "$CONTROL_ROOM" ]; then
  fail "ControlRoom.tsx not found"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# LEADERBOARD HEADER
# ═══════════════════════════════════════════════════════════════════

# ── 1. No "laps" in leaderboard badge ────────────────────────────
log "Step 1: Leaderboard badge does NOT contain 'laps'"
# Check the leaderboard section (between "Leaderboard" heading and LeaderboardRow)
if grep -A5 '>Leaderboard<' "$CONTROL_ROOM" | grep -qi 'laps'; then
  fail "Leaderboard badge still contains 'laps'"
else
  pass "No 'laps' text in leaderboard badge"
fi

# ── 2. Badge shows "Live order" ──────────────────────────────────
log "Step 2: Leaderboard badge shows 'Live order'"
if grep -A5 '>Leaderboard<' "$CONTROL_ROOM" | grep -q 'Live order'; then
  pass "Leaderboard badge shows 'Live order'"
else
  fail "Leaderboard badge missing 'Live order'"
fi

# ── 3. Heading text is "Leaderboard" ─────────────────────────────
log "Step 3: Leaderboard heading present"
if grep -q '>Leaderboard<' "$CONTROL_ROOM"; then
  pass "Leaderboard heading present"
else
  fail "Leaderboard heading missing"
fi

# ═══════════════════════════════════════════════════════════════════
# LEADERBOARD ROW COMPONENT
# ═══════════════════════════════════════════════════════════════════

# ── 4. LeaderboardRow renders position ────────────────────────────
log "Step 4: LeaderboardRow renders position number"
if grep -A40 'function LeaderboardRow' "$CONTROL_ROOM" | grep -q '{entry.position}'; then
  pass "LeaderboardRow renders position number"
else
  fail "LeaderboardRow missing position number"
fi

# ── 5. LeaderboardRow renders vehicle number ──────────────────────
log "Step 5: LeaderboardRow renders vehicle number"
if grep -A40 'function LeaderboardRow' "$CONTROL_ROOM" | grep -q '#{entry.vehicle_number}'; then
  pass "LeaderboardRow renders vehicle number"
else
  fail "LeaderboardRow missing vehicle number"
fi

# ── 6. LeaderboardRow renders delta for non-leaders ───────────────
log "Step 6: LeaderboardRow renders delta_formatted"
if grep -A40 'function LeaderboardRow' "$CONTROL_ROOM" | grep -q 'entry.delta_formatted'; then
  pass "LeaderboardRow renders delta_formatted"
else
  fail "LeaderboardRow missing delta_formatted"
fi

# ── 7. LeaderboardRow shows 'Leader' for P1 ──────────────────────
log "Step 7: LeaderboardRow shows 'Leader' for position 1"
if grep -A40 'function LeaderboardRow' "$CONTROL_ROOM" | grep -q "'Leader'"; then
  pass "LeaderboardRow shows 'Leader' for P1"
else
  fail "LeaderboardRow missing 'Leader' label for P1"
fi

# ── 8. LeaderboardRow renders checkpoint ──────────────────────────
log "Step 8: LeaderboardRow renders checkpoint"
if grep -A50 'function LeaderboardRow' "$CONTROL_ROOM" | grep -q 'CP {entry.last_checkpoint}'; then
  pass "LeaderboardRow renders checkpoint"
else
  fail "LeaderboardRow missing checkpoint display"
fi

# ── 9. Position-based color coding (gold/silver/bronze) ──────────
log "Step 9: Position-based color coding"
if grep -A40 'function LeaderboardRow' "$CONTROL_ROOM" | grep -q 'bg-status-warning'; then
  pass "P1 has gold (status-warning) color"
else
  fail "P1 missing gold color coding"
fi

# ── 10. Leaderboard shows top 10 ─────────────────────────────────
log "Step 10: Leaderboard slices to top 10"
if grep -q 'leaderboard.slice(0, 10)' "$CONTROL_ROOM"; then
  pass "Leaderboard slices to top 10"
else
  fail "Leaderboard missing slice(0, 10)"
fi

# ── 11. Empty state message present ──────────────────────────────
log "Step 11: Empty state message present"
if grep -q 'No timing data yet' "$CONTROL_ROOM"; then
  pass "Empty state 'No timing data yet' present"
else
  fail "Empty state message missing"
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
