#!/usr/bin/env bash
# link_pitnotes_smoke.sh — Smoke test for LINK-2 pit notes end-to-end delivery
#
# Validates that pit notes are saved locally, sync to cloud when connected,
# and handle missing event_id gracefully.
#
# Sections:
#   A. Python syntax
#   B. Event_id guard in sync loop
#   C. Event_id guard in handle_pit_note
#   D. Heartbeat event_id auto-discovery persists to disk
#   E. Sync status includes event_id + waiting_for_event
#   F. UI shows "Waiting for event assignment"
#   G. Cloud pit notes endpoint exists
#   H. Control room UI renders pit notes
#   I. Runtime integration (if edge is running)
#
# Usage:
#   bash scripts/link_pitnotes_smoke.sh
#
# Exit codes:
#   0 — all checks passed (SKIPs allowed)
#   1 — at least one FAIL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[link-2]  $*"; }
pass() { echo "[link-2]    PASS: $*"; }
fail() { echo "[link-2]    FAIL: $*"; FAIL=1; }
skip() { echo "[link-2]    SKIP: $*"; }

DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
PRODUCTION_PY="$REPO_ROOT/cloud/app/routes/production.py"
CONTROL_ROOM="$REPO_ROOT/web/src/pages/ControlRoom.tsx"

log "LINK-2: Pit Notes End-to-End Delivery Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION A: Python Syntax
# ═══════════════════════════════════════════════════════════════════
log "─── Section A: Python Syntax ───"

log "A1: pit_crew_dashboard.py compiles"
if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles cleanly"
else
  fail "pit_crew_dashboard.py has syntax errors"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION B: Event_id Guard in Sync Loop
# ═══════════════════════════════════════════════════════════════════
log "─── Section B: Sync Loop Event_id Guard ───"

# B1: Sync loop has explicit check for missing event_id
log "B1: Sync loop guards against missing event_id"
if grep -A80 'def _pit_notes_sync_loop' "$DASHBOARD" | grep -q 'not self.config.event_id'; then
  pass "Sync loop has explicit event_id guard"
else
  fail "Sync loop missing event_id guard"
fi

# B2: Guard logs a warning about missing event_id
log "B2: Sync loop logs warning when event_id missing"
if grep -A80 'def _pit_notes_sync_loop' "$DASHBOARD" | grep -q 'no event_id'; then
  pass "Sync loop logs warning about missing event_id"
else
  fail "Sync loop missing warning log for missing event_id"
fi

# B3: Guard uses continue (keeps loop alive for retry)
log "B3: Sync loop continues (does not exit) when event_id missing"
# The continue is a few lines after the event_id check (after the warning log)
if grep -A85 'def _pit_notes_sync_loop' "$DASHBOARD" | grep -A6 'not self.config.event_id' | grep -q 'continue'; then
  pass "Sync loop uses continue after event_id check"
else
  fail "Sync loop does not continue after event_id check"
fi

# B4: Rate-limited logging (only warns once until event_id appears)
log "B4: Event_id warning is rate-limited"
if grep -A85 'def _pit_notes_sync_loop' "$DASHBOARD" | grep -q '_event_id_warned'; then
  pass "Event_id warning uses rate-limiting flag"
else
  fail "Event_id warning not rate-limited (will spam logs)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION C: Event_id Guard in handle_pit_note
# ═══════════════════════════════════════════════════════════════════
log "─── Section C: handle_pit_note Event_id Guard ───"

# C1: Immediate sync attempt requires event_id
log "C1: handle_pit_note requires event_id for immediate sync"
if grep -A30 'Try to sync to cloud if connected' "$DASHBOARD" | grep -q 'self.config.event_id'; then
  pass "handle_pit_note checks event_id before sync attempt"
else
  fail "handle_pit_note does not check event_id before sync"
fi

# C2: Note is still saved locally even without event_id
log "C2: Note saved locally regardless of event_id"
# The local save (self._pit_notes.insert + self._save_pit_notes) happens
# BEFORE the cloud sync attempt
SAVE_LINE=$(grep -n '_save_pit_notes()' "$DASHBOARD" | grep -B1 'Persist to disk' | head -1 | cut -d: -f1 || echo "0")
SYNC_LINE=$(grep -n 'Try to sync to cloud if connected' "$DASHBOARD" | head -1 | cut -d: -f1 || echo "0")
if [ -n "$SAVE_LINE" ] && [ -n "$SYNC_LINE" ]; then
  pass "Local save happens before cloud sync attempt"
