#!/usr/bin/env bash
# pit_camera_preview_smoke.sh — Smoke test for PIT-CAM-PREVIEW (Ubuntu-friendly, no npm)
#
# Validates the camera preview feature end-to-end:
#   Section A: Endpoint registration — routes exist in code for all 4 canonical roles
#   Section B: Live endpoint check — if edge server is running, curl each endpoint
#              and verify structured responses (not random 404 pages)
#   Section C: UI/template references — frontend JS uses new /api/cameras/preview/ paths
#   Section D: Python syntax check — modified Python files compile cleanly
#
# Usage:
#   bash scripts/pit_camera_preview_smoke.sh            # offline + live if server up
#   PIT_CREW_URL=http://192.168.1.10:8080 bash scripts/pit_camera_preview_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0
WARN=0

log()  { echo "[cam-preview]  $*"; }
pass() { echo "[cam-preview]    PASS: $*"; }
fail() { echo "[cam-preview]    FAIL: $*"; FAIL=1; }
warn() { echo "[cam-preview]    WARN: $*"; WARN=1; }
skip() { echo "[cam-preview]    SKIP: $*"; }

DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
ROLES=(main cockpit chase suspension)

# Default edge URL (overridable via env)
PIT_CREW_URL="${PIT_CREW_URL:-http://localhost:8080}"

log "PIT-CAM-PREVIEW: Camera Preview Smoke Test (Ubuntu-friendly)"
echo ""

