#!/usr/bin/env bash
# team_redirect_edge_smoke.sh — Smoke test for Edge Auto-Discovery & Fan View
#
# Validates that the Team Dashboard auto-discovers edge URL from diagnostics
# (no manual URL entry, no localStorage, no redirect countdown) and that
# Preview Fan View works correctly.
#
# Validates:
#   Edge Auto-Discovery:
#     1.  edgeUrl derived from diagnostics.edge_url (auto-discovered)
#     2.  No manual edge URL entry form (no localStorage, no EDGE_URL_STORAGE_KEY)
#     3.  No redirect countdown (no redirectCountdown, no handleCancelRedirect)
#     4.  "Open Pit Crew Portal" button shown when edge_url exists
#     5.  Edge URL displayed in mono font
#   Edge Status Messaging:
#     6.  "Edge Online" label when edge is connected
#     7.  "Edge device offline" when edge_status is offline
#     8.  "Waiting for edge device" when status unknown
#   Preview Fan View:
#     9.  Preview Fan View text exists
#    10.  Link uses /events/{event_id}/vehicles/{vehicle_id}
#    11.  Opens in new tab (target=_blank)
#    12.  Has noopener noreferrer security attrs
#
# Usage:
#   bash scripts/team_redirect_edge_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEAM_DASH="$REPO_ROOT/web/src/pages/TeamDashboard.tsx"
FAIL=0

log()  { echo "[redirect-edge]  $*"; }
pass() { echo "[redirect-edge]    PASS: $*"; }
fail() { echo "[redirect-edge]    FAIL: $*"; FAIL=1; }

if [ ! -f "$TEAM_DASH" ]; then
  fail "TeamDashboard.tsx not found"
  exit 1
fi

log "Edge Auto-Discovery & Fan View Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# EDGE AUTO-DISCOVERY
# ═══════════════════════════════════════════════════════════════════

# ── 1. edgeUrl from diagnostics.edge_url ────────────────────────
log "Step 1: edgeUrl derived from diagnostics.edge_url"
if grep -q 'diagnostics?.edge_url' "$TEAM_DASH"; then
  pass "edgeUrl from diagnostics (auto-discovered)"
else
  fail "edgeUrl not from diagnostics"
fi

# ── 2. No manual edge URL entry ────────────────────────────────
log "Step 2: No manual edge URL entry (no localStorage)"
if grep -qE 'EDGE_URL_STORAGE_KEY|localStorage.*edge.*url|handleSaveEdgeUrl|isValidEdgeUrl' "$TEAM_DASH"; then
  fail "Manual edge URL entry found (should be auto-discovered)"
else
  pass "No manual edge URL entry"
fi

# ── 3. No redirect countdown ───────────────────────────────────
log "Step 3: No redirect countdown"
# Exclude comments (lines starting with * or //) when checking
if grep -v '^\s*[*/]' "$TEAM_DASH" | grep -qE 'redirectCountdown|handleCancelRedirect'; then
  fail "Redirect countdown found (should use direct portal link)"
else
  pass "No redirect countdown"
fi

# ── 4. Open Pit Crew Portal button ─────────────────────────────
log "Step 4: Open Pit Crew Portal button"
if grep -q 'Open Pit Crew Portal' "$TEAM_DASH"; then
  pass "Open Pit Crew Portal button exists"
else
  fail "Open Pit Crew Portal button missing"
fi

# ── 5. Edge URL in mono font ───────────────────────────────────
log "Step 5: Edge URL displayed in mono font"
if grep -q 'font-mono' "$TEAM_DASH" && grep -q '{edgeUrl}' "$TEAM_DASH"; then
  pass "Edge URL displayed in mono font"
else
  fail "Edge URL not in mono font"
fi

# ═══════════════════════════════════════════════════════════════════
# EDGE STATUS MESSAGING
# ═══════════════════════════════════════════════════════════════════

# ── 6. Edge Online label ───────────────────────────────────────
log "Step 6: Edge Online label when connected"
if grep -q 'Edge Online' "$TEAM_DASH"; then
  pass "Edge Online label exists"
else
  fail "Edge Online label missing"
fi

# ── 7. Edge device offline message ─────────────────────────────
log "Step 7: Edge device offline when status is offline"
if grep -q 'Edge device offline' "$TEAM_DASH"; then
  pass "Edge device offline message exists"
else
  fail "Edge device offline message missing"
fi

# ── 8. Waiting for edge device message ─────────────────────────
log "Step 8: Waiting for edge device when status unknown"
if grep -q 'Waiting for edge device' "$TEAM_DASH"; then
  pass "Waiting for edge device message exists"
else
  fail "Waiting for edge device message missing"
fi

# ═══════════════════════════════════════════════════════════════════
# PREVIEW FAN VIEW
# ═══════════════════════════════════════════════════════════════════

# ── 9. Preview Fan View text ───────────────────────────────────
log "Step 9: Preview Fan View text exists"
if grep -q 'Preview Fan View' "$TEAM_DASH"; then
  pass "Preview Fan View text exists"
else
  fail "Preview Fan View text missing"
fi

# ── 10. Link uses correct route ────────────────────────────────
log "Step 10: Link uses /events/{event_id}/vehicles/{vehicle_id}"
if grep -q '/events/\${data.event_id}/vehicles/\${data.vehicle_id}' "$TEAM_DASH"; then
  pass "Link uses correct route format"
else
  fail "Link has wrong route format"
fi

# ── 11. Opens in new tab ──────────────────────────────────────
log "Step 11: Preview Fan View opens in new tab"
if grep -B 15 'Preview Fan View' "$TEAM_DASH" | grep -q 'target="_blank"'; then
  pass "Opens in new tab (target=_blank)"
else
  fail "Missing target=_blank"
fi

# ── 12. Security attributes ───────────────────────────────────
log "Step 12: Preview Fan View has noopener noreferrer"
if grep -B 15 'Preview Fan View' "$TEAM_DASH" | grep -q 'noopener noreferrer'; then
  pass "Has noopener noreferrer"
else
  fail "Missing noopener noreferrer"
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