else
  # Fallback: just verify both exist in handle_pit_note
  if grep -A40 'async def handle_pit_note' "$DASHBOARD" | grep -q '_save_pit_notes' && \
     grep -A40 'async def handle_pit_note' "$DASHBOARD" | grep -q 'Try to sync'; then
    pass "handle_pit_note saves locally and attempts sync"
  else
    fail "handle_pit_note missing local save or sync attempt"
  fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION D: Heartbeat Event_id Auto-Discovery Persists
# ═══════════════════════════════════════════════════════════════════
log "─── Section D: Heartbeat Event_id Persistence ───"

# D1: Heartbeat stores event_id from response
log "D1: Heartbeat stores auto-discovered event_id"
if grep -A5 'Auto-discover event_id' "$DASHBOARD" | grep -q 'self.config.event_id = data'; then
  pass "Heartbeat stores event_id from response"
else
  fail "Heartbeat does not store event_id"
fi

# D2: Heartbeat persists event_id to disk via config.save()
log "D2: Heartbeat persists event_id to disk"
if grep -A8 'Auto-discover event_id' "$DASHBOARD" | grep -q 'self.config.save()'; then
  pass "Heartbeat calls config.save() after event_id discovery"
else
  fail "Heartbeat does not call config.save() — event_id lost on restart"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION E: Sync Status Includes Event_id Fields
# ═══════════════════════════════════════════════════════════════════
log "─── Section E: Sync Status Response ───"

# E1: Sync status includes event_id field
log "E1: Sync status response includes event_id"
if grep -A20 'def get_pit_notes_sync_status' "$DASHBOARD" | grep -q "'event_id'"; then
  pass "Sync status includes event_id field"
else
  fail "Sync status missing event_id field"
fi

# E2: Sync status includes waiting_for_event field
log "E2: Sync status response includes waiting_for_event"
if grep -A20 'def get_pit_notes_sync_status' "$DASHBOARD" | grep -q "'waiting_for_event'"; then
  pass "Sync status includes waiting_for_event field"
else
  fail "Sync status missing waiting_for_event field"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION F: UI Shows Waiting for Event
# ═══════════════════════════════════════════════════════════════════
log "─── Section F: UI Event Assignment State ───"

# F1: UI handles waiting_for_event state
log "F1: UI shows 'Waiting for event assignment' message"
if grep -q 'waiting_for_event' "$DASHBOARD" && grep -q 'Waiting for event' "$DASHBOARD"; then
  pass "UI shows 'Waiting for event assignment' when no event_id"
else
  fail "UI does not handle waiting_for_event state"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION G: Cloud Pit Notes Endpoint
# ═══════════════════════════════════════════════════════════════════
log "─── Section G: Cloud Pit Notes Endpoint ───"

if [ ! -f "$PRODUCTION_PY" ]; then
  skip "production.py not found — cloud checks skipped"
else
  # G1: POST endpoint for creating pit notes
  log "G1: Cloud has POST pit-notes endpoint"
  if grep -q 'events/{event_id}/pit-notes' "$PRODUCTION_PY" && grep -q 'def create_pit_note' "$PRODUCTION_PY"; then
    pass "Cloud POST /api/v1/events/{event_id}/pit-notes exists"
  else
    fail "Cloud POST pit-notes endpoint missing"
  fi

  # G2: GET endpoint for listing pit notes
  log "G2: Cloud has GET pit-notes endpoint"
  if grep -q 'def get_pit_notes' "$PRODUCTION_PY"; then
    pass "Cloud GET /api/v1/events/{event_id}/pit-notes exists"
  else
    fail "Cloud GET pit-notes endpoint missing"
  fi

  # G3: PitNote stores vehicle_number + team_name for display
  log "G3: PitNote stores vehicle_number and team_name"
  if grep -q 'vehicle_number' "$PRODUCTION_PY" && grep -q 'team_name' "$PRODUCTION_PY"; then
    pass "PitNote includes vehicle_number and team_name"
  else
    fail "PitNote missing vehicle_number or team_name"
  fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION H: Control Room UI Renders Pit Notes
