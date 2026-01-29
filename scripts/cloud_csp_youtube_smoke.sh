#!/usr/bin/env bash
# cloud_csp_youtube_smoke.sh - Smoke test for CLOUD-CSP-1: YouTube embed CSP fix
#
# Validates that the CSP in nginx.conf allows YouTube embeds:
#   1. frame-src includes https://www.youtube.com and https://www.youtube-nocookie.com
#   2. worker-src allows blob: (Vite/React tooling)
#   3. script-src-elem is NOT set to 'none' (would block scripts)
#   4. img-src includes i.ytimg.com (YouTube thumbnails)
#   5. No unsafe-eval in script-src
#   6. base-uri 'self' present (security hardening)
#   7. object-src 'none' present (security)
#
# Usage:
#   bash scripts/cloud_csp_youtube_smoke.sh
#   bash scripts/cloud_csp_youtube_smoke.sh --live http://192.168.0.19
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX_CONF="$REPO_ROOT/web/nginx.conf"

FAIL=0
LIVE_URL=""

log()  { echo "[cloud-csp-youtube]  $*"; }
pass() { echo "[cloud-csp-youtube]    PASS: $*"; }
fail() { echo "[cloud-csp-youtube]    FAIL: $*"; FAIL=1; }
skip() { echo "[cloud-csp-youtube]    SKIP: $*"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --live)
            LIVE_URL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--live http://host:port]"
            exit 1
            ;;
    esac
done

# ── Get CSP from source or live server ────────────────────────────────
get_csp() {
    if [[ -n "$LIVE_URL" ]]; then
        log "Fetching CSP from live server: $LIVE_URL"
        # Get headers and extract CSP
        local headers
        headers=$(curl -sS -D - -o /dev/null "$LIVE_URL/" 2>&1 || echo "")

        # Check for enforced CSP
        CSP_ENFORCED=$(echo "$headers" | grep -i "^content-security-policy:" | head -1 | sed 's/^[^:]*: //' || echo "")

        # Check for report-only CSP
        CSP_REPORT_ONLY=$(echo "$headers" | grep -i "^content-security-policy-report-only:" | head -1 | sed 's/^[^:]*: //' || echo "")

        if [[ -z "$CSP_ENFORCED" && -z "$CSP_REPORT_ONLY" ]]; then
            log "No CSP headers found in response"
            log "Headers received:"
            echo "$headers" | head -20
        fi
    else
        log "Checking CSP in source: $NGINX_CONF"

        if [[ ! -f "$NGINX_CONF" ]]; then
            fail "nginx.conf not found at $NGINX_CONF"
            return 1
        fi

        # Get the main SPA CSP (the longest CSP line, which is in the location / block)
        CSP_ENFORCED=$(grep 'add_header Content-Security-Policy' "$NGINX_CONF" | awk '{ print length, $0 }' | sort -rn | head -1 | sed 's/^[0-9]* *//' | sed 's/.*Content-Security-Policy "//' | sed 's/" always;$//' || echo "")
        CSP_REPORT_ONLY=""
    fi
}

# ── 1. Check frame-src includes YouTube ───────────────────────────────
check_frame_src() {
    log "Step 1: frame-src includes YouTube domains"

    if [[ -z "$CSP_ENFORCED" ]]; then
        fail "No enforced CSP found"
        return
    fi

    if echo "$CSP_ENFORCED" | grep -q "frame-src.*https://www.youtube.com"; then
        pass "frame-src includes https://www.youtube.com"
    else
        fail "frame-src missing https://www.youtube.com"
    fi

    if echo "$CSP_ENFORCED" | grep -q "frame-src.*https://www.youtube-nocookie.com"; then
        pass "frame-src includes https://www.youtube-nocookie.com"
    else
        fail "frame-src missing https://www.youtube-nocookie.com"
    fi
}

# ── 2. Check worker-src allows blob: ──────────────────────────────────
check_worker_src() {
    log "Step 2: worker-src allows blob:"

    if [[ -z "$CSP_ENFORCED" ]]; then
        skip "No enforced CSP found"
        return
    fi

    if echo "$CSP_ENFORCED" | grep -q "worker-src.*blob:"; then
        pass "worker-src includes blob:"
    elif echo "$CSP_ENFORCED" | grep -q "script-src.*blob:"; then
        pass "script-src includes blob: (worker-src fallback)"
    else
        fail "Neither worker-src nor script-src allow blob:"
    fi
}

