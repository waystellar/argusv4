#!/usr/bin/env bash
# fan_watch_live_precheck.sh — Pre-check for Fan Watch Live issues
#
# Checks:
#   A) Finds active/newest event ID
#   B) Fetches CSP / CSP-Report-Only headers
#   C) Parses CSP directives for basemap domains
#   D) Basemap tile reachability check
#   E) Standings data includes registered vehicles
#
# Usage:
#   EVENT_ID=evt_abc bash scripts/fan_watch_live_precheck.sh [BASE_URL]
#   bash scripts/fan_watch_live_precheck.sh http://localhost
#
# Exit non-zero on any failure.
set -euo pipefail

BASE_URL="${1:-http://localhost}"
API_BASE="${BASE_URL}/api/v1"
FAIL=0

log()  { echo "[precheck] $*"; }
pass() { echo "[precheck]   PASS: $*"; }
fail() { echo "[precheck]   FAIL: $*"; FAIL=1; }
warn() { echo "[precheck]   WARN: $*"; }
info() { echo "[precheck]   INFO: $*"; }

# ── A) Find event ID ─────────────────────────────────────────────────
log "Phase A: Resolve event ID"

if [ -n "${EVENT_ID:-}" ]; then
  info "Using EVENT_ID from env: $EVENT_ID"
else
  # Try to list events from public API
  EVENTS_JSON=$(curl -sf "${API_BASE}/events" 2>/dev/null || echo "")
  if [ -n "$EVENTS_JSON" ] && [ "$EVENTS_JSON" != "[]" ]; then
    # Pick first in_progress event, or first event
    EVENT_ID=$(echo "$EVENTS_JSON" | python3 -c "
import sys, json
events = json.load(sys.stdin)
if not events:
    sys.exit(1)
live = [e for e in events if e.get('status') == 'in_progress']
pick = live[0] if live else events[0]
print(pick['event_id'])
" 2>/dev/null || echo "")
  fi

  if [ -z "${EVENT_ID:-}" ]; then
    warn "Could not resolve event ID from API (server may not be running)"
    warn "Set EVENT_ID env var to test standings. Continuing with CSP checks only."
  else
    info "Resolved event: $EVENT_ID"
  fi
fi

# ── B) Fetch CSP headers ─────────────────────────────────────────────
log "Phase B: Fetch CSP headers from ${BASE_URL}/"

HEADERS=$(curl -sI "${BASE_URL}/" 2>/dev/null || echo "")

CSP=$(echo "$HEADERS" | grep -i "^content-security-policy:" | head -1 || echo "")
CSP_RO=$(echo "$HEADERS" | grep -i "^content-security-policy-report-only:" | head -1 || echo "")

if [ -n "$CSP" ]; then
  info "CSP header found:"
  echo "    $CSP"
else
  warn "No Content-Security-Policy header found (server may not be running)"
fi

if [ -n "$CSP_RO" ]; then
  info "CSP-Report-Only header found:"
  echo "    $CSP_RO"
else
  info "No Content-Security-Policy-Report-Only header (normal)"
fi

# ── C) Parse CSP directives for basemap domains ──────────────────────
log "Phase C: Check CSP permits basemap tile domains"

BASEMAP_DOMAINS="basemaps.cartocdn.com tile.openstreetmap.org tile.opentopomap.org"

# Use CSP if present, otherwise check nginx.conf source
if [ -n "$CSP" ]; then
  CSP_TEXT="$CSP"
elif [ -f "web/nginx.conf" ]; then
  info "Server not reachable — checking nginx.conf source directly"
  CSP_TEXT=$(grep -i "content-security-policy" web/nginx.conf 2>/dev/null || echo "")
else
  CSP_TEXT=""
fi

if [ -n "$CSP_TEXT" ]; then
  for DOMAIN in $BASEMAP_DOMAINS; do
    # Check img-src
    if echo "$CSP_TEXT" | grep -q "img-src[^;]*${DOMAIN}"; then
      pass "img-src includes $DOMAIN"
    else
      fail "img-src MISSING $DOMAIN"
    fi

    # Check connect-src (MapLibre may fetch tiles via fetch/XHR)
    if echo "$CSP_TEXT" | grep -q "connect-src[^;]*${DOMAIN}"; then
      pass "connect-src includes $DOMAIN"
    else
      warn "connect-src missing $DOMAIN (may be needed if tiles fetched via XHR)"
    fi
  done
else
  warn "No CSP to parse — skipping directive checks"
fi

# ── D) Basemap reachability ──────────────────────────────────────────
log "Phase D: Basemap tile reachability"

# CARTO dark tile (z=0, x=0, y=0)
CARTO_URL="https://basemaps.cartocdn.com/dark_all/0/0/0.png"
CARTO_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$CARTO_URL" 2>/dev/null || echo "000")
if [ "$CARTO_CODE" = "200" ] || [ "$CARTO_CODE" = "304" ]; then
  pass "CARTO tile reachable (HTTP $CARTO_CODE)"
else
  fail "CARTO tile returned HTTP $CARTO_CODE"
fi

# CARTO with Origin header (CORS check)
CARTO_CORS_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Origin: ${BASE_URL}" \
  "$CARTO_URL" 2>/dev/null || echo "000")
if [ "$CARTO_CORS_CODE" = "200" ] || [ "$CARTO_CORS_CODE" = "304" ]; then
  pass "CARTO tile with Origin header OK (HTTP $CARTO_CORS_CODE)"
else
  warn "CARTO tile with Origin header returned HTTP $CARTO_CORS_CODE"
fi

# OpenStreetMap fallback tile
OSM_URL="https://tile.openstreetmap.org/0/0/0.png"
OSM_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "User-Agent: ArgusPrecheck/1.0" \
  "$OSM_URL" 2>/dev/null || echo "000")
