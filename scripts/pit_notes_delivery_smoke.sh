#!/usr/bin/env bash
# pit_notes_delivery_smoke.sh - Smoke test for PIT-COMMS-1: Pit Notes Delivery Pipeline
#
# Validates:
#   1. Edge HTML has pit note textarea and send button
#   2. Edge JS sendPitNote() posts to /api/pit-note
#   3. Edge backend handle_pit_note() creates note with metadata
#   4. Edge backend syncs note to cloud via /api/v1/events/{eid}/pit-notes
#   5. Edge background sync loop retries unsynced notes
#   6. Edge persists notes to pit_notes.json
#   7. Cloud PitNote model exists with required columns
#   8. Cloud POST endpoint creates pit note with truck token auth
#   9. Cloud GET endpoint returns notes newest-first
#  10. ControlRoom PitNote interface matches cloud response
#  11. ControlRoom useQuery fetches pit notes with polling
#  12. ControlRoom renders notes with vehicle_number, team_name, timestamp, message
#  13. Edge getElementById('productionCamera') is null-guarded
#  14. Python syntax compiles
#
# Usage:
#   bash scripts/pit_notes_delivery_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[pit-comms]  $*"; }
pass() { echo "[pit-comms]    PASS: $*"; }
fail() { echo "[pit-comms]    FAIL: $*"; FAIL=1; }
skip() { echo "[pit-comms]    SKIP: $*"; }

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"
PRODUCTION_PY="$REPO_ROOT/cloud/app/routes/production.py"
MODELS_PY="$REPO_ROOT/cloud/app/models.py"
CONTROL_TSX="$REPO_ROOT/web/src/pages/ControlRoom.tsx"

log "PIT-COMMS-1: Pit Notes Delivery Pipeline Smoke Test"
echo ""

# ── 1. Edge HTML has pit note textarea and send button ──────
log "Step 1: Edge HTML pit note form elements"

if [ -f "$PIT_DASH" ]; then
  if grep -q 'id="pitNoteInput"' "$PIT_DASH"; then
    pass "Pit note textarea (pitNoteInput) exists"
  else
    fail "Pit note textarea (pitNoteInput) missing"
  fi

  if grep -q 'id="pitNotesHistory"' "$PIT_DASH"; then
    pass "Pit notes history container exists"
  else
    fail "Pit notes history container missing"
  fi

  if grep -q 'send-note-btn' "$PIT_DASH"; then
    pass "Send note button exists"
  else
    fail "Send note button missing"
  fi
else
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ── 2. Edge JS sendPitNote() posts to /api/pit-note ────────
log "Step 2: Edge JS sendPitNote function"

if grep -q 'async function sendPitNote' "$PIT_DASH"; then
  pass "sendPitNote() function exists"
else
  fail "sendPitNote() function missing"
fi

if grep -q "fetch('/api/pit-note'" "$PIT_DASH"; then
  pass "sendPitNote posts to /api/pit-note"
else
  fail "sendPitNote not posting to /api/pit-note"
fi

if grep -q "body: JSON.stringify.*note:" "$PIT_DASH"; then
  pass "sendPitNote sends note in request body"
else
  fail "sendPitNote not sending note in body"
fi

# ── 3. Edge backend handle_pit_note() creates note ─────────
log "Step 3: Edge backend pit note handler"

if grep -q 'async def handle_pit_note' "$PIT_DASH"; then
  pass "handle_pit_note handler exists"
else
  fail "handle_pit_note handler missing"
fi

if grep -q "'vehicle_id': self.config.vehicle_id" "$PIT_DASH"; then
  pass "Note includes vehicle_id metadata"
else
  fail "Note missing vehicle_id metadata"
fi

if grep -q "'event_id': self.config.event_id" "$PIT_DASH"; then
  pass "Note includes event_id metadata"
else
  fail "Note missing event_id metadata"
fi

if grep -q "'synced': False" "$PIT_DASH"; then
  pass "Note starts with synced=False"
else
  fail "Note not initializing synced status"
fi

# ── 4. Edge syncs note to cloud endpoint ────────────────────
log "Step 4: Edge cloud sync on send"

if grep -q '/api/v1/events/.*pit-notes' "$PIT_DASH"; then
  pass "Edge posts to cloud /api/v1/events/{eid}/pit-notes"
else
  fail "Edge not posting to cloud pit-notes endpoint"
fi

if grep -q "headers.*X-Truck-Token" "$PIT_DASH"; then
  pass "Edge sends X-Truck-Token header"
else
  fail "Edge not sending X-Truck-Token"
