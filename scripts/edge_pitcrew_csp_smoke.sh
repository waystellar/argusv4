#!/usr/bin/env bash
# edge_pitcrew_csp_smoke.sh - Smoke test for Edge Pit Crew CSP compliance
#
# Validates:
#   CSP Header (pit_crew_dashboard.py):
#     1.  CSP header is set on dashboard response (handle_index)
#     2.  script-src uses nonce (not unsafe-inline)
#     3.  style-src allows unpkg.com for Leaflet CSS
#     4.  frame-src is 'none'
#     5.  object-src is 'none'
#     6.  Nonce placeholder exists in HTML template
#     7.  Nonce injected into CDN script tags
#     8.  Nonce injected into inline script tag
#   Inline Handlers (pit_crew_dashboard.py):
#     9.  No onclick= attributes in HTML templates
#    10.  No onchange= attributes in HTML templates
#    11.  No onerror= attributes in HTML templates
#    12.  No onsubmit= attributes in HTML templates
#    13.  Event delegation block exists (data-click handler)
#    14.  data-change-val delegation exists
#    15.  data-hide-error handler exists
#    16.  triggerGpxUpload helper exists
#   Banner Safety (pit_crew_dashboard.py):
#    17.  Banner update is first in updateDashboard (before try block)
#    18.  Remaining UI wrapped in try-catch
#    19.  Heartbeat loop is independent asyncio task
#   Syntax:
#    20.  Python syntax compiles
#
# Usage:
#   bash scripts/edge_pitcrew_csp_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[edge-csp]  $*"; }
pass() { echo "[edge-csp]    PASS: $*"; }
fail() { echo "[edge-csp]    FAIL: $*"; FAIL=1; }

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "EDGE-CLOUD-2: Edge Pit Crew CSP Compliance Smoke Test"
echo ""

if [ ! -f "$PIT_DASH" ]; then
  fail "pit_crew_dashboard.py not found"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# CSP HEADER
# ═══════════════════════════════════════════════════════════════════

# ── 1. CSP header set on dashboard response ────────────────────
log "Step 1: CSP header set on dashboard response"
if grep -q "Content-Security-Policy" "$PIT_DASH"; then
  pass "CSP header set in handle_index"
else
  fail "CSP header not found"
fi

# ── 2. script-src uses nonce (not unsafe-inline) ──────────────
log "Step 2: script-src uses nonce (not unsafe-inline)"
CSP_LINE=$(grep 'script-src' "$PIT_DASH" | grep -v '^\s*//' | head -1)
if echo "$CSP_LINE" | grep -q "nonce-"; then
  if echo "$CSP_LINE" | grep -q "'unsafe-inline'"; then
    fail "script-src has both nonce and unsafe-inline"
  else
    pass "script-src uses nonce without unsafe-inline"
  fi
else
  fail "script-src missing nonce"
fi

# ── 3. style-src allows unpkg.com for Leaflet CSS ────────────
log "Step 3: style-src allows unpkg.com"
if grep -q "style-src.*unpkg.com" "$PIT_DASH"; then
  pass "style-src includes unpkg.com"
else
  fail "style-src missing unpkg.com"
fi

# ── 4. frame-src is 'none' ────────────────────────────────────
log "Step 4: frame-src is 'none'"
if grep -q "frame-src 'none'" "$PIT_DASH"; then
  pass "frame-src is 'none'"
else
  fail "frame-src not set to 'none'"
fi

# ── 5. object-src is 'none' ───────────────────────────────────
log "Step 5: object-src is 'none'"
if grep -q "object-src 'none'" "$PIT_DASH"; then
  pass "object-src is 'none'"
else
  fail "object-src not set to 'none'"
fi

# ── 6. Nonce placeholder in HTML template ─────────────────────
log "Step 6: Nonce placeholder in HTML template"
NONCE_COUNT=$(grep -c '__CSP_NONCE__' "$PIT_DASH")
if [ "$NONCE_COUNT" -ge 3 ]; then
  pass "Nonce placeholder found $NONCE_COUNT times (CDN scripts + inline)"
else
  fail "Expected at least 3 nonce placeholders, found $NONCE_COUNT"
fi

# ── 7. Nonce on CDN script tags ───────────────────────────────
log "Step 7: Nonce on CDN script tags"
if grep -q 'nonce="__CSP_NONCE__" src="https://cdn.jsdelivr.net' "$PIT_DASH"; then
  pass "Chart.js script tag has nonce"
else
  fail "Chart.js script tag missing nonce"
fi
if grep -q 'nonce="__CSP_NONCE__" src="https://unpkg.com' "$PIT_DASH"; then
  pass "Leaflet script tag has nonce"