if [ ! -f "$DASHBOARD" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION A: Endpoint Registration (grep-based, always runs)
# ═══════════════════════════════════════════════════════════════════
log "─── Section A: Endpoint Registration ───"

# ── A1. GET /api/cameras/preview/{camera}.jpg route registered ────
log "A1: GET preview route registered"
if grep -q "add_get.*'/api/cameras/preview/{camera}.jpg'" "$DASHBOARD"; then
  pass "GET /api/cameras/preview/{camera}.jpg route registered"
else
  fail "GET /api/cameras/preview/{camera}.jpg route missing"
fi

# ── A2. POST /api/cameras/preview/{camera}/capture route registered
log "A2: POST preview capture route registered"
if grep -q "add_post.*'/api/cameras/preview/{camera}/capture'" "$DASHBOARD"; then
  pass "POST /api/cameras/preview/{camera}/capture route registered"
else
  fail "POST /api/cameras/preview/{camera}/capture route missing"
fi

# ── A3. GET handler returns structured responses (not random pages)
log "A3: GET handler returns structured 404 for missing screenshots"
if grep -A15 'async def handle_camera_screenshot' "$DASHBOARD" | grep -q "No screenshot available"; then
  pass "GET handler returns descriptive 404 text (not generic page)"
else
  fail "GET handler missing structured 404 response"
fi

# ── A4. POST handler returns JSON response ────────────────────────
log "A4: POST capture handler returns JSON"
if grep -A20 'async def handle_capture_screenshot' "$DASHBOARD" | grep -q 'web.json_response'; then
  pass "POST capture handler returns JSON response"
else
  fail "POST capture handler missing JSON response"
fi

# ── A5. Handlers accept all 4 canonical roles via _normalize_camera_slot
log "A5: Handlers normalize camera slot names"
if grep -A5 'async def handle_camera_screenshot' "$DASHBOARD" | grep -q '_normalize_camera_slot'; then
  pass "GET handler normalizes camera slot"
else
  fail "GET handler missing _normalize_camera_slot"
fi
if grep -A5 'async def handle_capture_screenshot' "$DASHBOARD" | grep -q '_normalize_camera_slot'; then
  pass "POST handler normalizes camera slot"
else
  fail "POST handler missing _normalize_camera_slot"
fi

# ── A6. All 4 canonical roles in fallback device map ──────────────
log "A6: All 4 canonical roles in _get_camera_device fallback map"
FOUND=0
for role in "${ROLES[@]}"; do
  if grep -A20 'def _get_camera_device' "$DASHBOARD" | grep -q "\"$role\":"; then
    FOUND=$((FOUND + 1))
  fi
done
if [ "$FOUND" -eq 4 ]; then
  pass "All 4 roles (main/cockpit/chase/suspension) in fallback map"
else
  fail "Only $FOUND/4 roles in fallback map"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION B: Live Endpoint Check (curl-based, skipped if server down)
# ═══════════════════════════════════════════════════════════════════
log "─── Section B: Live Endpoint Check ───"

SERVER_UP=false
if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$PIT_CREW_URL/" >/dev/null 2>&1; then
  SERVER_UP=true
  log "Edge server detected at $PIT_CREW_URL"
else
  log "Edge server not running at $PIT_CREW_URL — live checks will be skipped"
fi

if [ "$SERVER_UP" = true ]; then
  # Try to get a session cookie (unauthenticated requests return 401)
  # If auth is needed, the test still validates response structure
  COOKIE_JAR=$(mktemp)
  trap "rm -f $COOKIE_JAR" EXIT

  for role in "${ROLES[@]}"; do
    # ── B-GET: GET /api/cameras/preview/<role>.jpg ──────────────────
    log "B-GET-$role: GET /api/cameras/preview/$role.jpg"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
      -b "$COOKIE_JAR" \
      "$PIT_CREW_URL/api/cameras/preview/$role.jpg" 2>/dev/null || echo "000")

    case "$HTTP_CODE" in
      200)
        # Verify Content-Type is image/jpeg
        CT=$(curl -s -o /dev/null -w "%{content_type}" --connect-timeout 3 \
          -b "$COOKIE_JAR" \
          "$PIT_CREW_URL/api/cameras/preview/$role.jpg" 2>/dev/null || echo "")
        if echo "$CT" | grep -qi "image/jpeg"; then
          pass "GET $role.jpg -> 200 image/jpeg"
        else
          warn "GET $role.jpg -> 200 but Content-Type=$CT (expected image/jpeg)"
        fi
        ;;
      404)
        # Check it's our controlled 404 (text/plain), not a framework 404
        BODY=$(curl -s --connect-timeout 3 \
          -b "$COOKIE_JAR" \
          "$PIT_CREW_URL/api/cameras/preview/$role.jpg" 2>/dev/null || echo "")
        if echo "$BODY" | grep -qi "No screenshot available\|Camera not found"; then
          pass "GET $role.jpg -> 404 controlled (camera offline or no capture yet)"
        else
          fail "GET $role.jpg -> 404 but uncontrolled response: $BODY"
        fi
        ;;
      401)
        skip "GET $role.jpg -> 401 (auth required, cannot test content)"
        ;;
      000)
        warn "GET $role.jpg -> connection failed"
        ;;
      *)
        fail "GET $role.jpg -> unexpected HTTP $HTTP_CODE"
        ;;
    esac

    # ── B-POST: POST /api/cameras/preview/<role>/capture ───────────
    log "B-POST-$role: POST /api/cameras/preview/$role/capture"
    RESP=$(curl -s -w "\n%{http_code}" --connect-timeout 5 -X POST \
      -b "$COOKIE_JAR" \
      "$PIT_CREW_URL/api/cameras/preview/$role/capture" 2>/dev/null || echo -e "\n000")
    BODY=$(echo "$RESP" | head -n -1)
    CODE=$(echo "$RESP" | tail -1)

    case "$CODE" in
      200)
        # Verify JSON with 'success' key
        if echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'success' in d" 2>/dev/null; then
          pass "POST $role/capture -> 200 JSON with 'success' key"
        else
          fail "POST $role/capture -> 200 but response is not valid JSON with 'success'"
        fi
        ;;
      404)
        if echo "$BODY" | grep -qi "Camera not found"; then
          pass "POST $role/capture -> 404 controlled (camera not configured)"
        else
          fail "POST $role/capture -> 404 but uncontrolled response"
        fi
        ;;
      401)
        skip "POST $role/capture -> 401 (auth required)"
        ;;
      500)
        # 500 with JSON error is acceptable (camera error)
        if echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'success' in d or 'error' in d" 2>/dev/null; then
          warn "POST $role/capture -> 500 JSON error (camera issue): $(echo "$BODY" | head -c 100)"
        else
          fail "POST $role/capture -> 500 unstructured error"
        fi
        ;;
      000)
        warn "POST $role/capture -> connection failed"
        ;;
      *)
        fail "POST $role/capture -> unexpected HTTP $CODE"
        ;;
    esac
  done
