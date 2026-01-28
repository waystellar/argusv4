#!/bin/bash
#
# Pit Notes Verification Script
#
# Tests the "Send note to race control" functionality:
# - POST /api/pit-note endpoint
# - GET /api/pit-notes endpoint
# - File persistence
# - UI feedback (manual verification)
#
# Usage: bash verify_pit_notes.sh [DASHBOARD_URL]
#
# Example:
#   bash verify_pit_notes.sh                          # Uses localhost:8080
#   bash verify_pit_notes.sh http://192.168.0.18:8080 # Uses edge IP
#

DASHBOARD_URL="${1:-http://localhost:8080}"
PIT_NOTES_FILE="/opt/argus/config/pit_notes.json"

echo "========================================"
echo "  Pit Notes Verification"
echo "========================================"
echo ""
echo "Dashboard URL: $DASHBOARD_URL"
echo "Notes File: $PIT_NOTES_FILE"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Session cookie for authenticated requests
SESSION_COOKIE="pit_session=test_session"

# ========================================
# Test 1: POST /api/pit-note - Send a note
# ========================================
echo "Test 1: POST /api/pit-note"
echo "--------------------------"
TEST_NOTE="Test note from verification script $(date +%s)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Cookie: $SESSION_COOKIE" \
    -d "{\"note\": \"$TEST_NOTE\", \"ts\": $(date +%s000)}" \
    "$DASHBOARD_URL/api/pit-note" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | grep -q '"success":true\|"success": true'; then
        pass "POST /api/pit-note returns success"
    else
        fail "POST /api/pit-note response missing success flag"
        echo "     Response: $BODY"
    fi

    if echo "$BODY" | grep -q '"id"'; then
        pass "Response includes note id"
    else
        fail "Response missing note id"
    fi

    if echo "$BODY" | grep -q '"timestamp"'; then
        pass "Response includes timestamp"
    else
        fail "Response missing timestamp"
    fi

    if echo "$BODY" | grep -q '"vehicle_id"'; then
        pass "Response includes vehicle_id"
    else
        info "Response may be missing vehicle_id (older version?)"
    fi
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401) - test with valid session"
else
    fail "POST /api/pit-note returned HTTP $HTTP_CODE"
    echo "     Response: $BODY"
fi
echo ""

# ========================================
# Test 2: POST validation - empty note
# ========================================
echo "Test 2: Validation - Empty Note"
echo "--------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Cookie: $SESSION_COOKIE" \
    -d '{"note": "", "ts": 1234567890}' \
    "$DASHBOARD_URL/api/pit-note" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "400" ]]; then
    pass "Empty note rejected with HTTP 400"
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401)"
else
    fail "Empty note should be rejected (got HTTP $HTTP_CODE)"
fi
echo ""

# ========================================
# Test 3: GET /api/pit-notes - Retrieve history
# ========================================
echo "Test 3: GET /api/pit-notes"
echo "--------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Cookie: $SESSION_COOKIE" \
    "$DASHBOARD_URL/api/pit-notes" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    pass "GET /api/pit-notes returns 200"

    if echo "$BODY" | grep -q '"notes"'; then
        pass "Response includes notes array"
    else
        fail "Response missing notes array"
    fi

    if echo "$BODY" | grep -q '"total"'; then
        pass "Response includes total count"
    else
        fail "Response missing total count"
    fi

    # Check if our test note is in the response
    if echo "$BODY" | grep -q "verification script"; then
        pass "Test note found in history"
    else
        info "Test note not found in history (may have been truncated)"
    fi
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401)"
else
    fail "GET /api/pit-notes returned HTTP $HTTP_CODE"
fi
echo ""

# ========================================
# Test 4: GET with limit parameter
# ========================================
echo "Test 4: GET /api/pit-notes with limit"
echo "-------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Cookie: $SESSION_COOKIE" \
    "$DASHBOARD_URL/api/pit-notes?limit=3" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    # Count number of notes returned (simplified check)
    NOTE_COUNT=$(echo "$BODY" | grep -o '"id":' | wc -l | tr -d ' ')
    if [[ "$NOTE_COUNT" -le 3 ]]; then
        pass "Limit parameter respected ($NOTE_COUNT notes returned)"
    else
        fail "Limit parameter not working ($NOTE_COUNT notes returned, expected <=3)"
    fi
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401)"
else
    fail "GET with limit returned HTTP $HTTP_CODE"
fi
echo ""

