#!/usr/bin/env bash
# cloud_team_dashboard_smoke.sh - Smoke test for Cloud Team Dashboard messaging
#
# CLOUD-MANAGE-0: Validates that the Team Dashboard shows proper state messaging
# for edge discovery, connection status, and next-action guidance.
#
# Validates:
#   Edge Auto-Discovery:
#     1.  edgeUrl derived from diagnostics.edge_url (no manual entry)
#     2.  "Open Pit Crew Portal" button shown when edge_url exists
#     3.  "Edge Online" label shown when edge_url exists
#     4.  Edge URL displayed in mono font
#   Connection Status Badges:
#     5.  LIVE badge for online edge
#     6.  STALE badge for delayed edge
#     7.  OFFLINE badge for disconnected edge
#     8.  WAITING badge for unknown/never-connected edge
#   Next-Action Messaging:
#     9.  "No Event" action when no event_id
#    10.  "Waiting for Edge" action when edge never connected
#    11.  "Edge Offline" action when edge is offline
#    12.  "Start Streaming" action when video not active
#   Edge-Not-Detected Messaging:
#    13.  Shows "Edge device offline" when edge_status is offline
#    14.  Shows "Waiting for edge device" when status unknown
#    15.  No manual edge URL entry form exists
#   Diagnostics Display:
#    16.  Edge Device card shows heartbeat status
#    17.  Edge Device card shows "Edge Online" for online
#    18.  Edge Device card shows "Edge Offline" for offline
#    19.  Edge Device card shows "Waiting for edge device" for unknown
#    20.  Last Seen time displayed
#   Polling:
#    21.  Diagnostics polled every 5 seconds
#    22.  Diagnostics only polled on Ops tab
#
# Usage:
#   bash scripts/cloud_team_dashboard_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[team-dash]  $*"; }
pass() { echo "[team-dash]    PASS: $*"; }
fail() { echo "[team-dash]    FAIL: $*"; FAIL=1; }

TEAM_TSX="$REPO_ROOT/web/src/pages/TeamDashboard.tsx"

log "CLOUD-MANAGE-0: Team Dashboard Messaging Smoke Test"
echo ""

if [ ! -f "$TEAM_TSX" ]; then
  fail "TeamDashboard.tsx not found"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# EDGE AUTO-DISCOVERY
# ═══════════════════════════════════════════════════════════════════

# ── 1. edgeUrl from diagnostics (no manual entry) ─────────────────
log "Step 1: edgeUrl derived from diagnostics.edge_url"
if grep -q 'diagnostics?.edge_url' "$TEAM_TSX"; then
  pass "edgeUrl from diagnostics (auto-discovered)"
else
  fail "edgeUrl not from diagnostics"
fi

# ── 2. "Open Pit Crew Portal" button ──────────────────────────────
log "Step 2: Open Pit Crew Portal button shown when edge_url exists"
if grep -q 'Open Pit Crew Portal' "$TEAM_TSX"; then
  pass "Open Pit Crew Portal button exists"
else
  fail "Open Pit Crew Portal button missing"
fi

# ── 3. "Edge Online" label ────────────────────────────────────────
log "Step 3: Edge Online label shown when edge_url exists"
if grep -q 'Edge Online' "$TEAM_TSX"; then
  pass "Edge Online label exists"
else
  fail "Edge Online label missing"
fi

# ── 4. Edge URL displayed in mono font ────────────────────────────
log "Step 4: Edge URL displayed in mono font"
if grep -q 'font-mono.*edgeUrl\|edgeUrl.*font-mono' "$TEAM_TSX"; then
  pass "Edge URL displayed in mono font"
else
  # Check for {edgeUrl} within a mono-styled span
  if grep -q 'font-mono' "$TEAM_TSX" && grep -q '{edgeUrl}' "$TEAM_TSX"; then
    pass "Edge URL displayed in mono font"
  else
    fail "Edge URL not displayed in mono font"
  fi
fi

# ═══════════════════════════════════════════════════════════════════
# CONNECTION STATUS BADGES
# ═══════════════════════════════════════════════════════════════════

# ── 5-8. Status badges ────────────────────────────────────────────
STEP=5
for badge in LIVE STALE OFFLINE WAITING; do
  log "Step $STEP: $badge badge exists"
  if grep -q "'$badge'" "$TEAM_TSX"; then
    pass "$badge badge exists"
  else
    fail "$badge badge missing"
  fi
  STEP=$((STEP + 1))
done

# ═══════════════════════════════════════════════════════════════════
# NEXT-ACTION MESSAGING
# ═══════════════════════════════════════════════════════════════════

