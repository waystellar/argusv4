#!/usr/bin/env bash
# fan_youtube_csp_smoke.sh - Smoke test for FAN-VIDEO-2: YouTube embed CSP fix for fan Watch Live
#
# Validates (source-level):
#   1. CSP header in nginx.conf contains frame-src directive
#   2. frame-src includes 'self', youtube.com, and youtube-nocookie.com
#   3. frame-src does NOT contain 'none' (would block all frames)
#   4. worker-src includes 'self' and blob: (for Vite/PWA/Map workers)
#   5. img-src includes YouTube thumbnail domain (i.ytimg.com)
#   6. YouTubeEmbed.tsx uses /embed/ URL format
#   7. WatchTab.tsx getYouTubeEmbedUrl converts to /embed/ format
#   8. VehiclePage.tsx uses YouTubeEmbed component
#   9. TypeScript check passes (tsc --noEmit)
#
# Usage:
#   bash scripts/fan_youtube_csp_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NGINX="$REPO_ROOT/web/nginx.conf"
YOUTUBE_EMBED="$REPO_ROOT/web/src/components/VehicleDetail/YouTubeEmbed.tsx"
WATCH_TAB="$REPO_ROOT/web/src/components/RaceCenter/WatchTab.tsx"
VEHICLE_PAGE="$REPO_ROOT/web/src/pages/VehiclePage.tsx"

FAIL=0

log()  { echo "[fan-youtube-csp]  $*"; }
pass() { echo "[fan-youtube-csp]    PASS: $*"; }
fail() { echo "[fan-youtube-csp]    FAIL: $*"; FAIL=1; }

# ── 1. CSP header exists in nginx.conf ────────────────────────
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

# ── 2. Extract main CSP (SPA location / block) ────────────────
log "Step 2: Extract and display main CSP"

# The main SPA CSP is in the location / block (the longest CSP line)
CSP_LINE=$(grep 'add_header Content-Security-Policy "' "$NGINX" | awk '{ print length, $0 }' | sort -rn | head -1 | cut -d' ' -f2-)

if [ -n "$CSP_LINE" ]; then
  # Extract just the CSP value (between quotes)
  CSP_VALUE=$(echo "$CSP_LINE" | sed 's/.*Content-Security-Policy "\([^"]*\)".*/\1/')
  echo ""
  log "Main CSP policy:"
  echo "$CSP_VALUE" | tr ';' '\n' | sed 's/^ */    /'
  echo ""
  pass "CSP extracted successfully"
else
  fail "Could not extract CSP line"
  exit 1
fi

# ── 3. frame-src includes YouTube domains ─────────────────────
log "Step 3: frame-src includes YouTube domains"

if echo "$CSP_VALUE" | grep -q "frame-src"; then
  pass "frame-src directive exists"
else
  fail "frame-src directive is MISSING (default-src fallback would block YouTube)"
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

# ── 4. frame-src does NOT contain 'none' ──────────────────────
log "Step 4: frame-src does NOT block all frames"

if echo "$CSP_VALUE" | grep -q "frame-src 'none'"; then
  fail "frame-src is set to 'none' - YouTube embeds will be blocked!"
else
  pass "frame-src is NOT 'none'"
fi

# ── 5. worker-src includes blob: ──────────────────────────────
log "Step 5: worker-src includes blob: for Vite/PWA workers"

if echo "$CSP_VALUE" | grep -q "worker-src.*blob:"; then
  pass "worker-src includes blob:"
else
  fail "worker-src missing blob: (blob workers will be blocked)"
fi

# ── 6. img-src includes YouTube thumbnail domain ──────────────
log "Step 6: img-src includes YouTube thumbnail domain"

if echo "$CSP_VALUE" | grep -q "img-src.*ytimg.com"; then
  pass "img-src includes ytimg.com (YouTube thumbnails)"
else
  fail "img-src missing ytimg.com (thumbnails may be blocked)"
fi

# ── 7. YouTubeEmbed.tsx uses /embed/ URL format ───────────────
log "Step 7: YouTubeEmbed.tsx uses /embed/ URL format"

if [ -f "$YOUTUBE_EMBED" ]; then
  if grep -q 'youtube.com/embed/' "$YOUTUBE_EMBED"; then
    pass "YouTubeEmbed.tsx uses /embed/ URL format"
  else
    fail "YouTubeEmbed.tsx does NOT use /embed/ URL format"
  fi
else
  fail "YouTubeEmbed.tsx not found"
fi

# ── 8. WatchTab.tsx getYouTubeEmbedUrl uses /embed/ ───────────
log "Step 8: WatchTab.tsx converts URLs to /embed/ format"

if [ -f "$WATCH_TAB" ]; then
  if grep -q 'youtube.com/embed/' "$WATCH_TAB"; then
    pass "WatchTab.tsx uses /embed/ URL format"
  else
    fail "WatchTab.tsx does NOT convert to /embed/ URL format"
  fi
else
  fail "WatchTab.tsx not found"
fi

# ── 9. VehiclePage.tsx uses YouTubeEmbed component ────────────
log "Step 9: VehiclePage.tsx uses YouTubeEmbed component"

if [ -f "$VEHICLE_PAGE" ]; then
  if grep -q 'YouTubeEmbed' "$VEHICLE_PAGE"; then
    pass "VehiclePage.tsx uses YouTubeEmbed component"
  else
    fail "VehiclePage.tsx does NOT use YouTubeEmbed component"
  fi
else
  fail "VehiclePage.tsx not found"
fi

# ── 10. TypeScript check ──────────────────────────────────────
log "Step 10: TypeScript check (tsc --noEmit)"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$REPO_ROOT/web":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit" \
      > /tmp/fan_youtube_csp_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed. Last 20 lines:"
    tail -20 /tmp/fan_youtube_csp_build.log
  fi
elif command -v npm >/dev/null 2>&1; then
  if (cd "$REPO_ROOT/web" && npx tsc --noEmit) > /tmp/fan_youtube_csp_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed"
    tail -20 /tmp/fan_youtube_csp_build.log
  fi
else
  echo "[fan-youtube-csp]    SKIP: Neither docker nor npm available"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