fi

if grep -q "'synced': True" "$PIT_DASH" || grep -q "note\['synced'\] = True" "$PIT_DASH"; then
  pass "Edge marks note synced on success"
else
  fail "Edge not marking note synced"
fi

# ── 5. Edge background sync loop ───────────────────────────
log "Step 5: Background sync loop for unsynced notes"

if grep -q '_pit_notes_sync_loop' "$PIT_DASH"; then
  pass "Background sync loop exists"
else
  fail "Background sync loop missing"
fi

if grep -q "not n.get('synced'" "$PIT_DASH"; then
  pass "Sync loop finds unsynced notes"
else
  fail "Sync loop not finding unsynced notes"
fi

if grep -q 'asyncio.sleep(30)' "$PIT_DASH"; then
  pass "Sync loop retries every 30 seconds"
else
  fail "Sync loop retry interval missing"
fi

# ── 6. Edge persists notes to pit_notes.json ────────────────
log "Step 6: Edge note persistence"

if grep -q 'pit_notes.json' "$PIT_DASH"; then
  pass "Notes persisted to pit_notes.json"
else
  fail "No pit_notes.json persistence"
fi

if grep -q '_save_pit_notes' "$PIT_DASH"; then
  pass "_save_pit_notes function exists"
else
  fail "_save_pit_notes missing"
fi

if grep -q '_load_pit_notes' "$PIT_DASH"; then
  pass "_load_pit_notes function exists"
else
  fail "_load_pit_notes missing"
fi

# ── 7. Cloud PitNote model ──────────────────────────────────
log "Step 7: Cloud PitNote database model"

if [ -f "$MODELS_PY" ]; then
  if grep -q 'class PitNote' "$MODELS_PY"; then
    pass "PitNote model exists"
  else
    fail "PitNote model missing"
  fi

  for col in note_id event_id vehicle_id vehicle_number team_name message timestamp_ms created_at; do
    if grep -q "$col.*Column" "$MODELS_PY" | head -1 && grep -A20 'class PitNote' "$MODELS_PY" | grep -q "$col"; then
      pass "PitNote has $col column"
    elif grep -A20 'class PitNote' "$MODELS_PY" | grep -q "$col"; then
      pass "PitNote has $col column"
    else
      fail "PitNote missing $col column"
    fi
  done

  if grep -q 'idx_pit_notes_event' "$MODELS_PY"; then
    pass "PitNote has event index"
  else
    fail "PitNote missing event index"
  fi
else
  fail "models.py not found"
fi

# ── 8. Cloud POST endpoint ──────────────────────────────────
log "Step 8: Cloud POST /pit-notes endpoint"

if [ -f "$PRODUCTION_PY" ]; then
  if grep -q 'post.*pit-notes' "$PRODUCTION_PY"; then
    pass "POST /pit-notes endpoint exists"
  else
    fail "POST /pit-notes endpoint missing"
  fi

  if grep -q 'X-Truck-Token' "$PRODUCTION_PY"; then
    pass "Endpoint validates X-Truck-Token"
  else
    fail "Endpoint not validating truck token"
  fi

  if grep -q 'class PitNoteCreateRequest' "$PRODUCTION_PY"; then
    pass "PitNoteCreateRequest schema exists"
  else
    fail "PitNoteCreateRequest schema missing"
  fi

  if grep -q 'class PitNoteResponse' "$PRODUCTION_PY"; then
    pass "PitNoteResponse schema exists"
  else
    fail "PitNoteResponse schema missing"
  fi

  # Check required fields in create request
  if grep -A5 'class PitNoteCreateRequest' "$PRODUCTION_PY" | grep -q 'vehicle_id: str'; then
    pass "Create request has vehicle_id field"
  else
    fail "Create request missing vehicle_id"
  fi

  if grep -A5 'class PitNoteCreateRequest' "$PRODUCTION_PY" | grep -q 'note: str'; then
    pass "Create request has note field"
  else
    fail "Create request missing note field"
  fi
else
  fail "production.py not found"
fi

# ── 9. Cloud GET endpoint returns notes newest-first ────────
log "Step 9: Cloud GET /pit-notes endpoint"

if [ -f "$PRODUCTION_PY" ]; then
  if grep -q 'get.*pit-notes' "$PRODUCTION_PY"; then
    pass "GET /pit-notes endpoint exists"
  else
    fail "GET /pit-notes endpoint missing"
  fi

  if grep -q 'timestamp_ms.desc()' "$PRODUCTION_PY"; then
    pass "Notes ordered newest-first"
  else
    fail "Notes not ordered newest-first"
  fi

  if grep -q 'class PitNotesListResponse' "$PRODUCTION_PY"; then
    pass "PitNotesListResponse schema exists"
  else
    fail "PitNotesListResponse schema missing"
  fi