# ── 9. "No Event" action ──────────────────────────────────────────
log "Step 9: No Event action when no event_id"
if grep -q "'No Event'" "$TEAM_TSX"; then
  pass "No Event action label exists"
else
  fail "No Event action label missing"
fi

# ── 10. "Waiting for Edge" action ─────────────────────────────────
log "Step 10: Waiting for Edge action when edge never connected"
if grep -q "'Waiting for Edge'" "$TEAM_TSX"; then
  pass "Waiting for Edge action exists"
else
  fail "Waiting for Edge action missing"
fi

# ── 11. "Edge Offline" action ─────────────────────────────────────
log "Step 11: Edge Offline action when edge is offline"
if grep -q "'Edge Offline'" "$TEAM_TSX"; then
  pass "Edge Offline action exists"
else
  fail "Edge Offline action missing"
fi

# ── 12. "Start Streaming" action ──────────────────────────────────
log "Step 12: Start Streaming action when video not active"
if grep -q "'Start Streaming'" "$TEAM_TSX"; then
  pass "Start Streaming action exists"
else
  fail "Start Streaming action missing"
fi

# ═══════════════════════════════════════════════════════════════════
# EDGE-NOT-DETECTED MESSAGING
# ═══════════════════════════════════════════════════════════════════

# ── 13. Shows "Edge device offline" ───────────────────────────────
log "Step 13: Shows 'Edge device offline' when status is offline"
if grep -q 'Edge device offline' "$TEAM_TSX"; then
  pass "Edge device offline message exists"
else
  fail "Edge device offline message missing"
fi

# ── 14. Shows "Waiting for edge device" ───────────────────────────
log "Step 14: Shows 'Waiting for edge device' when status unknown"
if grep -q 'Waiting for edge device' "$TEAM_TSX"; then
  pass "Waiting for edge device message exists"
else
  fail "Waiting for edge device message missing"
fi

# ── 15. No manual edge URL entry form ─────────────────────────────
log "Step 15: No manual edge URL entry form exists"
if grep -qE 'type="url"|type="text".*edge.*url|setEdgeUrl|edgeUrlInput' "$TEAM_TSX"; then
  fail "Manual edge URL entry form found (should be auto-discovered)"
else
  pass "No manual edge URL entry form"
fi

# ═══════════════════════════════════════════════════════════════════
# DIAGNOSTICS DISPLAY
# ═══════════════════════════════════════════════════════════════════

# ── 16. Edge Device card shows heartbeat status ────────────────────
log "Step 16: Edge Device card shows heartbeat status"
if grep -q 'Edge Device' "$TEAM_TSX"; then
  pass "Edge Device card exists"
else
  fail "Edge Device card missing"
fi

# ── 17. Edge Online for online ─────────────────────────────────────
log "Step 17: Shows Edge Online for online status"
if grep -q 'Edge Online.*heartbeat active' "$TEAM_TSX"; then
  pass "Edge Online + heartbeat active message exists"
else
  fail "Edge Online + heartbeat active message missing"
fi

# ── 18. Edge Offline for offline ───────────────────────────────────
log "Step 18: Shows Edge Offline for offline status"
if grep -q 'Edge Offline.*no heartbeat' "$TEAM_TSX"; then
  pass "Edge Offline message exists"
else
  fail "Edge Offline message missing"
fi

# ── 19. Waiting for edge for unknown ──────────────────────────────
log "Step 19: Shows Waiting for edge for unknown status"
if grep -q 'Waiting for edge device to connect' "$TEAM_TSX"; then
  pass "Waiting for edge device to connect message exists"
else
  fail "Waiting for edge device to connect message missing"
fi

# ── 20. Last Seen time displayed ──────────────────────────────────
log "Step 20: Last Seen time displayed"
if grep -q 'Last Seen' "$TEAM_TSX"; then
  pass "Last Seen time displayed"
else
  fail "Last Seen time missing"
fi

# ═══════════════════════════════════════════════════════════════════
# POLLING
# ═══════════════════════════════════════════════════════════════════

# ── 21. Diagnostics polled every 5 seconds ─────────────────────────
log "Step 21: Diagnostics polled every 5 seconds"
if grep -q 'setInterval' "$TEAM_TSX" && grep -q '5000' "$TEAM_TSX"; then
  pass "5-second polling interval set"
else
  fail "5-second polling interval missing"
fi

# ── 22. Diagnostics only polled on Ops tab ─────────────────────────
log "Step 22: Diagnostics only polled on Ops tab"
if grep -q "activeTab === 'ops'" "$TEAM_TSX"; then
  pass "Polling gated on Ops tab"
else
  fail "Polling not gated on Ops tab"
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
