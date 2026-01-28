#!/usr/bin/env bash
# setup_ui_smoke.sh — Smoke test for /setup/ UI modernization
#
# Validates:
#   1. Cloud Python syntax check (setup.py compiles)
#   2. DS token presence in setup.py inline CSS
#   3. No legacy gradient/color values remain
#   4. Live /setup/ returns HTML with DS tokens (if server running)
#   5. Web frontend build still passes (Docker)
#
# Usage:
#   bash scripts/setup_ui_smoke.sh [BASE_URL]
#
# Exit non-zero on any failure.
set -euo pipefail

BASE_URL="${1:-http://localhost}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_PY="$REPO_ROOT/cloud/app/routes/setup.py"
WEB_DIR="$REPO_ROOT/web"
FAIL=0

log()  { echo "[setup-smoke] $*"; }
pass() { echo "[setup-smoke]   PASS: $*"; }
fail() { echo "[setup-smoke]   FAIL: $*"; FAIL=1; }
warn() { echo "[setup-smoke]   WARN: $*"; }
info() { echo "[setup-smoke]   INFO: $*"; }

# ── 1. Python syntax check ────────────────────────────────────────
log "Step 1: Python syntax check"

if python3 -c "import py_compile; py_compile.compile('$SETUP_PY', doraise=True)" 2>/dev/null; then
  pass "setup.py compiles without syntax errors"
else
  fail "setup.py has syntax errors"
fi

# ── 2. DS token presence in inline CSS ─────────────────────────────
log "Step 2: Design system token presence"

# Body background should be neutral-950 (#0a0a0a)
if grep -q "background.*#0a0a0a" "$SETUP_PY" 2>/dev/null; then
  pass "Body uses neutral-950 (#0a0a0a)"
else
  fail "Body missing neutral-950 background"
fi

# Container background should be neutral-900 (#171717)
if grep -q "#171717" "$SETUP_PY" 2>/dev/null; then
  pass "Container uses neutral-900 (#171717)"
else
  fail "Container missing neutral-900"
fi

# Borders should use neutral-700 (#404040) or neutral-600 (#525252)
if grep -q "#404040\|#525252" "$SETUP_PY" 2>/dev/null; then
  pass "Borders use neutral-700/600 tokens"
else
  fail "Borders missing neutral-700/600 tokens"
fi

# Accent color should be accent-500 (#3b82f6) or accent-600 (#2563eb)
if grep -q "#3b82f6\|#2563eb" "$SETUP_PY" 2>/dev/null; then
  pass "Accent uses accent-500/600 tokens"
else
  fail "Accent missing accent-500/600"
fi

# Text color should be neutral-50 (#fafafa)
if grep -q "#fafafa" "$SETUP_PY" 2>/dev/null; then
  pass "Text uses neutral-50 (#fafafa)"
else
  fail "Text missing neutral-50"
fi

# DS font stack
if grep -q "apple-system.*BlinkMacSystemFont.*Segoe UI" "$SETUP_PY" 2>/dev/null; then
  pass "Uses DS font stack"
else
  fail "Missing DS font stack"
fi

# ── 3. No legacy values remain ─────────────────────────────────────
log "Step 3: Legacy value absence"

# No gradients (the key DS principle: "No gradients, no loud contrast")
if grep -q "linear-gradient" "$SETUP_PY" 2>/dev/null; then
  fail "Legacy linear-gradient still present"
else
  pass "No linear-gradient values"
fi

# No slate blues (#1e293b is the old container bg)
if grep -q "#1e293b" "$SETUP_PY" 2>/dev/null; then
  fail "Legacy slate-800 (#1e293b) still present"
else
  pass "No legacy slate-800 (#1e293b)"
fi

# No old dark bg (#0f172a was the old deep background)
if grep -q "#0f172a" "$SETUP_PY" 2>/dev/null; then
  fail "Legacy slate-900 (#0f172a) still present"
else
  pass "No legacy slate-900 (#0f172a)"
fi

# No purple (#8b5cf6 was the gradient end color)
if grep -q "#8b5cf6" "$SETUP_PY" 2>/dev/null; then
  fail "Legacy purple (#8b5cf6) still present"
else
  pass "No legacy purple (#8b5cf6)"
fi

# No old border color (#334155 was the old border)
if grep -q "#334155" "$SETUP_PY" 2>/dev/null; then
  fail "Legacy slate-700 (#334155) still present"
else
  pass "No legacy slate-700 (#334155)"
fi

# No old text colors (#e2e8f0, #cbd5e1)
if grep -q "#e2e8f0\|#cbd5e1" "$SETUP_PY" 2>/dev/null; then
  fail "Legacy slate text colors still present"
else
  pass "No legacy slate text colors"
fi

# ── 4. Live server check (best effort) ────────────────────────────
log "Step 4: Live server check (best effort)"

SETUP_HTML=$(curl -sf "${BASE_URL}/setup/" 2>/dev/null || echo "")

if [ -n "$SETUP_HTML" ]; then
  # Check HTTP 200 and HTML content
  SETUP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/setup/" 2>/dev/null || echo "000")
  if [ "$SETUP_STATUS" = "200" ]; then
    pass "/setup/ returns HTTP 200"
  else
    info "/setup/ returned HTTP $SETUP_STATUS (may be redirecting if setup already done)"
  fi

  # Check for DS tokens in response
  if echo "$SETUP_HTML" | grep -q "#0a0a0a"; then
    pass "Live /setup/ HTML contains neutral-950 token"
  else
    fail "Live /setup/ HTML missing DS tokens"
  fi

  # Check no gradients in response
  if echo "$SETUP_HTML" | grep -q "linear-gradient"; then
    fail "Live /setup/ HTML still has gradients"
  else
    pass "Live /setup/ HTML has no gradients"
  fi
else
  warn "Server not reachable at ${BASE_URL} — skipping live checks"
fi

# ── 5. Web frontend build check ───────────────────────────────────
log "Step 5: Web frontend build check (Docker)"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$WEB_DIR":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit && ./node_modules/.bin/vite build" \
      > /tmp/setup_smoke_build.log 2>&1; then
    pass "tsc --noEmit + vite build"
  else
    fail "Web build failed. Last 20 lines:"
    tail -20 /tmp/setup_smoke_build.log
  fi
else
  warn "Docker not available — skipping web build check"
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
