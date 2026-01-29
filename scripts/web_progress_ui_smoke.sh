#!/usr/bin/env bash
# web_progress_ui_smoke.sh — Smoke test for PROGRESS-2: Web UI miles remaining
#
# Validates (source-level):
#   1. progress_miles field in VehiclePosition interface (client.ts)
#   2. miles_remaining field in VehiclePosition interface (client.ts)
#   3. progress_miles field in LeaderboardEntry interface (client.ts)
#   4. miles_remaining field in LeaderboardEntry interface (client.ts)
#   5. course_length_miles field in Leaderboard interface (client.ts)
#   6. miles_remaining rendered in StandingsTab (StandingsTab.tsx)
#   7. toFixed(1) formatting in StandingsTab
#   8. miles_remaining rendered in VehiclePage (VehiclePage.tsx)
#   9. toFixed(1) formatting in VehiclePage
#  10. miles_remaining rendered in FeaturedVehicleTile (OverviewTab.tsx)
#  11. miles_remaining rendered in MiniLeaderboardRow (OverviewTab.tsx)
#  12. toFixed(1) formatting in OverviewTab
#  13. null-safe rendering (miles_remaining != null check in StandingsTab)
#  14. null-safe rendering (miles_remaining != null check in VehiclePage)
#  15. null-safe rendering (miles_remaining != null check in OverviewTab)
#
# Usage:
#   bash scripts/web_progress_ui_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIENT="$REPO_ROOT/web/src/api/client.ts"
STANDINGS="$REPO_ROOT/web/src/components/RaceCenter/StandingsTab.tsx"
VEHICLE="$REPO_ROOT/web/src/pages/VehiclePage.tsx"
OVERVIEW="$REPO_ROOT/web/src/components/RaceCenter/OverviewTab.tsx"
FAIL=0

log()  { echo "[progress-ui-smoke]  $*"; }
pass() { echo "[progress-ui-smoke]    PASS: $*"; }
fail() { echo "[progress-ui-smoke]    FAIL: $*"; FAIL=1; }

# ── 1. progress_miles in VehiclePosition ─────────────────────
log "Step 1: progress_miles in VehiclePosition"

if grep -A 15 "interface VehiclePosition" "$CLIENT" | grep -q "progress_miles"; then
  pass "progress_miles field in VehiclePosition"
else
  fail "progress_miles missing from VehiclePosition"
fi

# ── 2. miles_remaining in VehiclePosition ────────────────────
log "Step 2: miles_remaining in VehiclePosition"

if grep -A 15 "interface VehiclePosition" "$CLIENT" | grep -q "miles_remaining"; then
  pass "miles_remaining field in VehiclePosition"
else
  fail "miles_remaining missing from VehiclePosition"
fi

# ── 3. progress_miles in LeaderboardEntry ────────────────────
log "Step 3: progress_miles in LeaderboardEntry"

if grep -A 15 "interface LeaderboardEntry" "$CLIENT" | grep -q "progress_miles"; then
  pass "progress_miles field in LeaderboardEntry"
else
  fail "progress_miles missing from LeaderboardEntry"
fi

# ── 4. miles_remaining in LeaderboardEntry ───────────────────
log "Step 4: miles_remaining in LeaderboardEntry"

if grep -A 15 "interface LeaderboardEntry" "$CLIENT" | grep -q "miles_remaining"; then
  pass "miles_remaining field in LeaderboardEntry"
else
  fail "miles_remaining missing from LeaderboardEntry"
fi

# ── 5. course_length_miles in Leaderboard ────────────────────
log "Step 5: course_length_miles in Leaderboard"

if grep -A 10 "interface Leaderboard" "$CLIENT" | grep -q "course_length_miles"; then
  pass "course_length_miles field in Leaderboard"
else
  fail "course_length_miles missing from Leaderboard"
fi

# ── 6. miles_remaining rendered in StandingsTab ──────────────
log "Step 6: miles_remaining in StandingsTab"

if grep -q "miles_remaining" "$STANDINGS"; then
  pass "miles_remaining rendered in StandingsTab"
else
  fail "miles_remaining missing from StandingsTab"
fi

# ── 7. toFixed(1) in StandingsTab ───────────────────────────
log "Step 7: toFixed(1) formatting in StandingsTab"

if grep -q "toFixed(1)" "$STANDINGS"; then
  pass "toFixed(1) formatting in StandingsTab"
else
  fail "toFixed(1) missing from StandingsTab"
fi

# ── 8. miles_remaining rendered in VehiclePage ───────────────
log "Step 8: miles_remaining in VehiclePage"

if grep -q "miles_remaining" "$VEHICLE"; then
  pass "miles_remaining rendered in VehiclePage"
else
  fail "miles_remaining missing from VehiclePage"
fi

# ── 9. toFixed(1) in VehiclePage ────────────────────────────
log "Step 9: toFixed(1) formatting in VehiclePage"

if grep -q "toFixed(1)" "$VEHICLE"; then
  pass "toFixed(1) formatting in VehiclePage"
else
  fail "toFixed(1) missing from VehiclePage"
fi

# ── 10. miles_remaining in FeaturedVehicleTile ───────────────
log "Step 10: miles_remaining in FeaturedVehicleTile (OverviewTab)"

if grep -A 60 "function FeaturedVehicleTile" "$OVERVIEW" | grep -q "miles_remaining"; then
  pass "miles_remaining in FeaturedVehicleTile"
else
  fail "miles_remaining missing from FeaturedVehicleTile"
fi

# ── 11. miles_remaining in MiniLeaderboardRow ────────────────
log "Step 11: miles_remaining in MiniLeaderboardRow (OverviewTab)"

if grep -A 60 "function MiniLeaderboardRow" "$OVERVIEW" | grep -q "miles_remaining"; then
  pass "miles_remaining in MiniLeaderboardRow"
else
  fail "miles_remaining missing from MiniLeaderboardRow"
fi

# ── 12. toFixed(1) in OverviewTab ───────────────────────────
log "Step 12: toFixed(1) formatting in OverviewTab"

if grep -q "toFixed(1)" "$OVERVIEW"; then
  pass "toFixed(1) formatting in OverviewTab"
else
  fail "toFixed(1) missing from OverviewTab"
fi

# ── 13. null-safe in StandingsTab ───────────────────────────
log "Step 13: null-safe rendering in StandingsTab"

if grep -q "miles_remaining != null" "$STANDINGS"; then
  pass "null-safe check in StandingsTab"
else
  fail "null-safe check missing from StandingsTab"
fi

# ── 14. null-safe in VehiclePage ────────────────────────────
log "Step 14: null-safe rendering in VehiclePage"

if grep -q "miles_remaining != null" "$VEHICLE"; then
  pass "null-safe check in VehiclePage"
else
  fail "null-safe check missing from VehiclePage"
fi

# ── 15. null-safe in OverviewTab ────────────────────────────
log "Step 15: null-safe rendering in OverviewTab"

if grep -q "miles_remaining != null" "$OVERVIEW"; then
  pass "null-safe check in OverviewTab"
else
  fail "null-safe check missing from OverviewTab"
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
