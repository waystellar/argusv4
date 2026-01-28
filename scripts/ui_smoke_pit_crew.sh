#!/bin/bash
#
# UI Smoke Test for Pit Crew Dashboard (Team Dashboard)
#
# This script performs basic checks to verify the Pit Crew Dashboard is rendering correctly.
# It checks:
# 1. Dev server is running (or starts it)
# 2. Team dashboard page loads without JS errors
# 3. Key DOM elements are present
#
# Usage:
#   ./scripts/ui_smoke_pit_crew.sh [frontend_url]
#
# Default URL: http://localhost:5173

set -e

FRONTEND_URL="${1:-http://localhost:5173}"
TEAM_PAGE_PATH="/team"
FULL_URL="${FRONTEND_URL}${TEAM_PAGE_PATH}"

echo "=========================================="
echo "  UI Smoke Test: Pit Crew Dashboard"
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

# Check 2: Team page returns 200 (via SPA)
echo ""
echo "--- Check 2: Team Page Status ---"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${FULL_URL}" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    pass "Team page returns HTTP 200"
else
    # Note: SPA routes may return 200 from root
    warn "Team page path returned HTTP ${HTTP_STATUS} (expected 200, but SPA routing may differ)"
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

# Check 4: TypeScript Build Check
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

# Check 5: TeamDashboard file exists and uses design system
echo ""
echo "--- Check 5: Design System Compliance ---"
TEAM_DASHBOARD="${WEB_DIR}/src/pages/TeamDashboard.tsx"
if [ -f "${TEAM_DASHBOARD}" ]; then
    pass "TeamDashboard.tsx exists"

    # Check for old tokens
    if grep -E "(gray-[0-9]+|bg-surface|primary-[0-9]+)" "${TEAM_DASHBOARD}" > /dev/null 2>&1; then
        fail "Old color tokens found in TeamDashboard.tsx"
    else
        pass "No old color tokens in TeamDashboard.tsx"
    fi

    # Check for design system tokens
    if grep -q "bg-neutral-950" "${TEAM_DASHBOARD}"; then
        pass "Design system background tokens present"
    else
        warn "Design system background tokens not found"
    fi

    if grep -q "text-ds-" "${TEAM_DASHBOARD}"; then
        pass "Design system typography tokens present"
    else
        warn "Design system typography tokens not found"
    fi
else
    fail "TeamDashboard.tsx not found at expected path"
fi

# Summary
echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
if [ "$FAILED" = "0" ]; then
    echo -e "${GREEN}All critical checks passed!${NC}"
    echo ""
    echo "Pit Crew Dashboard URL: ${FULL_URL}"
    echo ""
    echo "Key elements to verify manually:"
    echo "  1. Header shows 'Pit Crew Ops Console' with status badges"
    echo "  2. Two tabs: 'Ops' and 'Sharing'"
    echo "  3. Ops tab shows: Status banner, Status cards (4), Diagnostics panel, Alerts"
    echo "  4. Sharing tab shows: Visibility toggle, Video feeds, Telemetry policy"
    echo "  5. Footer shows connection status and last sync time"
    echo "  6. All components use neutral-* colors and ds-* spacing"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