# ── 3. Check script-src-elem is NOT 'none' ────────────────────────────
check_script_src_elem() {
    log "Step 3: script-src-elem is NOT 'none'"

    if [[ -z "$CSP_ENFORCED" ]]; then
        skip "No enforced CSP found"
        return
    fi

    if echo "$CSP_ENFORCED" | grep -q "script-src-elem.*'none'"; then
        fail "script-src-elem is 'none' - will block script elements"
    else
        pass "script-src-elem is not 'none'"
    fi
}

# ── 4. Check img-src includes YouTube thumbnails ─────────────────────
check_img_src() {
    log "Step 4: img-src includes YouTube thumbnail domains"

    if [[ -z "$CSP_ENFORCED" ]]; then
        skip "No enforced CSP found"
        return
    fi

    if echo "$CSP_ENFORCED" | grep -q "img-src.*i.ytimg.com"; then
        pass "img-src includes i.ytimg.com"
    else
        fail "img-src missing i.ytimg.com (YouTube thumbnails)"
    fi
}

# ── 5. Check no unsafe-eval in script-src ─────────────────────────────
check_no_unsafe_eval() {
    log "Step 5: No unsafe-eval in script-src"

    if [[ -z "$CSP_ENFORCED" ]]; then
        skip "No enforced CSP found"
        return
    fi

    if echo "$CSP_ENFORCED" | grep -q "script-src.*'unsafe-eval'"; then
        fail "script-src contains 'unsafe-eval' - security risk"
    else
        pass "No 'unsafe-eval' in script-src"
    fi
}

# ── 6. Check base-uri 'self' present ──────────────────────────────────
check_base_uri() {
    log "Step 6: base-uri 'self' present"

    if [[ -z "$CSP_ENFORCED" ]]; then
        skip "No enforced CSP found"
        return
    fi

    if echo "$CSP_ENFORCED" | grep -q "base-uri.*'self'"; then
        pass "base-uri 'self' present"
    else
        fail "base-uri 'self' missing - security hardening required"
    fi
}

# ── 7. Check object-src 'none' present ────────────────────────────────
check_object_src() {
    log "Step 7: object-src 'none' present"

    if [[ -z "$CSP_ENFORCED" ]]; then
        skip "No enforced CSP found"
        return
    fi

    if echo "$CSP_ENFORCED" | grep -q "object-src.*'none'"; then
        pass "object-src 'none' present"
    else
        fail "object-src 'none' missing - security hardening required"
    fi
}

# ── 8. Check report-only alignment (if present) ───────────────────────
check_report_only_alignment() {
    log "Step 8: Report-only CSP alignment"

    if [[ -z "$CSP_REPORT_ONLY" ]]; then
        skip "No report-only CSP (OK - not required)"
        return
    fi

    # If report-only exists, it should also allow YouTube
    if echo "$CSP_REPORT_ONLY" | grep -q "frame-src.*youtube"; then
        pass "Report-only CSP also allows YouTube"
    else
        fail "Report-only CSP does not align with enforced CSP (may cause console warnings)"
    fi
}

# ── Summary ───────────────────────────────────────────────────────────
main() {
    log "CLOUD-CSP-1: YouTube Embed CSP Smoke Test"
    echo ""

    get_csp

    if [[ -n "$CSP_ENFORCED" ]]; then
        log "CSP found (first 200 chars):"
        echo "  ${CSP_ENFORCED:0:200}..."
        echo ""
    fi

    check_frame_src
    check_worker_src
    check_script_src_elem
    check_img_src
    check_no_unsafe_eval
    check_base_uri
    check_object_src
    check_report_only_alignment

    echo ""
    if [[ "$FAIL" -eq 0 ]]; then
        log "ALL CHECKS PASSED"
        exit 0
    else
        log "SOME CHECKS FAILED"
        exit 1
    fi
}

main "$@"
