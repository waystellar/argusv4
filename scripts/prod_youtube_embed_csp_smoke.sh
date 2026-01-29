#!/usr/bin/env bash
# prod_youtube_embed_csp_smoke.sh - Smoke test for YouTube Embed CSP Configuration
#
# Validates:
#   nginx.conf CSP:
#     1.  frame-src includes https://www.youtube.com
#     2.  frame-src includes https://www.youtube-nocookie.com
#     3.  frame-src does NOT use wildcard * for YouTube
#     4.  img-src includes i.ytimg.com (YouTube thumbnails)
#     5.  img-src includes *.ytimg.com
#     6.  No wildcard * in frame-src
#     7.  object-src 'none' (XSS hardening)
#     8.  frame-ancestors 'self' (clickjacking protection)
#     9.  X-Frame-Options SAMEORIGIN header present
#    10.  CLOUD-CSP-1 marker present
#   ControlRoom.tsx:
#    11.  YouTube iframe element exists
#    12.  iframe src uses youtube.com/embed
#    13.  iframe has allow="autoplay; encrypted-media"
#    14.  iframe has allowFullScreen
#    15.  YouTube URL extraction function exists
#    16.  Featured feed youtube_url used
#   production.py:
#    17.  VideoFeed model referenced (YouTube URL storage)
#    18.  youtube_url field exists in response schema
#
# Usage:
#   bash scripts/prod_youtube_embed_csp_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[yt-csp]  $*"; }
pass() { echo "[yt-csp]    PASS: $*"; }
fail() { echo "[yt-csp]    FAIL: $*"; FAIL=1; }

NGINX_CONF="$REPO_ROOT/web/nginx.conf"
CONTROL_TSX="$REPO_ROOT/web/src/pages/ControlRoom.tsx"
PROD_PY="$REPO_ROOT/cloud/app/routes/production.py"

log "PROD-YT-CSP: YouTube Embed CSP Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# NGINX CSP
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$NGINX_CONF" ]; then
  fail "nginx.conf not found"
  exit 1
fi

# Get the main SPA CSP (the longest CSP line — the one on the / location block)
CSP=$(grep 'add_header Content-Security-Policy' "$NGINX_CONF" | awk '{ print length, $0 }' | sort -rn | head -1 | sed 's/^[0-9]* *//' || echo "")

if [ -z "$CSP" ]; then
  fail "No Content-Security-Policy header found in nginx.conf"
  exit 1
fi

# Extract frame-src directive
FRAME_SRC=$(echo "$CSP" | grep -oE "frame-src[^;]*" | head -1)

# ── 1. frame-src includes youtube.com ─────────────────────────────
log "Step 1: frame-src includes https://www.youtube.com"

if echo "$FRAME_SRC" | grep -q 'https://www.youtube.com'; then
  pass "frame-src includes https://www.youtube.com"
else
  fail "frame-src missing https://www.youtube.com"
fi

# ── 2. frame-src includes youtube-nocookie.com ────────────────────
log "Step 2: frame-src includes https://www.youtube-nocookie.com"

if echo "$FRAME_SRC" | grep -q 'https://www.youtube-nocookie.com'; then
  pass "frame-src includes https://www.youtube-nocookie.com"
else
  fail "frame-src missing https://www.youtube-nocookie.com"
fi

# ── 3. frame-src does NOT use wildcard for YouTube ────────────────
log "Step 3: frame-src does NOT use wildcard for YouTube"

if echo "$FRAME_SRC" | grep -q 'https://\*.youtube'; then
  fail "frame-src uses wildcard *.youtube (should be explicit domains)"
else
  pass "No wildcard *.youtube in frame-src"
fi

# ── 4. img-src includes i.ytimg.com ──────────────────────────────
log "Step 4: img-src includes i.ytimg.com"

IMG_SRC=$(echo "$CSP" | grep -oE "img-src[^;]*" | head -1)

if echo "$IMG_SRC" | grep -q 'i.ytimg.com'; then
  pass "img-src includes i.ytimg.com"
else
  fail "img-src missing i.ytimg.com"
fi

# ── 5. img-src includes *.ytimg.com ──────────────────────────────
log "Step 5: img-src includes *.ytimg.com"

if echo "$IMG_SRC" | grep -q 'ytimg.com'; then
  pass "img-src includes ytimg.com domain"
else
  fail "img-src missing ytimg.com"
fi

# ── 6. No bare wildcard * in frame-src ────────────────────────────
log "Step 6: No bare wildcard * in frame-src"

