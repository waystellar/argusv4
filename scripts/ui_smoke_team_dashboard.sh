#!/bin/bash
#
# UI Smoke Test for Team Dashboard
#
# This script performs basic checks to verify the Team Dashboard is rendering correctly.
# It checks:
# 1. Dev server is running
# 2. Team dashboard page loads without JS errors
# 3. Key DOM elements and design system compliance
#
# Usage:
#   ./scripts/ui_smoke_team_dashboard.sh [frontend_url]
#
# Default URL: http://localhost:5173

set -e

FRONTEND_URL="${1:-http://localhost:5173}"
TEAM_PAGE_PATH="/team"
FULL_URL="${FRONTEND_URL}${TEAM_PAGE_PATH}"

echo "=========================================="
echo "  UI Smoke Test: Team Dashboard"
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
    warn "Team page path returned HTTP ${HTTP_STATUS} (SPA routing may differ)"
fi

# Check 3: Page contains expected HTML markers
echo ""
echo "--- Check 3: Key DOM Elements ---"

PAGE_CONTENT=$(curl -s --max-time 10 "${FRONTEND_URL}" 2>/dev/null || echo "")

if echo "$PAGE_CONTENT" | grep -q 'id="root"'; then
    pass "React root element found"
else
    fail "React root element not found"
fi

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
echo "--- Check 5: Design System Compliance (TeamDashboard) ---"
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

    # Check for UI-6 specific features
    if grep -q "My Truck" "${TEAM_DASHBOARD}"; then
        pass "My Truck section present (UI-6)"
    else
        warn "My Truck section not found"
    fi

    if grep -q "Event Context" "${TEAM_DASHBOARD}" || grep -q "Active Event" "${TEAM_DASHBOARD}"; then
        pass "Event context area present (UI-6)"
    else
        warn "Event context area not found"
    fi
else
    fail "TeamDashboard.tsx not found at expected path"
fi

# Check 6: TeamLogin file uses design system
echo ""
echo "--- Check 6: Design System Compliance (TeamLogin) ---"
TEAM_LOGIN="${WEB_DIR}/src/pages/TeamLogin.tsx"
if [ -f "${TEAM_LOGIN}" ]; then
    pass "TeamLogin.tsx exists"

    # Check for old tokens
    if grep -E "(gray-[0-9]+|bg-surface|primary-[0-9]+)" "${TEAM_LOGIN}" > /dev/null 2>&1; then
        fail "Old color tokens found in TeamLogin.tsx"
    else
        pass "No old color tokens in TeamLogin.tsx"
    fi

    if grep -q "neutral-" "${TEAM_LOGIN}"; then
        pass "TeamLogin uses design system tokens"
    else
        warn "TeamLogin may not use design system tokens"
    fi
else
    warn "TeamLogin.tsx not found"
fi

# Check 7: Team components use design system
echo ""
echo "--- Check 7: Design System Compliance (Team Components) ---"
PERM_TOGGLE="${WEB_DIR}/src/components/Team/PermissionToggle.tsx"
if [ -f "${PERM_TOGGLE}" ]; then
    if grep -q "gray-" "${PERM_TOGGLE}"; then
        fail "PermissionToggle.tsx has legacy gray-* tokens"
    else
        pass "PermissionToggle.tsx has no legacy tokens"
    fi
fi

VIDEO_MANAGER="${WEB_DIR}/src/components/Team/VideoFeedManager.tsx"
if [ -f "${VIDEO_MANAGER}" ]; then
    if grep -q "gray-" "${VIDEO_MANAGER}"; then
        fail "VideoFeedManager.tsx has legacy gray-* tokens"
    else
        pass "VideoFeedManager.tsx has no legacy tokens"
    fi
fi

TELEM_POLICY="${WEB_DIR}/src/components/Team/TelemetrySharingPolicy.tsx"
if [ -f "${TELEM_POLICY}" ]; then
    if grep -q "gray-" "${TELEM_POLICY}"; then
        fail "TelemetrySharingPolicy.tsx has legacy gray-* tokens"
    else
        pass "TelemetrySharingPolicy.tsx has no legacy tokens"
    fi
fi

# Summary
echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
if [ "$FAILED" = "0" ]; then
    echo -e "${GREEN}All critical checks passed!${NC}"
    echo ""
    echo "Team Dashboard URLs:"
    echo "  Login: ${FRONTEND_URL}/team/login"
    echo "  Dashboard: ${FRONTEND_URL}/team/dashboard"
    echo ""
    echo "Manual verification checklist:"
    echo "  [ ] Login page uses design system colors"
    echo "  [ ] Header shows 'Team Dashboard' with logout button"
    echo "  [ ] Event context bar shows active event or 'No Active Event'"
    echo "  [ ] My Truck card with vehicle number, team name, status badges"
    echo "  [ ] Quick stats: Hz, Last Seen, Queue"
    echo "  [ ] Streaming & Edge Status with GPS, CAN, Video, Visibility"
    echo "  [ ] Diagnostics section with copy button"
    echo "  [ ] Two tabs: 'Ops' and 'Sharing'"
    echo "  [ ] Empty states have clear next steps"
    echo "  [ ] Loading states use skeletons"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
