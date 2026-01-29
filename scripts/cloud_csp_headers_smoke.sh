#!/usr/bin/env bash
# cloud_csp_headers_smoke.sh - Guardrail: Cloud CSP & Security Headers
#
# Prints and validates CSP headers from the live Cloud nginx server.
# Checks multiple pages to ensure consistent CSP enforcement.
#
# Validates:
#   1. CSP header present on /, /team/dashboard, /events/<id>
#   2. script-src is NOT 'none' (would block all scripts)
#   3. frame-src includes YouTube domains (required for embeds)
#   4. worker-src allows blob: (required for service worker)
#   5. connect-src allows ws:/wss: (required for SSE/WebSocket)
#   6. No Content-Security-Policy-Report-Only (must be enforcing)
#   7. X-Frame-Options and X-Content-Type-Options present
#   8. Source-level nginx.conf validation
#
# Usage:
#   bash scripts/cloud_csp_headers_smoke.sh [http://host]
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX="$REPO_ROOT/web/nginx.conf"
BASE_URL="${1:-http://192.168.0.19}"
FAIL=0

log()  { echo "[cloud-csp]  $*"; }
pass() { echo "[cloud-csp]    PASS: $*"; }
fail() { echo "[cloud-csp]    FAIL: $*"; FAIL=1; }
skip() { echo "[cloud-csp]    SKIP: $*"; }
info() { echo "[cloud-csp]    INFO: $*"; }

log "CSP & Security Headers Guardrail - Cloud"
echo ""

# ── 1. Source-level: nginx.conf CSP validation ────────────────
log "Step 1: Source-level nginx.conf CSP validation"

if [ ! -f "$NGINX" ]; then
  fail "web/nginx.conf not found at $NGINX"
else
  # Extract main CSP line (longest one = SPA location / block)
  CSP_LINE=$(grep 'add_header Content-Security-Policy "' "$NGINX" | awk '{ print length, $0 }' | sort -rn | head -1 | cut -d' ' -f2-)

  if [ -z "$CSP_LINE" ]; then
    fail "No Content-Security-Policy add_header found in nginx.conf"
  else
    pass "CSP add_header found in nginx.conf"

    # Print the CSP for documentation
    info "CSP directive from nginx.conf:"
    echo "$CSP_LINE" | sed 's/; /;\n                      /g' | sed 's/^/         /' | head -20

    # Check script-src is not 'none' (must check within the directive, not across ';' boundaries)
    SCRIPT_SRC=$(echo "$CSP_LINE" | grep -oE "script-src[^;]*" | head -1)
    SCRIPT_SRC_ELEM=$(echo "$CSP_LINE" | grep -oE "script-src-elem[^;]*" || true)
    if echo "$SCRIPT_SRC" | grep -q "'none'"; then
      fail "script-src is 'none' — blocks all scripts!"
    elif [ -n "$SCRIPT_SRC_ELEM" ] && echo "$SCRIPT_SRC_ELEM" | grep -q "'none'"; then
      fail "script-src-elem is 'none' — blocks script elements!"
    else
      pass "script-src is not 'none' (found: $SCRIPT_SRC)"
    fi

    # Check frame-src includes YouTube
    if echo "$CSP_LINE" | grep -q "frame-src.*youtube.com"; then
      pass "frame-src includes youtube.com"
    else
      fail "frame-src missing youtube.com — YouTube embeds will be blocked"
    fi

    if echo "$CSP_LINE" | grep -q "frame-src.*youtube-nocookie.com"; then
      pass "frame-src includes youtube-nocookie.com"
    else
      fail "frame-src missing youtube-nocookie.com"
    fi

    # Check worker-src allows blob:
    if echo "$CSP_LINE" | grep -q "worker-src.*blob:"; then
      pass "worker-src allows blob:"
    else
      fail "worker-src missing blob: — service worker will fail"
    fi

    # Check connect-src allows ws: and wss:
    if echo "$CSP_LINE" | grep -q "connect-src.*ws:.*wss:\|connect-src.*wss:.*ws:"; then
      pass "connect-src allows ws: and wss:"
    else
      fail "connect-src missing ws:/wss: — SSE/WebSocket will fail"
    fi

    # Check no Report-Only
    if grep -q "Content-Security-Policy-Report-Only" "$NGINX"; then
      fail "CSP is Report-Only in nginx.conf — must be enforcing"
    else
      pass "CSP is enforcing (not Report-Only)"
    fi

    # Check default-src doesn't block frames when frame-src is missing
    if echo "$CSP_LINE" | grep -q "frame-src"; then
      pass "frame-src directive is explicit (not falling back to default-src)"
    else
      if echo "$CSP_LINE" | grep -q "default-src 'self'"; then
        fail "No frame-src and default-src is 'self' — frames limited to same origin only"
      else
        skip "frame-src not explicit but default-src may allow frames"
      fi
    fi
  fi
