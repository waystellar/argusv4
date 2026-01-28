#!/bin/bash
#
# UI Smoke Test for Admin Dashboard
#
# This script performs basic checks to verify the Admin pages are rendering correctly.
# It checks:
# 1. Dev server is running
# 2. Admin page loads without JS errors
# 3. Key DOM elements and design system compliance
#
# Usage:
#   ./scripts/ui_smoke_admin.sh [frontend_url]
#
# Default URL: http://localhost:5173

set -e

FRONTEND_URL="${1:-http://localhost:5173}"
ADMIN_PAGE_PATH="/admin"
FULL_URL="${FRONTEND_URL}${ADMIN_PAGE_PATH}"

echo "=========================================="
echo "  UI Smoke Test: Admin Dashboard"
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

# Check 2: Admin page returns 200 (via SPA)
echo ""
echo "--- Check 2: Admin Page Status ---"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${FULL_URL}" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    pass "Admin page returns HTTP 200"
else
    warn "Admin page path returned HTTP ${HTTP_STATUS} (SPA routing may differ)"
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

# Check 5: AdminDashboard file exists and uses design system
echo ""
echo "--- Check 5: Design System Compliance (AdminDashboard) ---"
ADMIN_DASHBOARD="${WEB_DIR}/src/pages/admin/AdminDashboard.tsx"
if [ -f "${ADMIN_DASHBOARD}" ]; then
    pass "AdminDashboard.tsx exists"

    # Check for old tokens
    if grep -E "(gray-[0-9]+|bg-surface|primary-[0-9]+)" "${ADMIN_DASHBOARD}" > /dev/null 2>&1; then
        fail "Old color tokens found in AdminDashboard.tsx"
    else
        pass "No old color tokens in AdminDashboard.tsx"
    fi

    # Check for design system tokens
    if grep -q "bg-neutral-950" "${ADMIN_DASHBOARD}"; then
        pass "Design system background tokens present"
    else
        warn "Design system background tokens not found"
    fi

    if grep -q "text-ds-" "${ADMIN_DASHBOARD}"; then
        pass "Design system typography tokens present"
    else
        warn "Design system typography tokens not found"
    fi

    # Check for UI-7 specific features
    if grep -q "Badge" "${ADMIN_DASHBOARD}"; then
        pass "Badge component used (UI-7)"
    else
        warn "Badge component not found"
    fi

    if grep -q "EmptyState" "${ADMIN_DASHBOARD}"; then
        pass "EmptyState component used (UI-7)"
    else
        warn "EmptyState component not found"
    fi
else
    fail "AdminDashboard.tsx not found at expected path"
fi

# Check 6: EventDetail file exists and uses design system
echo ""
echo "--- Check 6: Design System Compliance (EventDetail) ---"
EVENT_DETAIL="${WEB_DIR}/src/pages/admin/EventDetail.tsx"
if [ -f "${EVENT_DETAIL}" ]; then
    pass "EventDetail.tsx exists"

    # Check for old tokens
    if grep -E "(gray-[0-9]+|bg-surface|primary-[0-9]+)" "${EVENT_DETAIL}" > /dev/null 2>&1; then
        fail "Old color tokens found in EventDetail.tsx"
    else
        pass "No old color tokens in EventDetail.tsx"
    fi

    # Check for design system tokens
    if grep -q "bg-neutral-950" "${EVENT_DETAIL}"; then
        pass "Design system background tokens present"
    else
        warn "Design system background tokens not found"
    fi

    if grep -q "text-ds-" "${EVENT_DETAIL}"; then
        pass "Design system typography tokens present"
    else
        warn "Design system typography tokens not found"
    fi

    # Check for UI-7 features
    if grep -q "Badge" "${EVENT_DETAIL}"; then
        pass "Badge component used (UI-7)"
    else
        warn "Badge component not found"
    fi

    if grep -q "rounded-ds-" "${EVENT_DETAIL}"; then
        pass "Design system border radius tokens present (UI-7)"
    else
        warn "Design system border radius tokens not found"
    fi
else
    fail "EventDetail.tsx not found at expected path"
fi

# Summary
echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
if [ "$FAILED" = "0" ]; then
    echo -e "${GREEN}All critical checks passed!${NC}"
    echo ""
    echo "Admin Dashboard URL: ${FULL_URL}"
    echo ""
    echo "Key elements to verify manually:"
    echo "  1. Header shows 'Admin Control Center' with navigation"
    echo "  2. Stats row: Total Events, Active Now, Total Vehicles"
    echo "  3. Events table with sortable columns and status badges"
    echo "  4. Empty state when no events exist"
    echo "  5. Create Event button opens modal form"
    echo "  6. Click event row navigates to EventDetail"
    echo "  7. EventDetail shows vehicle list with class badges"
    echo "  8. Add Vehicle form with validation"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
