#!/usr/bin/env bash
# fan_watch_live_smoke.sh — Smoke test for Fan "Watch Live" page
#
# Validates:
#   1. Build check (tsc + vite build via Docker)
#   2. CSP permits all basemap tile domains (source-level)
#   3. Map.tsx tile URLs match CSP allowlist
#   4. StandingsTab renders "Not Started" entries
#   5. OverviewTab shows leaderboard entries (not just empty state)
#   6. Leaderboard API includes registered vehicles (live server)
#   7. Basemap tile servers reachable
#
# Usage:
#   bash scripts/fan_watch_live_smoke.sh [BASE_URL]
#   EVENT_ID=evt_abc bash scripts/fan_watch_live_smoke.sh http://192.168.0.19
#
# Exit non-zero on any failure.
set -euo pipefail

BASE_URL="${1:-http://localhost}"
API_BASE="${BASE_URL}/api/v1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
FAIL=0

log()  { echo "[watch-live] $*"; }
pass() { echo "[watch-live]   PASS: $*"; }
fail() { echo "[watch-live]   FAIL: $*"; FAIL=1; }
warn() { echo "[watch-live]   WARN: $*"; }
info() { echo "[watch-live]   INFO: $*"; }

# ── 1. Build check ────────────────────────────────────────────────
log "Step 1: Build check (Docker)"
if docker run --rm -v "$WEB_DIR":/app -w /app node:20-alpine \
    sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit && ./node_modules/.bin/vite build" \
    > /tmp/fan_watch_live_build.log 2>&1; then
  pass "tsc --noEmit + vite build"
else
  fail "Build failed. Last 20 lines:"
  tail -20 /tmp/fan_watch_live_build.log
fi

# ── 2. CSP permits basemap tile domains (source-level) ────────────
log "Step 2: CSP source-level checks"

NGINX_CONF="$WEB_DIR/nginx.conf"
if [ -f "$NGINX_CONF" ]; then
  CSP_LINE=$(grep -i "content-security-policy" "$NGINX_CONF" 2>/dev/null || echo "")

  BASEMAP_DOMAINS="basemaps.cartocdn.com tile.openstreetmap.org tile.opentopomap.org"
  for DOMAIN in $BASEMAP_DOMAINS; do
    if echo "$CSP_LINE" | grep -q "img-src[^;]*${DOMAIN}"; then
      pass "CSP img-src includes $DOMAIN"
    else
      fail "CSP img-src MISSING $DOMAIN"
    fi

    if echo "$CSP_LINE" | grep -q "connect-src[^;]*${DOMAIN}"; then
      pass "CSP connect-src includes $DOMAIN"
    else
      fail "CSP connect-src MISSING $DOMAIN"
    fi
  done
else
  fail "nginx.conf not found at $NGINX_CONF"
fi

# ── 3. Basemap config tile URLs match CSP ─────────────────────────
log "Step 3: Basemap tile source alignment"

MAP_FILE="$WEB_DIR/src/components/Map/Map.tsx"
BASEMAP_TS="$WEB_DIR/src/config/basemap.ts"

# MAP-STYLE-2: Tile URLs are in centralized config
if [ -f "$BASEMAP_TS" ]; then
  TOPO_IN_CONFIG=$(grep -o "tile\.opentopomap\.org" "$BASEMAP_TS" 2>/dev/null | head -1)

  if [ -n "$TOPO_IN_CONFIG" ]; then
    pass "Basemap config uses OpenTopoMap tiles"
  else
    fail "Basemap config does not reference tile.opentopomap.org"
  fi

  # Verify tile domains in basemap config exist in CSP
  if [ -n "$CSP_LINE" ]; then
    MAP_DOMAINS=$(grep '{z}/{x}/{y}' "$BASEMAP_TS" 2>/dev/null | grep -oE 'https://[a-z.*]+\.(opentopomap\.org)' | sed 's|https://||' | sort -u)
    for D in $MAP_DOMAINS; do
      PLAIN_D=$(echo "$D" | sed 's/\*\.//')
      WILDCARD_D=$(echo "$PLAIN_D" | sed 's/^[a-z]*\./\*\./')
      if echo "$CSP_LINE" | grep -q "$PLAIN_D"; then
        pass "Basemap domain $D found in CSP"
      elif echo "$CSP_LINE" | grep -q "$WILDCARD_D"; then
        pass "Basemap domain $D covered by CSP wildcard $WILDCARD_D"
      else
        fail "Basemap domain $D NOT in CSP"
      fi
    done
  fi
else
  fail "config/basemap.ts not found"
fi

if [ -f "$MAP_FILE" ]; then
  # MAP-STYLE-1: No CARTO tiles
  if grep -q "dark_all\|light_all\|basemaps.cartocdn.com" "$MAP_FILE"; then
    fail "Map.tsx still has CARTO tile references (should be topo-only)"
  else
    pass "No CARTO tile references (topo-only)"
  fi
fi

# ── 4. StandingsTab handles "Not Started" entries ─────────────────
log "Step 4: StandingsTab component checks"

STANDINGS_FILE="$WEB_DIR/src/components/RaceCenter/StandingsTab.tsx"
if [ -f "$STANDINGS_FILE" ]; then
  # Must reference "Not Started" or last_checkpoint === 0 for unstarted vehicles
  if grep -q "Not Started\|notStarted\|last_checkpoint" "$STANDINGS_FILE" 2>/dev/null; then
    pass "StandingsTab handles unstarted vehicles"
  else
    fail "StandingsTab missing Not Started handling"
  fi

  # Must render leaderboard entries
  if grep -q "leaderboard\|entries" "$STANDINGS_FILE" 2>/dev/null; then
    pass "StandingsTab renders leaderboard entries"
  else
    fail "StandingsTab missing leaderboard rendering"
  fi
