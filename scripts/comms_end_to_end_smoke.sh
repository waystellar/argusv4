#!/usr/bin/env bash
# comms_end_to_end_smoke.sh - Smoke test for PIT-COMMS-1: Pit Notes End-to-End
#
# Validates:
#   1. Edge: Background sync loop exists
#   2. Edge: Sync status endpoint exists
#   3. Edge: UI shows "Queued (will sync)" instead of "Saved (offline)"
#   4. Cloud: POST /api/v1/events/{event_id}/pit-notes endpoint exists
#   5. Cloud: GET /api/v1/events/{event_id}/pit-notes endpoint exists
#   6. Cloud: PitNote model exists
#   7. Web: ControlRoom fetches pit notes
#   8. Python syntax compiles
#
# Usage:
#   bash scripts/comms_end_to_end_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
MODELS_PY="$REPO_ROOT/cloud/app/models.py"
CONTROL_ROOM="$REPO_ROOT/web/src/pages/ControlRoom.tsx"
FAIL=0

log()  { echo "[pit-comms]  $*"; }
pass() { echo "[pit-comms]    PASS: $*"; }
fail() { echo "[pit-comms]    FAIL: $*"; FAIL=1; }
skip() { echo "[pit-comms]    SKIP: $*"; }

log "PIT-COMMS-1: Pit Notes End-to-End Smoke Test"
echo ""

# ── 1. Edge: Background sync loop exists ────────────────────────
log "Step 1: Edge background sync loop exists"

if [ -f "$PIT_DASH" ]; then
  if grep -q '_pit_notes_sync_loop' "$PIT_DASH"; then
    pass "_pit_notes_sync_loop method exists"
  else
    fail "_pit_notes_sync_loop method missing"
  fi

  if grep -q 'asyncio.create_task.*_pit_notes_sync_loop' "$PIT_DASH"; then
    pass "Background sync task is started"
  else
    fail "Background sync task not started"
  fi

  if grep -q 'PIT-COMMS-1.*Background' "$PIT_DASH"; then
    pass "PIT-COMMS-1 marker present in sync loop"
  else
    fail "PIT-COMMS-1 marker missing"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. Edge: Sync status endpoint exists ────────────────────────
log "Step 2: Edge sync status endpoint exists"

if [ -f "$PIT_DASH" ]; then
  if grep -q '/api/pit-notes/sync-status' "$PIT_DASH"; then
    pass "Sync status endpoint route registered"
  else
    fail "Sync status endpoint route missing"
  fi

  if grep -q 'handle_pit_notes_sync_status' "$PIT_DASH"; then
    pass "Sync status handler exists"
  else
    fail "Sync status handler missing"
  fi

  if grep -q 'get_pit_notes_sync_status' "$PIT_DASH"; then
    pass "Sync status helper method exists"
  else
    fail "Sync status helper method missing"
  fi
fi

# ── 3. Edge: UI shows "Queued" status ───────────────────────────
log "Step 3: Edge UI shows 'Queued (will sync)' status"

if [ -f "$PIT_DASH" ]; then
  if grep -q 'Queued (will sync)' "$PIT_DASH"; then
    pass "UI shows 'Queued (will sync)' for unsynced notes"
  else
    fail "UI missing 'Queued (will sync)' text"
  fi

  # Verify old "Saved (offline)" is removed
  if grep -q "Saved (offline)" "$PIT_DASH"; then
    fail "Old 'Saved (offline)' text still present"
  else
    pass "Old 'Saved (offline)' text removed"
  fi

  if grep -q 'pitNotesCloudStatus' "$PIT_DASH"; then
    pass "Cloud status indicator element exists"
  else
    fail "Cloud status indicator element missing"
  fi

  if grep -q 'pitNotesQueueCount' "$PIT_DASH"; then
    pass "Queue count indicator element exists"
  else
    fail "Queue count indicator element missing"
  fi
fi

# ── 4. Cloud: POST pit-notes endpoint exists ────────────────────
log "Step 4: Cloud POST pit-notes endpoint exists"