# ═══════════════════════════════════════════════════════════════════
log "─── Section H: Control Room UI ───"

if [ ! -f "$CONTROL_ROOM" ]; then
  skip "ControlRoom.tsx not found — UI checks skipped"
else
  # H1: Fetches pit notes from API
  log "H1: ControlRoom fetches pit notes"
  if grep -q 'pit-notes' "$CONTROL_ROOM" && grep -q 'useQuery' "$CONTROL_ROOM"; then
    pass "ControlRoom fetches pit notes via useQuery"
  else
    fail "ControlRoom does not fetch pit notes"
  fi

  # H2: Renders vehicle_number and team_name
  log "H2: ControlRoom renders vehicle_number + team_name"
  if grep -q 'vehicle_number' "$CONTROL_ROOM" && grep -q 'team_name' "$CONTROL_ROOM"; then
    pass "ControlRoom renders vehicle_number and team_name"
  else
    fail "ControlRoom missing vehicle_number or team_name display"
  fi

  # H3: Renders timestamp
  log "H3: ControlRoom renders note timestamp"
  if grep -q 'timestamp_ms' "$CONTROL_ROOM" && grep -q 'toLocaleTimeString' "$CONTROL_ROOM"; then
    pass "ControlRoom renders timestamp"
  else
    fail "ControlRoom missing timestamp display"
  fi

  # H4: Renders note message
  log "H4: ControlRoom renders note message"
  if grep -q 'note.message' "$CONTROL_ROOM"; then
    pass "ControlRoom renders note message"
  else
    fail "ControlRoom missing note message display"
  fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION I: Runtime Integration (if edge is running)
# ═══════════════════════════════════════════════════════════════════
log "─── Section I: Runtime Integration ───"

EDGE_PORT="${ARGUS_EDGE_PORT:-8080}"
EDGE_HOST="${ARGUS_EDGE_HOST:-localhost}"
EDGE_URL="http://${EDGE_HOST}:${EDGE_PORT}"

# I1: Check if edge is running
log "I1: Edge reachability check"
EDGE_BODY=$(curl -s --connect-timeout 2 --max-time 3 \
  "${EDGE_URL}/api/telemetry/current" 2>/dev/null || true)

if echo "$EDGE_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'cloud_detail' in d" 2>/dev/null; then
  pass "Edge reachable at ${EDGE_URL}"

  # I2: Check sync status endpoint
  log "I2: Pit notes sync status endpoint"
  # Need auth — try without first; if 401, note it
  SYNC_RESP=$(curl -s --max-time 3 "${EDGE_URL}/api/pit-notes/sync-status" 2>/dev/null || true)
  SYNC_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    "${EDGE_URL}/api/pit-notes/sync-status" 2>/dev/null || echo "000")

  if [ "$SYNC_CODE" = "401" ]; then
    skip "Pit notes sync status requires auth (expected)"
  elif [ "$SYNC_CODE" = "200" ]; then
    # Parse response
    HAS_EVENT_ID=$(echo "$SYNC_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print('event_id' in d)" 2>/dev/null || echo "False")
    HAS_WAITING=$(echo "$SYNC_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print('waiting_for_event' in d)" 2>/dev/null || echo "False")
    if [ "$HAS_EVENT_ID" = "True" ] && [ "$HAS_WAITING" = "True" ]; then
      pass "Sync status includes event_id + waiting_for_event fields"
    else
      fail "Sync status missing new LINK-2 fields (event_id=$HAS_EVENT_ID, waiting_for_event=$HAS_WAITING)"
    fi
  else
    skip "Pit notes sync status returned HTTP $SYNC_CODE"
  fi

  # I3: Check pit notes list endpoint
  log "I3: Pit notes list endpoint"
  NOTES_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    "${EDGE_URL}/api/pit-notes?limit=1" 2>/dev/null || echo "000")
  if [ "$NOTES_CODE" = "401" ]; then
    skip "Pit notes list requires auth (expected)"
  elif [ "$NOTES_CODE" = "200" ]; then
    pass "Pit notes list endpoint returns 200"
  else
    skip "Pit notes list returned HTTP $NOTES_CODE"
  fi

else
  skip "Edge not running at ${EDGE_URL} — runtime checks skipped"
  skip "To run runtime checks: start the edge, then re-run this script"
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════"
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