if [ "$OSM_CODE" = "200" ] || [ "$OSM_CODE" = "304" ]; then
  pass "OpenStreetMap tile reachable (HTTP $OSM_CODE)"
else
  warn "OpenStreetMap tile returned HTTP $OSM_CODE (may be rate-limited)"
fi

# ── E) Standings includes registered vehicles ────────────────────────
log "Phase E: Standings data includes registered vehicles"

if [ -z "${EVENT_ID:-}" ]; then
  warn "No EVENT_ID — skipping standings check"
else
  # Count registered vehicles for event
  EVENT_JSON=$(curl -sf "${API_BASE}/events/${EVENT_ID}" 2>/dev/null || echo "")
  if [ -n "$EVENT_JSON" ]; then
    VEHICLE_COUNT=$(echo "$EVENT_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('vehicle_count', 0))
" 2>/dev/null || echo "0")
    info "Registered vehicles for event: $VEHICLE_COUNT"
  else
    VEHICLE_COUNT="0"
    warn "Could not fetch event details"
  fi

  # Count vehicles in leaderboard
  LEADERBOARD_JSON=$(curl -sf "${API_BASE}/events/${EVENT_ID}/leaderboard" 2>/dev/null || echo "")
  if [ -n "$LEADERBOARD_JSON" ]; then
    LB_COUNT=$(echo "$LEADERBOARD_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
entries = d.get('entries', [])
print(len(entries))
" 2>/dev/null || echo "0")
    info "Vehicles in leaderboard: $LB_COUNT"

    # Check for "Not Started" entries (vehicles with no timing data)
    NOT_STARTED=$(echo "$LEADERBOARD_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
entries = d.get('entries', [])
ns = [e for e in entries if e.get('last_checkpoint') == 0]
print(len(ns))
" 2>/dev/null || echo "0")
    info "Not Started entries: $NOT_STARTED"
  else
    LB_COUNT="0"
    warn "Could not fetch leaderboard"
  fi

  # Compare: if registered > 0 but leaderboard shows 0, that's a FAIL
  if [ "$VEHICLE_COUNT" -gt 0 ] && [ "$LB_COUNT" -eq 0 ]; then
    fail "Registered vehicles ($VEHICLE_COUNT) > 0 but leaderboard shows 0 entries"
  elif [ "$VEHICLE_COUNT" -gt 0 ] && [ "$LB_COUNT" -gt 0 ]; then
    if [ "$LB_COUNT" -ge "$VEHICLE_COUNT" ]; then
      pass "Leaderboard ($LB_COUNT) includes all registered vehicles ($VEHICLE_COUNT)"
    else
      warn "Leaderboard ($LB_COUNT) < registered vehicles ($VEHICLE_COUNT) — some may be hidden"
    fi
  elif [ "$VEHICLE_COUNT" -eq 0 ]; then
    info "No vehicles registered — standings check N/A"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL PRE-CHECKS PASSED"
  exit 0
else
  log "SOME PRE-CHECKS FAILED"
  exit 1
fi
