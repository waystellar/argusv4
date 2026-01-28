#!/usr/bin/env bash
# fan_watch_feeds_smoke.sh — Smoke test for Fan Watch video feeds feature
#
# Validates (source-level):
#   1. WatchTab fetches from /production/events/{eventId}/stream-states
#   2. WatchTab does NOT hardcode youtube_url: null for all vehicles
#   3. WatchTab has StreamState interface with is_live and youtube_url
#   4. WatchTab has empty state with helpful message
#   5. WatchTab polls for updates (setInterval)
#   6. Backend stream-states endpoint exists and returns required schema
#   7. FeedCard shows Live/Offline badges based on is_live
#   8. Web build passes (tsc --noEmit)
#
# Usage:
#   bash scripts/fan_watch_feeds_smoke.sh [EVENT_ID]
#
# EVENT_ID is optional and used for live API checks (skipped if not provided).
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
WATCH_TAB="$WEB_DIR/src/components/RaceCenter/WatchTab.tsx"
TYPES_FILE="$WEB_DIR/src/components/RaceCenter/types.ts"
PRODUCTION_PY="$REPO_ROOT/cloud/app/routes/production.py"
EVENT_ID="${1:-}"
FAIL=0

log()  { echo "[watch-feeds] $*"; }
pass() { echo "[watch-feeds]   PASS: $*"; }
fail() { echo "[watch-feeds]   FAIL: $*"; FAIL=1; }
warn() { echo "[watch-feeds]   WARN: $*"; }

# ── 1. WatchTab fetches stream states from API ─────────────────
log "Step 1: WatchTab API integration"

if [ -f "$WATCH_TAB" ]; then
  if grep -q 'stream-states' "$WATCH_TAB"; then
    pass "WatchTab fetches from stream-states endpoint"
  else
    fail "WatchTab missing stream-states fetch"
  fi

  if grep -q 'production/events' "$WATCH_TAB"; then
    pass "WatchTab uses production API path"
  else
    fail "WatchTab missing production API path"
  fi

  if grep -q 'fetchStreamStates' "$WATCH_TAB"; then
    pass "WatchTab has fetchStreamStates function"
  else
    fail "WatchTab missing fetchStreamStates"
  fi
else
  fail "WatchTab.tsx not found"
fi

# ── 2. No hardcoded null feeds ──────────────────────────────────
log "Step 2: No hardcoded null feeds"

if [ -f "$WATCH_TAB" ]; then
  # Should NOT have "Would come from API" placeholder comments
  if grep -q 'Would come from API' "$WATCH_TAB"; then
    fail "WatchTab still has 'Would come from API' placeholder"
  else
    pass "No placeholder comments for feed data"
  fi
fi

# ── 3. StreamState interface ────────────────────────────────────
log "Step 3: StreamState type definitions"

if [ -f "$WATCH_TAB" ]; then
  if grep -q 'interface StreamState' "$WATCH_TAB"; then
    pass "WatchTab has StreamState interface"
  else
    fail "WatchTab missing StreamState interface"
  fi

  if grep -q 'is_live.*boolean' "$WATCH_TAB"; then
    pass "StreamState has is_live: boolean"
  else
    fail "StreamState missing is_live"
  fi

  if grep -q 'youtube_url.*string.*null' "$WATCH_TAB"; then
    pass "StreamState has youtube_url field"
  else
    fail "StreamState missing youtube_url"
  fi

  if grep -q 'StreamStatesResponse' "$WATCH_TAB"; then
    pass "WatchTab has StreamStatesResponse type"
  else
    fail "WatchTab missing StreamStatesResponse"
  fi

  if grep -q 'live_count' "$WATCH_TAB"; then
    pass "StreamStatesResponse has live_count"
  else
    fail "StreamStatesResponse missing live_count"
  fi
fi

# ── 4. Empty state message ──────────────────────────────────────
log "Step 4: Empty state UX"

if [ -f "$WATCH_TAB" ]; then
  if grep -q 'No video feeds yet' "$WATCH_TAB"; then
    pass "WatchTab has 'No video feeds yet' empty state"
  else
    fail "WatchTab missing empty state title"
  fi

  if grep -q 'teams start streaming' "$WATCH_TAB"; then
    pass "Empty state explains when feeds appear"
  else
    fail "Empty state missing explanation"
  fi

  if grep -q 'hasFetched' "$WATCH_TAB"; then
    pass "WatchTab tracks fetch state before showing empty state"
  else
    fail "WatchTab missing hasFetched guard"
  fi
fi

# ── 5. Polling for updates ──────────────────────────────────────
log "Step 5: Polling"

