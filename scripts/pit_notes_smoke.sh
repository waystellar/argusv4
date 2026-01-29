#!/usr/bin/env bash
# pit_notes_smoke.sh — Smoke test for PIT-NOTES-1: Pit Notes End-to-End
#
# Validates (source-level):
#   1. Cloud: PitNote model exists in models.py
#   2. Cloud: POST /api/v1/events/{event_id}/pit-notes endpoint exists
#   3. Cloud: GET /api/v1/events/{event_id}/pit-notes endpoint exists
#   4. Cloud: Endpoints use X-Truck-Token auth for POST
#   5. Edge: Pit crew dashboard sends to correct endpoint
#   6. Web: Control Room has Pit Notes panel
#   7. Web: Control Room queries pit-notes endpoint
#   8. Web build passes (tsc --noEmit)
#
# Optional live tests (if env vars set):
#   9. POST a test note with curl
#  10. GET notes list and verify note is present
#
# Environment variables (for live tests):
#   ARGUS_CLOUD_BASE_URL   — Cloud API base (default: http://localhost:8000)
#   ARGUS_TEST_EVENT_ID    — Event ID for test
#   ARGUS_TEST_TRUCK_TOKEN — Truck token for auth
#   ARGUS_TEST_NOTE        — Message to send (default: "Smoke test note")
#
# Usage:
#   bash scripts/pit_notes_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODELS_PY="$REPO_ROOT/cloud/app/models.py"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"
PIT_PY="$REPO_ROOT/edge/pit_crew_dashboard.py"
CONTROL_ROOM="$REPO_ROOT/web/src/pages/ControlRoom.tsx"
FAIL=0

log()  { echo "[pit-notes]  $*"; }
pass() { echo "[pit-notes]    PASS: $*"; }
fail() { echo "[pit-notes]    FAIL: $*"; FAIL=1; }
skip() { echo "[pit-notes]    SKIP: $*"; }

# ── 1. PitNote model exists ─────────────────────────────────
log "Step 1: PitNote model in models.py"

if [ -f "$MODELS_PY" ]; then
  if grep -q 'class PitNote' "$MODELS_PY"; then
    pass "PitNote model class exists"
  else
    fail "PitNote model class missing"
  fi

  if grep -q '"pit_notes"' "$MODELS_PY"; then
    pass "pit_notes table defined"
  else
    fail "pit_notes table missing"
  fi

  if grep -q 'message = Column' "$MODELS_PY"; then
    pass "message column exists"
  else
    fail "message column missing"
  fi

  if grep -q 'timestamp_ms = Column' "$MODELS_PY"; then
    pass "timestamp_ms column exists"
  else
    fail "timestamp_ms column missing"
  fi
else
  fail "models.py not found"
fi

# ── 2. POST endpoint exists ──────────────────────────────────
log "Step 2: POST /api/v1/events/{event_id}/pit-notes endpoint"

if [ -f "$PROD_PY" ]; then
  if grep -q 'post.*pit-notes' "$PROD_PY"; then
    pass "POST pit-notes route exists"
  else
    fail "POST pit-notes route missing"
  fi

  if grep -q 'async def create_pit_note' "$PROD_PY"; then
    pass "create_pit_note function exists"
  else
    fail "create_pit_note function missing"
  fi

  if grep -q 'PitNoteCreateRequest' "$PROD_PY"; then
    pass "PitNoteCreateRequest schema exists"
  else
    fail "PitNoteCreateRequest schema missing"
  fi
else
  fail "production.py not found"
fi

# ── 3. GET endpoint exists ───────────────────────────────────
log "Step 3: GET /api/v1/events/{event_id}/pit-notes endpoint"

if [ -f "$PROD_PY" ]; then
  if grep -q 'get.*pit-notes' "$PROD_PY"; then
    pass "GET pit-notes route exists"
  else
    fail "GET pit-notes route missing"
  fi

  if grep -q 'async def get_pit_notes' "$PROD_PY"; then
    pass "get_pit_notes function exists"
  else
    fail "get_pit_notes function missing"
  fi

  if grep -q 'PitNotesListResponse' "$PROD_PY"; then
    pass "PitNotesListResponse schema exists"
  else
    fail "PitNotesListResponse schema missing"
  fi
else
  fail "production.py not found"
fi

# ── 4. POST uses X-Truck-Token auth ──────────────────────────
log "Step 4: POST endpoint uses X-Truck-Token auth"