fi

# ── 10. ControlRoom PitNote interface ───────────────────────
log "Step 10: ControlRoom PitNote TypeScript interface"

if [ -f "$CONTROL_TSX" ]; then
  if grep -q 'interface PitNote' "$CONTROL_TSX"; then
    pass "PitNote interface defined"
  else
    fail "PitNote interface missing"
  fi

  for field in note_id vehicle_id vehicle_number team_name message timestamp_ms; do
    if grep -A15 'interface PitNote' "$CONTROL_TSX" | grep -q "$field"; then
      pass "PitNote interface has $field"
    else
      fail "PitNote interface missing $field"
    fi
  done

  if grep -q 'interface PitNotesResponse' "$CONTROL_TSX"; then
    pass "PitNotesResponse interface defined"
  else
    fail "PitNotesResponse interface missing"
  fi
else
  fail "ControlRoom.tsx not found"
fi

# ── 11. ControlRoom fetches pit notes with polling ──────────
log "Step 11: ControlRoom pit notes polling"

if [ -f "$CONTROL_TSX" ]; then
  if grep -q "queryKey.*pit-notes" "$CONTROL_TSX"; then
    pass "useQuery for pit-notes exists"
  else
    fail "useQuery for pit-notes missing"
  fi

  if grep -q 'pit-notes.*limit=' "$CONTROL_TSX"; then
    pass "Fetch includes limit parameter"
  else
    fail "Fetch missing limit parameter"
  fi

  if grep -q 'refetchInterval.*10000' "$CONTROL_TSX"; then
    pass "Polls every 10 seconds"
  else
    fail "Not polling every 10 seconds"
  fi
fi

# ── 12. ControlRoom renders notes with author + timestamp ───
log "Step 12: ControlRoom pit notes display"

if [ -f "$CONTROL_TSX" ]; then
  if grep -q 'Pit Notes' "$CONTROL_TSX"; then
    pass "Pit Notes panel title exists"
  else
    fail "Pit Notes panel missing"
  fi

  if grep -q 'note.vehicle_number' "$CONTROL_TSX"; then
    pass "Displays vehicle number"
  else
    fail "Not displaying vehicle number"
  fi

  if grep -q 'note.team_name' "$CONTROL_TSX"; then
    pass "Displays team name"
  else
    fail "Not displaying team name"
  fi

  if grep -q 'note.timestamp_ms' "$CONTROL_TSX"; then
    pass "Displays timestamp"
  else
    fail "Not displaying timestamp"
  fi

  if grep -q 'note.message' "$CONTROL_TSX"; then
    pass "Displays note message"
  else
    fail "Not displaying note message"
  fi

  if grep -q 'No pit notes' "$CONTROL_TSX"; then
    pass "Empty state message exists"
  else
    fail "Empty state message missing"
  fi
fi

# ── 13. Edge getElementById null guard ──────────────────────
log "Step 13: Edge productionCamera null guard"

if grep -q "getElementById('productionCamera')" "$PIT_DASH"; then
  if grep -q "const prodCamEl = document.getElementById('productionCamera')" "$PIT_DASH"; then
    pass "productionCamera access is null-guarded"
  else
    fail "productionCamera not null-guarded (console error source)"
  fi
else
  pass "productionCamera reference removed or guarded"
fi

# ── 14. Python syntax compiles ──────────────────────────────
log "Step 14: Python syntax compiles"

for pyfile in "$PIT_DASH" "$PRODUCTION_PY" "$MODELS_PY"; do
  if [ -f "$pyfile" ]; then
    basename=$(basename "$pyfile")
    if python3 -m py_compile "$pyfile" 2>/dev/null; then
      pass "$basename compiles"
    else
      fail "$basename has syntax errors"
    fi
  fi
done

# ── 15. PIT-COMMS-1 markers ────────────────────────────────
log "Step 15: PIT-COMMS-1 / PIT-NOTES-1 markers"

for file in "$PIT_DASH" "$PRODUCTION_PY" "$CONTROL_TSX"; do
  if [ -f "$file" ]; then
    basename=$(basename "$file")
    if grep -q 'PIT-COMMS-1\|PIT-NOTES-1' "$file"; then
      pass "$basename has PIT-COMMS/NOTES marker"
    else
      fail "$basename missing PIT-COMMS/NOTES marker"
    fi
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