if [ -f "$WATCH_TAB" ]; then
  if grep -q 'setInterval' "$WATCH_TAB"; then
    pass "WatchTab polls for stream state updates"
  else
    fail "WatchTab missing polling"
  fi

  if grep -q 'clearInterval' "$WATCH_TAB"; then
    pass "WatchTab cleans up interval on unmount"
  else
    fail "WatchTab missing interval cleanup"
  fi
fi

# ── 6. Backend endpoint exists ──────────────────────────────────
log "Step 6: Backend stream-states endpoint"

if [ -f "$PRODUCTION_PY" ]; then
  if grep -q 'stream-states' "$PRODUCTION_PY"; then
    pass "production.py has stream-states route"
  else
    fail "production.py missing stream-states route"
  fi

  if grep -q 'RacerStreamStateList' "$PRODUCTION_PY"; then
    pass "production.py has RacerStreamStateList model"
  else
    fail "production.py missing RacerStreamStateList"
  fi

  if grep -q 'class RacerStreamState' "$PRODUCTION_PY"; then
    pass "production.py has RacerStreamState model"
  else
    fail "production.py missing RacerStreamState model"
  fi

  # Check required response fields
  if grep -q 'is_live.*bool' "$PRODUCTION_PY"; then
    pass "RacerStreamState has is_live: bool"
  else
    fail "RacerStreamState missing is_live"
  fi

  if grep -q 'youtube_url.*Optional' "$PRODUCTION_PY"; then
    pass "RacerStreamState has youtube_url"
  else
    fail "RacerStreamState missing youtube_url"
  fi

  if grep -q 'live_count.*int' "$PRODUCTION_PY"; then
    pass "RacerStreamStateList has live_count"
  else
    fail "RacerStreamStateList missing live_count"
  fi
fi

# ── 7. Feed card badges ────────────────────────────────────────
log "Step 7: Feed card Live/Offline badges"

if [ -f "$WATCH_TAB" ]; then
  if grep -q 'feed.is_live' "$WATCH_TAB"; then
    pass "FeedCard checks feed.is_live"
  else
    fail "FeedCard missing is_live check"
  fi

  if grep -q 'LIVE' "$WATCH_TAB"; then
    pass "FeedCard shows LIVE badge"
  else
    fail "FeedCard missing LIVE badge"
  fi

  if grep -q 'OFFLINE' "$WATCH_TAB"; then
    pass "FeedCard shows OFFLINE badge"
  else
    fail "FeedCard missing OFFLINE badge"
  fi

  if grep -q 'feed-card' "$WATCH_TAB"; then
    pass "FeedCard has data-testid"
  else
    fail "FeedCard missing data-testid"
  fi
fi

# ── 8. CameraFeed type has required fields ──────────────────────
log "Step 8: CameraFeed type"

if [ -f "$TYPES_FILE" ]; then
  if grep -q 'youtube_url.*string.*null' "$TYPES_FILE"; then
    pass "CameraFeed type has youtube_url"
  else
    fail "CameraFeed type missing youtube_url"
  fi

  if grep -q 'is_live.*boolean' "$TYPES_FILE"; then
    pass "CameraFeed type has is_live"
  else
    fail "CameraFeed type missing is_live"
  fi
fi

# ── 9. Live API check (optional) ───────────────────────────────
if [ -n "$EVENT_ID" ]; then
  log "Step 9: Live API check (event: $EVENT_ID)"

  API_URL="${API_BASE:-http://localhost:8000}/api/v1/production/events/${EVENT_ID}/stream-states"
  RESP=$(curl -sf "$API_URL" 2>/dev/null || echo "")

  if [ -n "$RESP" ]; then
    # Check response has expected fields
    if echo "$RESP" | grep -q '"event_id"'; then
      pass "API response has event_id"
    else
      fail "API response missing event_id"
    fi

    if echo "$RESP" | grep -q '"vehicles"'; then
      pass "API response has vehicles array"
    else
      fail "API response missing vehicles"
    fi

    if echo "$RESP" | grep -q '"live_count"'; then
      pass "API response has live_count"
    else
      fail "API response missing live_count"
    fi
  else
    warn "Could not reach API at $API_URL (server may not be running)"
  fi
else
  log "Step 9: Live API check (skipped — no EVENT_ID provided)"
fi

# ── 10. Build check ─────────────────────────────────────────────
log "Step 10: Web build"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$WEB_DIR":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit" \
      > /tmp/fan_watch_feeds_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed. Last 20 lines:"
    tail -20 /tmp/fan_watch_feeds_build.log
  fi
else
  warn "Docker not available — skipping build check"
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
