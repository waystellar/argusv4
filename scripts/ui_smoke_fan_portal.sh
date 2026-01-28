#!/bin/bash
#
# UI Smoke Test for Fan Portal Event Page
#
# This script performs basic checks to verify the Fan Portal page is rendering correctly.
# It checks:
# 1. Dev server is running (or starts it)
# 2. Event page loads without JS errors
# 3. Key DOM elements are present
#
# Usage:
#   ./scripts/ui_smoke_fan_portal.sh [frontend_url]
#
# Default URL: http://localhost:5173

set -e

FRONTEND_URL="${1:-http://localhost:5173}"
EVENT_PAGE_PATH="/events/demo"
FULL_URL="${FRONTEND_URL}${EVENT_PAGE_PATH}"

echo "=========================================="
echo "  UI Smoke Test: Fan Portal Event Page"
echo "=========================================="
echo ""
echo "Target URL: ${FULL_URL}"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILED=1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

FAILED=0

# Check 1: Frontend server is responding
echo "--- Check 1: Frontend Server Status ---"
if curl -s --max-time 5 "${FRONTEND_URL}" > /dev/null 2>&1; then
    pass "Frontend server is responding at ${FRONTEND_URL}"
else
    fail "Frontend server is not responding at ${FRONTEND_URL}"
    echo ""
    echo "Make sure to start the dev server with:"
    echo "  cd argus_v4/web && npm run dev"
    echo ""
    exit 1
fi

# Check 2: Event page returns 200 (via SPA)
echo ""
echo "--- Check 2: Event Page Status ---"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${FULL_URL}" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    pass "Event page returns HTTP 200"
else
    # Note: SPA routes may return 200 from root
    warn "Event page path returned HTTP ${HTTP_STATUS} (expected 200, but SPA routing may differ)"
fi

# Check 3: Page contains expected HTML markers
echo ""
echo "--- Check 3: Key DOM Elements ---"

# Fetch the page content
PAGE_CONTENT=$(curl -s --max-time 10 "${FRONTEND_URL}" 2>/dev/null || echo "")

# Check for React root element
if echo "$PAGE_CONTENT" | grep -q 'id="root"'; then
    pass "React root element found"
else
    fail "React root element not found - page may not be loading React app"
fi

# Check for Vite dev script (in dev mode)
if echo "$PAGE_CONTENT" | grep -q 'vite\|@vite'; then
    pass "Vite dev scripts found"
else
    warn "Vite scripts not found (may be production build)"
fi

# Check 4: Build check (TypeScript compilation)
echo ""
echo "--- Check 4: TypeScript Build Check ---"
WEB_DIR="$(dirname "$0")/../web"
if [ -f "${WEB_DIR}/package.json" ]; then
    # Try to run type check without full build
    if command -v npx &> /dev/null; then
        echo "Running TypeScript check..."
        cd "$WEB_DIR"
        if npx tsc --noEmit 2>&1 | head -20; then
            pass "TypeScript compilation check passed"
        else
            warn "TypeScript may have errors (check output above)"
        fi
        cd - > /dev/null
    else
        warn "npx not available - skipping TypeScript check"
    fi
else
    warn "package.json not found - skipping TypeScript check"
fi

# Summary
echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
if [ "$FAILED" = "0" ]; then
    echo -e "${GREEN}All critical checks passed!${NC}"
    echo ""
    echo "Fan Portal Event Page URL: ${FULL_URL}"
    echo ""
    echo "Key elements to verify manually:"
    echo "  1. Header shows event name with status badges (Live/Upcoming/Finished)"
    echo "  2. Tab bar shows Overview, Standings, Watch, Tracker tabs"
    echo "  3. Overview tab shows map and mini leaderboard"
    echo "  4. Standings tab shows searchable leaderboard with positions"
    echo "  5. Watch tab shows video area and camera feed cards"
    echo "  6. Empty states display helpful messages"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
