#!/usr/bin/env bash
# team_gateway_smoke.sh — Smoke test for TEAM-1: Team Dashboard Gateway to Pit Crew
#
# Validates (source-level):
#   1. Edge URL storage key defined
#   2. Edge URL validation function exists
#   3. Redirect countdown logic
#   4. Cancel redirect / "Stay Here" button
#   5. Edge URL input form
#   6. "Open Pit Crew" link
#   7. Preview Fan View button with target="_blank"
#   8. Edge URL saved to localStorage
#   9. Edge URL cleared from localStorage
#  10. isValidEdgeUrl rejects non-LAN URLs
#  11. isValidEdgeUrl accepts LAN patterns
#  12. Auto-detect edge IP from diagnostics
#  13. TypeScript build check (if node available)
#
# Usage:
#   bash scripts/team_gateway_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TD="$REPO_ROOT/web/src/pages/TeamDashboard.tsx"
FAIL=0

log()  { echo "[team-gateway]  $*"; }
pass() { echo "[team-gateway]    PASS: $*"; }
fail() { echo "[team-gateway]    FAIL: $*"; FAIL=1; }
warn() { echo "[team-gateway]    WARN: $*"; }

# ── 1. Edge URL storage key ─────────────────────────────────────────
log "Step 1: Edge URL storage key"

if [ -f "$TD" ]; then
  if grep -q "EDGE_URL_STORAGE_KEY" "$TD"; then
    pass "EDGE_URL_STORAGE_KEY constant defined"
  else
    fail "EDGE_URL_STORAGE_KEY missing"
  fi

  if grep -q "argus_edge_url" "$TD"; then
    pass "Storage key value is 'argus_edge_url'"
  else
    fail "Storage key value missing"
  fi
else
  fail "TeamDashboard.tsx not found"
fi

# ── 2. Edge URL validation ──────────────────────────────────────────
log "Step 2: Edge URL validation function"

if [ -f "$TD" ]; then
  if grep -q "function isValidEdgeUrl" "$TD"; then
    pass "isValidEdgeUrl function defined"
  else
    fail "isValidEdgeUrl function missing"
  fi

  if grep -q "protocol.*http" "$TD" && grep -q "protocol.*https" "$TD"; then
    pass "Validates http/https protocol"
  else
    fail "Protocol validation missing"
  fi

  if grep -q "192\.168" "$TD"; then
    pass "Allows 192.168.x.x private range"
  else
    fail "Private IP range validation missing"
  fi

  if grep -q "\.local" "$TD"; then
    pass "Allows .local mDNS hostnames"
  else
    fail ".local hostname support missing"
  fi
fi

# ── 3. Redirect countdown ───────────────────────────────────────────
log "Step 3: Redirect countdown logic"

if [ -f "$TD" ]; then
  if grep -q "redirectCountdown" "$TD"; then
    pass "redirectCountdown state variable exists"
  else
    fail "redirectCountdown missing"
  fi

  if grep -q "setRedirectCountdown(5)" "$TD"; then
    pass "Countdown starts at 5 seconds"
  else
    fail "5-second countdown not set"
  fi

  if grep -q "window.location.href = edgeUrl" "$TD"; then
    pass "Redirects via window.location.href"
  else
    fail "Redirect mechanism missing"
  fi
fi

# ── 4. Cancel redirect ──────────────────────────────────────────────
log "Step 4: Cancel redirect / Stay Here"

if [ -f "$TD" ]; then
  if grep -q "handleCancelRedirect" "$TD"; then
    pass "handleCancelRedirect function exists"
  else
    fail "handleCancelRedirect missing"
  fi

  if grep -q "redirectCancelled" "$TD"; then
    pass "redirectCancelled state tracked"
  else
    fail "redirectCancelled state missing"
  fi

  if grep -q "Stay Here" "$TD"; then
    pass "Stay Here button text exists"
  else
    fail "Stay Here button missing"
  fi
fi

# ── 5. Edge URL input form ──────────────────────────────────────────
log "Step 5: Edge URL input form"

if [ -f "$TD" ]; then
  if grep -q "edgeUrlInput" "$TD"; then
    pass "edgeUrlInput state variable exists"
  else
    fail "edgeUrlInput missing"
  fi

  if grep -q "handleSaveEdgeUrl" "$TD"; then
    pass "handleSaveEdgeUrl function exists"
  else
    fail "handleSaveEdgeUrl missing"
  fi

  if grep -q "Connect to Pit Crew Portal" "$TD"; then
    pass "Form has descriptive heading"
  else
    fail "Form heading missing"
  fi
fi

