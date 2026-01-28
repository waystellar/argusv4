#!/usr/bin/env bash
# admin_event_id_copy_smoke.sh — Smoke test for Admin Event ID copy feature
#
# Validates (source-level):
#   1. EventDetail.tsx has Event ID display with data-testid
#   2. EventDetail.tsx has copy button with data-testid="copy-event-id"
#   3. EventDetail.tsx uses copyToClipboard utility
#   4. EventDetail.tsx has "Copied" confirmation state
#   5. Copy button has aria-label for accessibility
#   6. Clipboard utility has HTTP fallback (execCommand)
#   7. Web build passes (tsc --noEmit)
#
# Usage:
#   bash scripts/admin_event_id_copy_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
EVENT_DETAIL="$WEB_DIR/src/pages/admin/EventDetail.tsx"
CLIPBOARD_UTIL="$WEB_DIR/src/utils/clipboard.ts"
FAIL=0

log()  { echo "[admin-event-id] $*"; }
pass() { echo "[admin-event-id]   PASS: $*"; }
fail() { echo "[admin-event-id]   FAIL: $*"; FAIL=1; }
warn() { echo "[admin-event-id]   WARN: $*"; }

# ── 1. Event ID display ───────────────────────────────────────────
log "Step 1: Event ID display"

if [ -f "$EVENT_DETAIL" ]; then
  if grep -q 'data-testid="event-id-display"' "$EVENT_DETAIL"; then
    pass "EventDetail has event-id-display test ID"
  else
    fail "EventDetail missing event-id-display test ID"
  fi

  if grep -q "Event ID" "$EVENT_DETAIL"; then
    pass "EventDetail has 'Event ID' label"
  else
    fail "EventDetail missing 'Event ID' label"
  fi

  if grep -q "event.event_id" "$EVENT_DETAIL"; then
    pass "EventDetail renders event.event_id"
  else
    fail "EventDetail missing event.event_id rendering"
  fi

  # Monospace display
  if grep -q "font-mono" "$EVENT_DETAIL"; then
    pass "Event ID uses monospace font"
  else
    fail "Event ID missing monospace font"
  fi
else
  fail "EventDetail.tsx not found"
fi

# ── 2. Copy button ────────────────────────────────────────────────
log "Step 2: Copy button"

if [ -f "$EVENT_DETAIL" ]; then
  if grep -q 'data-testid="copy-event-id"' "$EVENT_DETAIL"; then
    pass "Copy button has data-testid='copy-event-id'"
  else
    fail "Copy button missing data-testid='copy-event-id'"
  fi

  if grep -q 'aria-label="Copy event ID to clipboard"' "$EVENT_DETAIL"; then
    pass "Copy button has aria-label"
  else
    fail "Copy button missing aria-label"
  fi
fi

# ── 3. Clipboard integration ─────────────────────────────────────
log "Step 3: Clipboard integration"

if [ -f "$EVENT_DETAIL" ]; then
  if grep -q "copyToClipboard" "$EVENT_DETAIL"; then
    pass "EventDetail uses copyToClipboard utility"
  else
    fail "EventDetail missing copyToClipboard"
  fi

  if grep -q "copiedEventId" "$EVENT_DETAIL"; then
    pass "EventDetail has copiedEventId state"
  else
    fail "EventDetail missing copiedEventId state"
  fi

  if grep -q "Copied" "$EVENT_DETAIL"; then
    pass "EventDetail shows 'Copied' confirmation"
  else
    fail "EventDetail missing 'Copied' confirmation"
  fi
fi

# ── 4. HTTP fallback ─────────────────────────────────────────────
log "Step 4: Clipboard HTTP fallback"

if [ -f "$CLIPBOARD_UTIL" ]; then
  if grep -q "isSecureContext" "$CLIPBOARD_UTIL"; then
    pass "Clipboard utility checks isSecureContext"
  else
    fail "Clipboard utility missing isSecureContext check"
  fi

  if grep -q "execCommand.*copy" "$CLIPBOARD_UTIL"; then
    pass "Clipboard utility has execCommand fallback"
  else
    fail "Clipboard utility missing execCommand fallback"
  fi
else
  fail "clipboard.ts utility not found"
fi

# ── 5. Build check ────────────────────────────────────────────────
log "Step 5: Web build"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$WEB_DIR":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit" \
      > /tmp/admin_event_id_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed. Last 20 lines:"
    tail -20 /tmp/admin_event_id_build.log
  fi
else
  warn "Docker not available — skipping build check"
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