# Check for standalone * (not https://*.domain which is fine)
if echo "$FRAME_SRC" | grep -qE " \*[^.]| \*$|'\*'"; then
  fail "frame-src has bare wildcard * (security risk)"
else
  pass "No bare wildcard in frame-src"
fi

# ── 7. object-src 'none' ─────────────────────────────────────────
log "Step 7: object-src 'none'"

if echo "$CSP" | grep -q "object-src 'none'"; then
  pass "object-src 'none' (XSS hardening)"
else
  fail "Missing object-src 'none'"
fi

# ── 8. frame-ancestors 'self' ─────────────────────────────────────
log "Step 8: frame-ancestors 'self'"

if echo "$CSP" | grep -q "frame-ancestors 'self'"; then
  pass "frame-ancestors 'self' (clickjacking protection)"
else
  fail "Missing frame-ancestors 'self'"
fi

# ── 9. X-Frame-Options header ─────────────────────────────────────
log "Step 9: X-Frame-Options SAMEORIGIN"

if grep -q 'X-Frame-Options.*SAMEORIGIN' "$NGINX_CONF"; then
  pass "X-Frame-Options SAMEORIGIN present"
else
  fail "X-Frame-Options SAMEORIGIN missing"
fi

# ── 10. CLOUD-CSP-1 marker ────────────────────────────────────────
log "Step 10: CLOUD-CSP-1 marker"

if grep -q 'CLOUD-CSP-1' "$NGINX_CONF"; then
  pass "CLOUD-CSP-1 marker present"
else
  fail "CLOUD-CSP-1 marker missing"
fi

# ═══════════════════════════════════════════════════════════════════
# CONTROLROOM (ControlRoom.tsx)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$CONTROL_TSX" ]; then
  fail "ControlRoom.tsx not found"
  exit 1
fi

# ── 11. YouTube iframe exists ─────────────────────────────────────
log "Step 11: YouTube iframe element exists"

if grep -q '<iframe' "$CONTROL_TSX"; then
  pass "iframe element exists"
else
  fail "No iframe element in ControlRoom"
fi

# ── 12. iframe src uses youtube.com/embed ─────────────────────────
log "Step 12: iframe src uses youtube.com/embed"

if grep -q 'youtube.com/embed' "$CONTROL_TSX"; then
  pass "iframe src uses youtube.com/embed"
else
  fail "iframe src not using youtube.com/embed"
fi

# ── 13. iframe has autoplay + encrypted-media ─────────────────────
log "Step 13: iframe has allow autoplay + encrypted-media"

if grep -q 'allow=.*autoplay' "$CONTROL_TSX"; then
  pass "iframe allows autoplay"
else
  fail "iframe missing autoplay allow"
fi

if grep -q 'encrypted-media' "$CONTROL_TSX"; then
  pass "iframe allows encrypted-media"
else
  fail "iframe missing encrypted-media"
fi

# ── 14. iframe has allowFullScreen ─────────────────────────────────
log "Step 14: iframe has allowFullScreen"

if grep -q 'allowFullScreen' "$CONTROL_TSX"; then
  pass "iframe has allowFullScreen"
else
  fail "iframe missing allowFullScreen"
fi

# ── 15. YouTube URL extraction function ───────────────────────────
log "Step 15: YouTube URL extraction function"

if grep -q 'extractYouTubeId\|youtube.*extract\|youtubeId' "$CONTROL_TSX"; then
  pass "YouTube URL extraction function exists"
else
  fail "No YouTube URL extraction function"
fi

# ── 16. Featured feed youtube_url used ────────────────────────────
log "Step 16: Featured feed youtube_url used"

if grep -q 'youtube_url' "$CONTROL_TSX"; then
  pass "youtube_url field referenced"
else
  fail "youtube_url not referenced"
fi

# ═══════════════════════════════════════════════════════════════════
# CLOUD (production.py)
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$PROD_PY" ]; then
  fail "production.py not found"
  exit 1
fi

# ── 17. VideoFeed model referenced ────────────────────────────────
log "Step 17: VideoFeed model referenced"

if grep -q 'VideoFeed' "$PROD_PY"; then
  pass "VideoFeed model referenced"
else
  fail "VideoFeed model not referenced"
fi

# ── 18. youtube_url in schema ─────────────────────────────────────
log "Step 18: youtube_url in response schema"

if grep -q 'youtube_url' "$PROD_PY"; then
  pass "youtube_url field in schema"
else
  fail "youtube_url not in schema"
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
