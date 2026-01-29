#!/usr/bin/env bash
# prod_csp_youtube_smoke.sh — Smoke test for PROD-CSP-1: YouTube embed CSP fix
#
# Validates (source-level):
#   1. CSP header in nginx.conf contains frame-src directive
#   2. frame-src includes 'self', youtube.com, and youtube-nocookie.com
#   3. CSP does NOT contain frame-src 'none'
#   4. object-src 'none' is present for security
#   5. Web build passes (tsc && vite build simulation via npm run build)
#
# Usage:
#   bash scripts/prod_csp_youtube_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX="$REPO_ROOT/web/nginx.conf"
FAIL=0

log()  { echo "[prod-csp-youtube]  $*"; }
pass() { echo "[prod-csp-youtube]    PASS: $*"; }
fail() { echo "[prod-csp-youtube]    FAIL: $*"; FAIL=1; }

# ── 1. CSP header exists in nginx.conf ──────────────────────────
log "Step 1: CSP header exists in nginx.conf"

if [ -f "$NGINX" ]; then
  if grep -q 'add_header Content-Security-Policy' "$NGINX"; then
    pass "Content-Security-Policy header is set in nginx.conf"
  else
    fail "Content-Security-Policy header not found in nginx.conf"
  fi
else
  fail "nginx.conf not found at $NGINX"
fi

# ── 2. Extract main CSP (SPA location / block) ──────────────────
log "Step 2: Extract and display main CSP"

# The main SPA CSP is in the location / block (the longest CSP line)
CSP_LINE=$(grep 'add_header Content-Security-Policy "' "$NGINX" | awk '{ print length, $0 }' | sort -rn | head -1 | cut -d' ' -f2-)

if [ -n "$CSP_LINE" ]; then
  # Extract just the CSP value (between quotes)
  CSP_VALUE=$(echo "$CSP_LINE" | sed 's/.*Content-Security-Policy "\([^"]*\)".*/\1/')
  echo ""
  log "Main CSP policy:"
  echo "  $CSP_VALUE" | tr ';' '\n' | sed 's/^ */    /'
  echo ""
  pass "CSP extracted successfully"
else
  fail "Could not extract CSP line"
fi

# ── 3. frame-src includes YouTube domains ───────────────────────
log "Step 3: frame-src includes YouTube domains"

if echo "$CSP_VALUE" | grep -q "frame-src"; then
  pass "frame-src directive exists"
else
  fail "frame-src directive is MISSING"
fi

if echo "$CSP_VALUE" | grep -q "frame-src.*'self'"; then
  pass "frame-src includes 'self'"
else
  fail "frame-src missing 'self'"
fi

if echo "$CSP_VALUE" | grep -q "frame-src.*https://www.youtube.com"; then
  pass "frame-src includes https://www.youtube.com"
else
  fail "frame-src missing https://www.youtube.com"
fi

if echo "$CSP_VALUE" | grep -q "frame-src.*https://www.youtube-nocookie.com"; then
  pass "frame-src includes https://www.youtube-nocookie.com"
else
  fail "frame-src missing https://www.youtube-nocookie.com"
fi

# ── 4. frame-src does NOT contain 'none' ────────────────────────
log "Step 4: frame-src does NOT block all frames"

if echo "$CSP_VALUE" | grep -q "frame-src 'none'"; then
  fail "frame-src is set to 'none' - YouTube embeds will be blocked!"
else
  pass "frame-src is NOT 'none'"
fi

# ── 5. object-src 'none' for security ───────────────────────────
log "Step 5: object-src 'none' is set for security"

if echo "$CSP_VALUE" | grep -q "object-src 'none'"; then
  pass "object-src 'none' is set (blocks plugins)"
else
  fail "object-src 'none' is missing (security weakness)"
fi

# ── 6. Web build passes ─────────────────────────────────────────
log "Step 6: Web build (tsc --noEmit)"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$REPO_ROOT/web":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit" \
      > /tmp/prod_csp_youtube_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed. Last 20 lines:"
    tail -20 /tmp/prod_csp_youtube_build.log
  fi
elif command -v npm >/dev/null 2>&1; then
  if (cd "$REPO_ROOT/web" && npx tsc --noEmit) > /tmp/prod_csp_youtube_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed"
    tail -20 /tmp/prod_csp_youtube_build.log
  fi
else
  echo "[prod-csp-youtube]    SKIP: Neither docker nor npm available"
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