# ========================================
# Test 5: Check file persistence
# ========================================
echo "Test 5: File Persistence"
echo "------------------------"
if [[ -f "$PIT_NOTES_FILE" ]]; then
    pass "pit_notes.json exists at $PIT_NOTES_FILE"

    # Check file is valid JSON
    if cat "$PIT_NOTES_FILE" | python3 -m json.tool > /dev/null 2>&1; then
        pass "pit_notes.json is valid JSON"
    else
        fail "pit_notes.json is not valid JSON"
    fi

    # Check if our test note is persisted
    if grep -q "verification script" "$PIT_NOTES_FILE" 2>/dev/null; then
        pass "Test note persisted to file"
    else
        info "Test note may not be persisted yet (check permissions)"
    fi

    # Show first note in file
    FIRST_NOTE=$(cat "$PIT_NOTES_FILE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['text'][:50] if d else 'empty')" 2>/dev/null)
    info "First note in file: $FIRST_NOTE..."
else
    info "pit_notes.json not found (may not have permissions or dashboard not running)"
fi
echo ""

# ========================================
# Test 6: Check dashboard HTML includes history element
# ========================================
echo "Test 6: Dashboard HTML Elements"
echo "--------------------------------"
RESPONSE=$(curl -s "$DASHBOARD_URL/" 2>&1)

if echo "$RESPONSE" | grep -q "pitNotesHistory"; then
    pass "Dashboard includes pitNotesHistory element"
else
    fail "Dashboard missing pitNotesHistory element"
fi

if echo "$RESPONSE" | grep -q "loadPitNotesHistory"; then
    pass "Dashboard includes loadPitNotesHistory function"
else
    fail "Dashboard missing loadPitNotesHistory function"
fi

if echo "$RESPONSE" | grep -q "sendPitNote"; then
    pass "Dashboard includes sendPitNote function"
else
    fail "Dashboard missing sendPitNote function"
fi

if echo "$RESPONSE" | grep -q "pit-notes-history"; then
    pass "Dashboard includes pit-notes-history CSS class"
else
    fail "Dashboard missing pit-notes-history CSS class"
fi
echo ""

# ========================================
# Summary
# ========================================
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "Pit Notes Data Flow:"
echo "  1. UI: Click send button or quick-note preset"
echo "  2. JS: sendPitNote() -> POST /api/pit-note"
echo "  3. Backend: Creates note with id, text, timestamp, vehicle_id"
echo "  4. Backend: Saves to memory list + persists to $PIT_NOTES_FILE"
echo "  5. Backend: Attempts cloud sync if connected"
echo "  6. UI: Shows success/failure feedback + refreshes history"
echo ""
echo "API Endpoints:"
echo "  POST /api/pit-note   - Send a new note"
echo "    Request: {\"note\": \"message\", \"ts\": 1234567890}"
echo "    Response: {\"success\": true, \"note\": {...}}"
echo ""
echo "  GET /api/pit-notes   - Get note history"
echo "    Query: ?limit=20 (optional, default 20, max 100)"
echo "    Response: {\"notes\": [...], \"total\": N, \"vehicle_id\": \"...\", \"event_id\": \"...\"}"
echo ""
echo "Note Fields:"
echo "  - id: Unique identifier (note_<timestamp>)"
echo "  - text: Note content"
echo "  - timestamp: Unix timestamp in ms"
echo "  - vehicle_id: Vehicle/truck identifier"
echo "  - event_id: Current event ID"
echo "  - synced: Boolean (true if synced to cloud)"
echo ""
echo "UI Feedback:"
echo "  - '⏳ Sending...' - Request in progress"
echo "  - '✓ Sent & Synced!' (green) - Saved and synced to cloud"
echo "  - '✓ Saved (offline)' (yellow) - Saved locally, not synced"
echo "  - '✗ Failed: <error>' (red) - Request failed"
echo ""
echo "Manual Verification Checklist:"
echo "  [ ] Load dashboard in browser"
echo "  [ ] Type custom note in textarea"
echo "  [ ] Click '📤 Send Note to Race Control'"
echo "  [ ] Verify button shows feedback (Sending... -> Sent/Failed)"
echo "  [ ] Verify note appears in 'Recent Notes' section"
echo "  [ ] Click quick preset button (PIT IN, FUEL, etc.)"
echo "  [ ] Verify preset note is sent and appears in history"
echo "  [ ] Refresh page, verify notes persist"
echo "  [ ] Check $PIT_NOTES_FILE on edge device"
echo ""