if [ -f "$PROD_PY" ]; then
  if grep -A 30 'async def create_pit_note' "$PROD_PY" | grep -q 'X-Truck-Token'; then
    pass "create_pit_note checks X-Truck-Token"
  else
    fail "create_pit_note missing X-Truck-Token auth"
  fi
fi

# ── 5. Edge sends to correct endpoint ────────────────────────
log "Step 5: Edge pit crew dashboard sends to correct endpoint"

if [ -f "$PIT_PY" ]; then
  if grep -q '/api/v1/events.*pit-notes' "$PIT_PY"; then
    pass "Edge sends to /api/v1/events/{event_id}/pit-notes"
  else
    fail "Edge endpoint path incorrect"
  fi

  if grep -q 'X-Truck-Token' "$PIT_PY"; then
    pass "Edge sends X-Truck-Token header"
  else
    fail "Edge missing X-Truck-Token header"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 6. Control Room has Pit Notes panel ──────────────────────
log "Step 6: Control Room has Pit Notes panel"

if [ -f "$CONTROL_ROOM" ]; then
  if grep -q 'Pit Notes' "$CONTROL_ROOM"; then
    pass "Pit Notes text exists in Control Room"
  else
    fail "Pit Notes text missing from Control Room"
  fi

  if grep -q 'interface PitNote' "$CONTROL_ROOM"; then
    pass "PitNote interface defined"
  else
    fail "PitNote interface missing"
  fi

  if grep -q 'pitNotes' "$CONTROL_ROOM"; then
    pass "pitNotes variable used"
  else
    fail "pitNotes variable missing"
  fi
fi

# ── 7. Control Room queries pit-notes endpoint ───────────────
log "Step 7: Control Room queries pit-notes endpoint"

if [ -f "$CONTROL_ROOM" ]; then
  if grep -q 'pit-notes' "$CONTROL_ROOM"; then
    pass "pit-notes endpoint referenced"
  else
    fail "pit-notes endpoint not referenced"
  fi

  if grep -q "queryKey.*'pit-notes'" "$CONTROL_ROOM"; then
    pass "pit-notes query key exists"
  else
    fail "pit-notes query key missing"
  fi
fi

# ── 8. Web build passes ──────────────────────────────────────
log "Step 8: Web build (tsc --noEmit)"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$REPO_ROOT/web":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit" \
      > /tmp/pit_notes_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed. Last 20 lines:"
    tail -20 /tmp/pit_notes_build.log
  fi
elif command -v npm >/dev/null 2>&1; then
  if (cd "$REPO_ROOT/web" && npx tsc --noEmit) > /tmp/pit_notes_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed"
    tail -20 /tmp/pit_notes_build.log
  fi
else
  skip "Neither docker nor npm available"
fi

# ── 9-10. Live tests (optional) ──────────────────────────────
BASE_URL="${ARGUS_CLOUD_BASE_URL:-http://localhost:8000}"
EVENT_ID="${ARGUS_TEST_EVENT_ID:-}"
TRUCK_TOKEN="${ARGUS_TEST_TRUCK_TOKEN:-}"
TEST_NOTE="${ARGUS_TEST_NOTE:-Smoke test note at $(date +%s)}"

if [ -n "$EVENT_ID" ] && [ -n "$TRUCK_TOKEN" ]; then
  log "Step 9: POST test note"

  POST_RESP=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Truck-Token: $TRUCK_TOKEN" \
    -d "{\"vehicle_id\":\"test\",\"note\":\"$TEST_NOTE\"}" \
    "$BASE_URL/api/v1/events/$EVENT_ID/pit-notes" 2>/dev/null || echo -e "\n000")

  HTTP_CODE=$(echo "$POST_RESP" | tail -1)
  BODY=$(echo "$POST_RESP" | sed '$d')

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    pass "POST note succeeded (HTTP $HTTP_CODE)"
  else
    fail "POST note failed (HTTP $HTTP_CODE): $BODY"
  fi

  log "Step 10: GET notes and verify"

  sleep 1

  GET_RESP=$(curl -s "$BASE_URL/api/v1/events/$EVENT_ID/pit-notes?limit=10" 2>/dev/null || echo "{}")

  if echo "$GET_RESP" | grep -q "$TEST_NOTE"; then
    pass "GET notes contains test note"
  else
    fail "GET notes missing test note. Response: $GET_RESP"
  fi
else
  skip "Live tests skipped — set ARGUS_TEST_EVENT_ID and ARGUS_TEST_TRUCK_TOKEN to enable"
fi

# ── Summary ────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