else
  fail "StandingsTab.tsx not found"
fi

# ── 5. OverviewTab leaderboard rendering ───────────────────────────
log "Step 5: OverviewTab component checks"

OVERVIEW_FILE="$WEB_DIR/src/components/RaceCenter/OverviewTab.tsx"
if [ -f "$OVERVIEW_FILE" ]; then
  # Must slice leaderboard for top entries
  if grep -q "leaderboard\|top10\|slice" "$OVERVIEW_FILE" 2>/dev/null; then
    pass "OverviewTab renders leaderboard entries"
  else
    fail "OverviewTab missing leaderboard rendering"
  fi

  # Should have empty state message
  if grep -q "Waiting for race data\|No.*data\|Empty" "$OVERVIEW_FILE" 2>/dev/null; then
    pass "OverviewTab has empty state message"
  else
    warn "OverviewTab missing empty state"
  fi
else
  fail "OverviewTab.tsx not found"
fi

# ── 6. Leaderboard API includes registered vehicles (live) ────────
log "Step 6: Leaderboard API check (live server)"

# Resolve event ID
if [ -z "${EVENT_ID:-}" ]; then
  EVENTS_JSON=$(curl -sf "${API_BASE}/events" 2>/dev/null || echo "")
  if [ -n "$EVENTS_JSON" ] && [ "$EVENTS_JSON" != "[]" ]; then
    EVENT_ID=$(echo "$EVENTS_JSON" | python3 -c "
import sys, json
events = json.load(sys.stdin)
if not events: sys.exit(1)
live = [e for e in events if e.get('status') == 'in_progress']
pick = live[0] if live else events[0]
print(pick['event_id'])
" 2>/dev/null || echo "")
  fi
fi

if [ -z "${EVENT_ID:-}" ]; then
  warn "No EVENT_ID and server not reachable — skipping API checks"
else
  info "Event: $EVENT_ID"

  # Fetch vehicle count
  EVENT_JSON=$(curl -sf "${API_BASE}/events/${EVENT_ID}" 2>/dev/null || echo "")
  VEHICLE_COUNT=0
  if [ -n "$EVENT_JSON" ]; then
    VEHICLE_COUNT=$(echo "$EVENT_JSON" | python3 -c "
import sys, json
print(json.load(sys.stdin).get('vehicle_count', 0))
" 2>/dev/null || echo "0")
    info "Registered vehicles: $VEHICLE_COUNT"
  fi

  # Fetch leaderboard
  LB_JSON=$(curl -sf "${API_BASE}/events/${EVENT_ID}/leaderboard" 2>/dev/null || echo "")
  LB_COUNT=0
  NOT_STARTED=0
  if [ -n "$LB_JSON" ]; then
    LB_COUNT=$(echo "$LB_JSON" | python3 -c "
import sys, json
print(len(json.load(sys.stdin).get('entries', [])))
" 2>/dev/null || echo "0")

    NOT_STARTED=$(echo "$LB_JSON" | python3 -c "
import sys, json
entries = json.load(sys.stdin).get('entries', [])
print(len([e for e in entries if e.get('last_checkpoint') == 0]))
" 2>/dev/null || echo "0")

    info "Leaderboard entries: $LB_COUNT (Not Started: $NOT_STARTED)"
  else
    warn "Could not fetch leaderboard"
  fi

  # Validate: registered > 0 but leaderboard = 0 is a failure
  if [ "$VEHICLE_COUNT" -gt 0 ] && [ "$LB_COUNT" -eq 0 ]; then
    fail "Registered vehicles ($VEHICLE_COUNT) but leaderboard empty"
  elif [ "$VEHICLE_COUNT" -gt 0 ] && [ "$LB_COUNT" -ge "$VEHICLE_COUNT" ]; then
    pass "Leaderboard ($LB_COUNT) includes all registered vehicles ($VEHICLE_COUNT)"
  elif [ "$VEHICLE_COUNT" -gt 0 ]; then
    warn "Leaderboard ($LB_COUNT) < registered ($VEHICLE_COUNT) — some may be hidden"
  else
    info "No vehicles registered — API check N/A"
  fi
fi

# ── 7. Basemap reachability ────────────────────────────────────────
log "Step 7: Basemap tile reachability"

TOPO_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "User-Agent: ArgusSmoke/1.0" \
  "https://a.tile.opentopomap.org/0/0/0.png" 2>/dev/null || echo "000")
if [ "$TOPO_CODE" = "200" ] || [ "$TOPO_CODE" = "304" ]; then
  pass "OpenTopoMap tile reachable (HTTP $TOPO_CODE)"
else
  warn "OpenTopoMap tile returned HTTP $TOPO_CODE (may be rate-limited)"
fi

TOPO_B_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "User-Agent: ArgusSmoke/1.0" \
  "https://b.tile.opentopomap.org/0/0/0.png" 2>/dev/null || echo "000")
if [ "$TOPO_B_CODE" = "200" ] || [ "$TOPO_B_CODE" = "304" ]; then
  pass "OpenTopoMap subdomain b reachable (HTTP $TOPO_B_CODE)"
else
  warn "OpenTopoMap subdomain b returned HTTP $TOPO_B_CODE"
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