else
  fail "Leaflet script tag missing nonce"
fi

# ── 8. Nonce on inline script tag ─────────────────────────────
log "Step 8: Nonce on inline script tag"
if grep -q '<script nonce="__CSP_NONCE__">' "$PIT_DASH"; then
  pass "Inline script tag has nonce"
else
  fail "Inline script tag missing nonce"
fi

# ═══════════════════════════════════════════════════════════════════
# INLINE HANDLERS
# ═══════════════════════════════════════════════════════════════════

# ── 9-12. No inline handler attributes in HTML ────────────────
for attr in onclick onchange onerror onsubmit; do
  NUM=$(python3 -c "
import re
with open('$PIT_DASH') as f:
    content = f.read()
# Count actual HTML attributes (not JS comments or Python comments)
# Match: space + attr + = + quote, but NOT inside // comments
lines = content.split(chr(10))
count = 0
for line in lines:
    stripped = line.strip()
    # Skip JS comments and Python comments
    if stripped.startswith('//') or stripped.startswith('#'):
        continue
    if ' ${attr}=\"' in line:
        count += 1
print(count)
" 2>/dev/null || echo "-1")
  log "Step $((8 + $(echo "onclick onchange onerror onsubmit" | tr ' ' '\n' | grep -n "^${attr}$" | cut -d: -f1))): No ${attr}= in HTML"
  if [ "$NUM" -eq 0 ]; then
    pass "Zero ${attr}= attributes found"
  else
    fail "Found ${attr}= attributes: $NUM"
  fi
done

# ── 13. Event delegation block exists ─────────────────────────
log "Step 13: Event delegation for data-click exists"
if grep -q "data-click" "$PIT_DASH" && grep -q "document.addEventListener.*click" "$PIT_DASH"; then
  pass "data-click event delegation exists"
else
  fail "Missing data-click event delegation"
fi

# ── 14. data-change-val delegation exists ─────────────────────
log "Step 14: data-change-val delegation exists"
if grep -q "data-change-val" "$PIT_DASH"; then
  pass "data-change-val delegation exists"
else
  fail "Missing data-change-val delegation"
fi

# ── 15. data-hide-error handler exists ────────────────────────
log "Step 15: data-hide-error handler exists"
if grep -q "data-hide-error" "$PIT_DASH"; then
  pass "data-hide-error handler exists"
else
  fail "Missing data-hide-error handler"
fi

# ── 16. triggerGpxUpload helper exists ────────────────────────
log "Step 16: triggerGpxUpload helper exists"
if grep -q "function triggerGpxUpload" "$PIT_DASH"; then
  pass "triggerGpxUpload function exists"
else
  fail "Missing triggerGpxUpload function"
fi

# ═══════════════════════════════════════════════════════════════════
# BANNER SAFETY
# ═══════════════════════════════════════════════════════════════════

# ── 17. Banner update first in updateDashboard ────────────────
log "Step 17: Banner update is first in updateDashboard"
UPDATE_FUNC=$(sed -n '/function updateDashboard/,/^        function /p' "$PIT_DASH")
BANNER_LINE=$(echo "$UPDATE_FUNC" | grep -n 'offlineBanner' | head -1 | cut -d: -f1)
TRY_LINE=$(echo "$UPDATE_FUNC" | grep -n 'try {' | head -2 | tail -1 | cut -d: -f1)
if [ -n "$BANNER_LINE" ] && [ -n "$TRY_LINE" ] && [ "$BANNER_LINE" -lt "$TRY_LINE" ]; then
  pass "Banner update comes before main try block"
else
  fail "Banner update not first (banner=$BANNER_LINE, try=$TRY_LINE)"
fi

# ── 18. UI wrapped in try-catch ───────────────────────────────
log "Step 18: UI updates wrapped in try-catch"
if echo "$UPDATE_FUNC" | grep -q "catch.*uiErr"; then
  pass "UI try-catch block exists"
else
  fail "Missing UI try-catch block"
fi

# ── 19. Heartbeat is independent asyncio task ─────────────────
log "Step 19: Heartbeat loop is independent asyncio task"
if grep -q "create_task.*_cloud_status_loop" "$PIT_DASH"; then
  pass "Heartbeat runs as independent asyncio task"
else
  fail "Heartbeat not running as independent task"
fi

# ═══════════════════════════════════════════════════════════════════
# SYNTAX
# ═══════════════════════════════════════════════════════════════════

# ── 20. Python syntax compiles ────────────────────────────────
log "Step 20: Python syntax compiles"
if python3 -c "import ast; ast.parse(open('$PIT_DASH').read())" 2>/dev/null; then
  pass "Python syntax OK"
else
  fail "Python syntax error"
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