else
  for role in "${ROLES[@]}"; do
    skip "B-GET-$role: server not running"
    skip "B-POST-$role: server not running"
  done
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION C: UI/Template References (grep-based, always runs)
# ═══════════════════════════════════════════════════════════════════
log "─── Section C: UI/Template References ───"

# ── C1. Frontend JS thumbnail grid references /api/cameras/preview/
log "C1: Frontend JS thumbnail uses /api/cameras/preview/ path"
if grep "img.src" "$DASHBOARD" | grep -q "/api/cameras/preview/"; then
  pass "Thumbnail img.src uses /api/cameras/preview/"
else
  fail "Thumbnail img.src not using /api/cameras/preview/"
fi

# ── C2. Frontend JS manual capture uses /api/cameras/preview/
log "C2: Frontend JS capture button uses /api/cameras/preview/ path"
if grep "fetch.*'/api/cameras/preview/" "$DASHBOARD" | grep -q "/capture"; then
  pass "Manual capture fetch uses /api/cameras/preview/.../capture"
else
  fail "Manual capture fetch not using /api/cameras/preview/"
fi

# ── C3. Frontend JS references all 4 canonical roles in camera grid
log "C3: Camera grid references all 4 canonical roles"
GRID_ROLES=0
for role in "${ROLES[@]}"; do
  if grep -q "'$role'" "$DASHBOARD"; then
    GRID_ROLES=$((GRID_ROLES + 1))
  fi
done
if [ "$GRID_ROLES" -eq 4 ]; then
  pass "All 4 canonical roles referenced in dashboard"
else
  fail "Only $GRID_ROLES/4 canonical roles referenced"
fi

# ── C4. Status endpoint URL uses /api/cameras/preview/ path
log "C4: Status response screenshot_url uses /api/cameras/preview/"
if grep 'screenshot_url' "$DASHBOARD" | grep -q '/api/cameras/preview/'; then
  pass "Status response uses /api/cameras/preview/ URL"
else
  fail "Status response not using /api/cameras/preview/ URL"
fi

# ── C5. No stale /api/cameras/screenshot/ in frontend-facing JS
log "C5: No stale /api/cameras/screenshot/ in frontend JS"
# Only check JS string contexts (lines with quotes), exclude route registration
STALE=$(grep "/api/cameras/screenshot/" "$DASHBOARD" | grep -v "add_get\|add_post\|add_route" | grep -c "'" || true)
if [ "$STALE" -eq 0 ]; then
  pass "No stale /api/cameras/screenshot/ in frontend JS"
else
  fail "$STALE stale /api/cameras/screenshot/ reference(s) in frontend JS"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SECTION D: Python Syntax Check (always runs)
# ═══════════════════════════════════════════════════════════════════
log "─── Section D: Python Syntax Check ───"

# ── D1. pit_crew_dashboard.py compiles cleanly
log "D1: pit_crew_dashboard.py syntax"
if python3 -m py_compile "$DASHBOARD" 2>/tmp/pycheck_dashboard.txt; then
  pass "pit_crew_dashboard.py compiles cleanly"
else
  fail "pit_crew_dashboard.py has syntax errors: $(cat /tmp/pycheck_dashboard.txt)"
fi

# ── D2. Check any other modified edge Python files
for pyfile in "$REPO_ROOT"/edge/*.py; do
  if [ -f "$pyfile" ] && [ "$pyfile" != "$DASHBOARD" ]; then
    BASENAME=$(basename "$pyfile")
    log "D2: $BASENAME syntax"
    if python3 -m py_compile "$pyfile" 2>/tmp/pycheck_extra.txt; then
      pass "$BASENAME compiles cleanly"
    else
      fail "$BASENAME has syntax errors: $(cat /tmp/pycheck_extra.txt)"
    fi
  fi
done

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════"
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
elif [ "$WARN" -ne 0 ]; then
  log "RESULT: ALL CHECKS PASSED (with warnings)"
  exit 0
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