if [ -f "$PROD_PY" ]; then
  if grep -q '@events_router.post.*/pit-notes' "$PROD_PY"; then
    pass "POST /pit-notes endpoint route exists"
  else
    fail "POST /pit-notes endpoint route missing"
  fi

  if grep -q 'async def create_pit_note' "$PROD_PY"; then
    pass "create_pit_note handler exists"
  else
    fail "create_pit_note handler missing"
  fi

  if grep -q 'X-Truck-Token' "$PROD_PY"; then
    pass "Truck token authentication present"
  else
    fail "Truck token authentication missing"
  fi
else
  fail "production.py not found"
fi

# ── 5. Cloud: GET pit-notes endpoint exists ─────────────────────
log "Step 5: Cloud GET pit-notes endpoint exists"

if [ -f "$PROD_PY" ]; then
  if grep -q '@events_router.get.*/pit-notes' "$PROD_PY"; then
    pass "GET /pit-notes endpoint route exists"
  else
    fail "GET /pit-notes endpoint route missing"
  fi

  if grep -q 'async def get_pit_notes' "$PROD_PY"; then
    pass "get_pit_notes handler exists"
  else
    fail "get_pit_notes handler missing"
  fi
fi

# ── 6. Cloud: PitNote model exists ──────────────────────────────
log "Step 6: Cloud PitNote model exists"

if [ -f "$MODELS_PY" ]; then
  if grep -q 'class PitNote' "$MODELS_PY"; then
    pass "PitNote model class exists"
  else
    fail "PitNote model class missing"
  fi

  if grep -q '__tablename__ = "pit_notes"' "$MODELS_PY"; then
    pass "pit_notes table defined"
  else
    fail "pit_notes table not defined"
  fi

  if grep -q 'message = Column' "$MODELS_PY"; then
    pass "PitNote has message column"
  else
    fail "PitNote missing message column"
  fi
else
  fail "models.py not found"
fi

# ── 7. Web: ControlRoom fetches pit notes ───────────────────────
log "Step 7: Web ControlRoom fetches pit notes"

if [ -f "$CONTROL_ROOM" ]; then
  if grep -q 'pit-notes' "$CONTROL_ROOM"; then
    pass "ControlRoom references pit-notes"
  else
    fail "ControlRoom missing pit-notes reference"
  fi

  # Check for queryKey with pit-notes (React Query pattern uses separate line)
  if grep -q "queryKey.*pit-notes" "$CONTROL_ROOM"; then
    pass "ControlRoom queries pit-notes (queryKey found)"
  elif grep -q "useQuery.*pit-notes" "$CONTROL_ROOM"; then
    pass "ControlRoom queries pit-notes (inline pattern)"
  else
    fail "ControlRoom missing pit-notes query"
  fi

  if grep -q 'Pit Notes' "$CONTROL_ROOM"; then
    pass "ControlRoom has 'Pit Notes' panel"
  else
    fail "ControlRoom missing 'Pit Notes' panel"
  fi
else
  fail "ControlRoom.tsx not found"
fi

# ── 8. Python syntax check ──────────────────────────────────────
log "Step 8: Python syntax compiles"

if python3 -m py_compile "$PIT_DASH" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles without syntax errors"
else
  fail "pit_crew_dashboard.py has syntax errors"
fi

if python3 -m py_compile "$PROD_PY" 2>/dev/null; then
  pass "production.py compiles without syntax errors"
else
  fail "production.py has syntax errors"
fi

if python3 -m py_compile "$MODELS_PY" 2>/dev/null; then
  pass "models.py compiles without syntax errors"
else
  fail "models.py has syntax errors"
fi

# ── 9. Edge: Retry unsynced notes on sync ───────────────────────
log "Step 9: Edge retries unsynced notes"

if [ -f "$PIT_DASH" ]; then
  if grep -A 50 '_pit_notes_sync_loop' "$PIT_DASH" | grep -q "synced.*False"; then
    pass "Sync loop finds unsynced notes"
  else
    fail "Sync loop missing unsynced notes filter"
  fi

  if grep -A 50 '_pit_notes_sync_loop' "$PIT_DASH" | grep -q "asyncio.sleep(30)"; then
    pass "Sync loop runs every 30 seconds"
  else
    fail "Sync loop missing 30 second interval"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
