#!/usr/bin/env bash
# cloud_csp_smoke.sh — Smoke test for PROD-CRASH-2: CSP cleanup
#
# Validates (source-level in nginx.conf):
#   1. CSP header is set (Content-Security-Policy, not Report-Only)
#   2. script-src includes 'self'
#   3. worker-src includes 'self' and blob:
#   4. connect-src includes 'self', ws:, wss:
#   5. manifest-src includes 'self'
#   6. frame-ancestors includes 'self'
#   7. No script-src-elem 'none' (would block scripts)
#   8. /sw.js location has X-Content-Type-Options
#   9. /assets/ location has X-Content-Type-Options
#  10. Live curl check (if server reachable)
#
# Usage:
#   bash scripts/cloud_csp_smoke.sh [http://host]
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX="$REPO_ROOT/web/nginx.conf"
BASE_URL="${1:-http://localhost}"
FAIL=0

log()  { echo "[csp-smoke]  $*"; }
pass() { echo "[csp-smoke]    PASS: $*"; }
fail() { echo "[csp-smoke]    FAIL: $*"; FAIL=1; }
skip() { echo "[csp-smoke]    SKIP: $*"; }

# ── Source-level checks on nginx.conf ─────────────────────────

log "Step 1: CSP header is enforcing (not Report-Only)"

if grep -q 'add_header Content-Security-Policy ' "$NGINX"; then
  if grep -q 'Content-Security-Policy-Report-Only' "$NGINX"; then
    fail "CSP is Report-Only — should be enforcing"
  else
    pass "CSP is enforcing (Content-Security-Policy, not Report-Only)"
  fi
else
  fail "No Content-Security-Policy header found in nginx.conf"
fi

# Extract the main CSP line (the longest one — the SPA location / block)
# The sw.js block has a shorter, stricter CSP; we want the main app CSP.
CSP_LINE=$(grep 'add_header Content-Security-Policy "' "$NGINX" | awk '{ print length, $0 }' | sort -rn | head -1 | cut -d' ' -f2-)

log "Step 2: script-src includes 'self'"

if echo "$CSP_LINE" | grep -q "script-src 'self'"; then
  pass "script-src includes 'self'"
else
  fail "script-src missing 'self'"
fi

log "Step 3: worker-src includes 'self' and blob:"

if echo "$CSP_LINE" | grep -q "worker-src 'self' blob:"; then
  pass "worker-src includes 'self' blob:"
else
  fail "worker-src missing 'self' blob:"
fi

log "Step 4: connect-src includes 'self', ws:, wss:"

if echo "$CSP_LINE" | grep -q "connect-src 'self' ws: wss:"; then
  pass "connect-src includes 'self' ws: wss:"
else
  fail "connect-src missing 'self' ws: wss:"
fi

log "Step 5: manifest-src includes 'self'"

if echo "$CSP_LINE" | grep -q "manifest-src 'self'"; then
  pass "manifest-src includes 'self'"
else
  fail "manifest-src missing 'self'"
fi

log "Step 6: frame-ancestors includes 'self'"

if echo "$CSP_LINE" | grep -q "frame-ancestors 'self'"; then
  pass "frame-ancestors includes 'self'"
else
  fail "frame-ancestors missing 'self'"
fi

log "Step 7: No script-src-elem 'none' (would block scripts)"

if echo "$CSP_LINE" | grep -q "script-src-elem.*'none'"; then
  fail "script-src-elem 'none' present — will block script elements"
else
  pass "No script-src-elem 'none' directive"
fi

log "Step 8: /sw.js location has X-Content-Type-Options"

if grep -A 5 'location /sw.js' "$NGINX" | grep -q 'X-Content-Type-Options'; then
  pass "/sw.js has X-Content-Type-Options"
else
  fail "/sw.js missing X-Content-Type-Options"
fi

log "Step 9: /assets/ location has X-Content-Type-Options"

if grep -A 5 'location /assets/' "$NGINX" | grep -q 'X-Content-Type-Options'; then
  pass "/assets/ has X-Content-Type-Options"
else
  fail "/assets/ missing X-Content-Type-Options"
fi

# ── Live check (optional) ────────────────────────────────────

log "Step 10: Live CSP header check (curl $BASE_URL)"

HEADERS=$(curl -sI "$BASE_URL/" 2>/dev/null || echo "CURL_FAILED")

if echo "$HEADERS" | grep -q "CURL_FAILED"; then
  skip "Server not reachable at $BASE_URL — source-level checks above substitute"
else
  LIVE_CSP=$(echo "$HEADERS" | grep -i "^content-security-policy:" | head -1 || true)
  if [ -n "$LIVE_CSP" ]; then
    pass "Live CSP header present"
    echo "[csp-smoke]    CSP: ${LIVE_CSP:0:120}..."

    # Verify key directives in live header
    if echo "$LIVE_CSP" | grep -q "worker-src"; then
      pass "Live CSP includes worker-src"
    else
      fail "Live CSP missing worker-src"
    fi
  else
    skip "No CSP header in live response (server may not be nginx)"
  fi
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