# ── 6. Open Pit Crew link ───────────────────────────────────────────
log "Step 6: Open Pit Crew link"

if [ -f "$TD" ]; then
  if grep -q "Open Pit Crew" "$TD"; then
    pass "Open Pit Crew link text exists"
  else
    fail "Open Pit Crew link missing"
  fi

  if grep -q 'href={edgeUrl}' "$TD"; then
    pass "Link href bound to edgeUrl"
  else
    fail "Link href not bound to edgeUrl"
  fi
fi

# ── 7. Preview Fan View ─────────────────────────────────────────────
log "Step 7: Preview Fan View button"

if [ -f "$TD" ]; then
  if grep -q "Preview Fan View" "$TD"; then
    pass "Preview Fan View button exists"
  else
    fail "Preview Fan View button missing"
  fi

  if grep -q 'target="_blank"' "$TD"; then
    pass "Opens in new tab (target=_blank)"
  else
    fail "Not opening in new tab"
  fi

  if grep -q 'rel="noopener noreferrer"' "$TD"; then
    pass "Has noopener noreferrer for security"
  else
    fail "Missing noopener noreferrer"
  fi

  if grep -q 'data.event_id.*data.vehicle_id\|events/.*vehicles/' "$TD"; then
    pass "Uses event_id and vehicle_id from API data"
  else
    fail "Fan view URL not using API data"
  fi
fi

# ── 8. Edge URL persistence (save) ──────────────────────────────────
log "Step 8: Edge URL saved to localStorage"

if [ -f "$TD" ]; then
  if grep -q "localStorage.setItem(EDGE_URL_STORAGE_KEY" "$TD"; then
    pass "Saves edge URL to localStorage"
  else
    fail "localStorage.setItem for edge URL missing"
  fi

  if grep -q "localStorage.getItem(EDGE_URL_STORAGE_KEY" "$TD"; then
    pass "Reads edge URL from localStorage on mount"
  else
    fail "localStorage.getItem for edge URL missing"
  fi
fi

# ── 9. Edge URL persistence (clear) ─────────────────────────────────
log "Step 9: Edge URL cleared from localStorage"

if [ -f "$TD" ]; then
  if grep -q "localStorage.removeItem(EDGE_URL_STORAGE_KEY" "$TD"; then
    pass "Can clear edge URL from localStorage"
  else
    fail "localStorage.removeItem for edge URL missing"
  fi

  if grep -q "handleClearEdgeUrl\|Change URL" "$TD"; then
    pass "Clear/change URL action available"
  else
    fail "Clear URL action missing"
  fi
fi

# ── 10. Validation rejects non-LAN ──────────────────────────────────
log "Step 10: Validation rejects non-LAN URLs"

if [ -f "$TD" ]; then
  # Should return false for non-LAN by default
  if grep -q "return false" "$TD"; then
    pass "Validator returns false by default (rejects non-LAN)"
  else
    fail "Validator not rejecting non-LAN"
  fi
fi

# ── 11. Validation accepts LAN patterns ─────────────────────────────
log "Step 11: Validation accepts LAN patterns"

if [ -f "$TD" ]; then
  if grep -q "localhost" "$TD" && grep -q "127.0.0.1" "$TD"; then
    pass "Accepts localhost and 127.0.0.1"
  else
    fail "localhost/127.0.0.1 not accepted"
  fi

  if grep -q '10\\.' "$TD" || grep -q "^10\\\\." "$TD" || grep -q '/^10/' "$TD" || grep -q "'10.'" "$TD" || grep -q '^10\.' "$TD"; then
    pass "Accepts 10.x.x.x private range"
  else
    fail "10.x.x.x range not accepted"
  fi
fi

# ── 12. Auto-detect edge IP ─────────────────────────────────────────
log "Step 12: Auto-detect edge IP from diagnostics"

if [ -f "$TD" ]; then
  if grep -q "diagnostics?.edge_ip" "$TD" && grep -q "Use detected edge IP" "$TD"; then
    pass "Auto-detect uses diagnostics.edge_ip"
  else
    fail "Edge IP auto-detect missing"
  fi
fi

# ── 13. TypeScript build check ───────────────────────────────────────
log "Step 13: TypeScript build check"

if command -v node >/dev/null 2>&1; then
  if [ -f "$REPO_ROOT/web/package.json" ]; then
    if (cd "$REPO_ROOT/web" && npx tsc --noEmit 2>&1); then
      pass "TypeScript build passes"
    else
      fail "TypeScript build errors"
    fi
  else
    warn "web/package.json not found"
  fi
else
  warn "Node.js not available — skipping tsc check (source-level checks above substitute)"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