fi

# ── 2. Live header checks ────────────────────────────────────
log "Step 2: Live CSP headers from Cloud server ($BASE_URL)"

PAGES=(
  "/"
  "/team/dashboard"
  "/events/test-event"
)

for page in "${PAGES[@]}"; do
  url="$BASE_URL$page"
  HEADERS=$(curl -sI --connect-timeout 5 "$url" 2>/dev/null || echo "CURL_FAILED")

  if echo "$HEADERS" | grep -q "CURL_FAILED"; then
    skip "Server not reachable at $url"
    continue
  fi

  info "Headers for $page:"

  # Extract and print CSP
  LIVE_CSP=$(echo "$HEADERS" | grep -i "^content-security-policy:" | head -1 || true)
  if [ -n "$LIVE_CSP" ]; then
    pass "$page: CSP header present"
    echo "         ${LIVE_CSP:0:140}..."
  else
    fail "$page: No CSP header in response"
  fi

  # Check for Report-Only
  REPORT_ONLY=$(echo "$HEADERS" | grep -i "^content-security-policy-report-only:" || true)
  if [ -n "$REPORT_ONLY" ]; then
    fail "$page: CSP-Report-Only header found (should be enforcing)"
  fi

  # Check X-Frame-Options
  if echo "$HEADERS" | grep -qi "^x-frame-options:"; then
    pass "$page: X-Frame-Options present"
  else
    fail "$page: X-Frame-Options missing"
  fi

  # Check X-Content-Type-Options
  if echo "$HEADERS" | grep -qi "^x-content-type-options:"; then
    pass "$page: X-Content-Type-Options present"
  else
    fail "$page: X-Content-Type-Options missing"
  fi

  echo ""
done

# ── 3. Validate live CSP directives ──────────────────────────
log "Step 3: Validate live CSP directive content"

ROOT_HEADERS=$(curl -sI --connect-timeout 5 "$BASE_URL/" 2>/dev/null || echo "CURL_FAILED")
if echo "$ROOT_HEADERS" | grep -q "CURL_FAILED"; then
  skip "Server not reachable — skipping live directive validation"
else
  LIVE_CSP=$(echo "$ROOT_HEADERS" | grep -i "^content-security-policy:" | head -1 || true)

  if [ -n "$LIVE_CSP" ]; then
    # script-src not 'none' (check within directive boundaries)
    LIVE_SCRIPT_SRC=$(echo "$LIVE_CSP" | grep -oiE "script-src[^;]*" | head -1 || true)
    if echo "$LIVE_SCRIPT_SRC" | grep -qi "'none'"; then
      fail "Live CSP: script-src is 'none'"
    else
      pass "Live CSP: script-src is not 'none'"
    fi

    # frame-src includes YouTube
    if echo "$LIVE_CSP" | grep -qi "frame-src.*youtube"; then
      pass "Live CSP: frame-src includes YouTube"
    else
      fail "Live CSP: frame-src missing YouTube"
    fi

    # worker-src includes blob:
    if echo "$LIVE_CSP" | grep -qi "worker-src.*blob:"; then
      pass "Live CSP: worker-src includes blob:"
    else
      fail "Live CSP: worker-src missing blob:"
    fi

    # connect-src includes ws:
    if echo "$LIVE_CSP" | grep -qi "connect-src.*ws:"; then
      pass "Live CSP: connect-src includes ws:"
    else
      fail "Live CSP: connect-src missing ws:"
    fi
  fi
fi

# ── 4. Print CSP config location summary ─────────────────────
log "Step 4: CSP Configuration Locations"
echo ""
echo "  Cloud CSP is configured in nginx (NOT in Python backend):"
echo "    File: web/nginx.conf"
echo "    Location / (SPA):  Full CSP with YouTube, map tiles, WebSocket, workers"
echo "    Location /sw.js:   Stricter CSP (script-src 'self' only)"
echo "    Location /assets/: No CSP (static files, X-Content-Type-Options only)"
echo ""
echo "  Python backend (cloud/app/main.py): No CSP headers set"
echo "  CSP is entirely delegated to the nginx reverse proxy"
echo ""

# ── Summary ──────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
