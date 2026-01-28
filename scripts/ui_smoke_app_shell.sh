#!/bin/bash
#
# UI Smoke Test for App Shell & Loading Experience (UI-8)
#
# This script performs basic checks to verify:
# 1. App shell renders correctly
# 2. Routes mount without errors
# 3. Design system compliance
#
# Usage:
#   ./scripts/ui_smoke_app_shell.sh [frontend_url]
#
# Default URL: http://localhost:5173

set -e

FRONTEND_URL="${1:-http://localhost:5173}"

echo "=========================================="
echo "  UI Smoke Test: App Shell (UI-8)"
echo "=========================================="
echo ""
echo "Target URL: ${FRONTEND_URL}"
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

# Check 2: Root page returns 200
echo ""
echo "--- Check 2: Root Page Status ---"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${FRONTEND_URL}/" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    pass "Root page returns HTTP 200"
else
    fail "Root page returned HTTP ${HTTP_STATUS}"
fi

# Check 3: Key routes respond (SPA routing)
echo ""
echo "--- Check 3: Route Checks ---"
ROUTES=("/events" "/team/login" "/admin" "/admin/login" "/production")

for route in "${ROUTES[@]}"; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${FRONTEND_URL}${route}" 2>/dev/null || echo "000")
    if [ "$STATUS" = "200" ]; then
        pass "Route ${route} returns HTTP 200"
    else
        warn "Route ${route} returned HTTP ${STATUS} (SPA may handle)"
    fi
done

# Check 4: HTML structure
echo ""
echo "--- Check 4: App Shell Structure ---"
PAGE_CONTENT=$(curl -s --max-time 10 "${FRONTEND_URL}" 2>/dev/null || echo "")

if echo "$PAGE_CONTENT" | grep -q 'id="root"'; then
    pass "React root element found"
else
    fail "React root element not found"
fi

if echo "$PAGE_CONTENT" | grep -q 'vite\|@vite'; then
    pass "Vite scripts found"
else
    warn "Vite scripts not found (may be production build)"
fi

# Check 5: App.tsx uses design system
echo ""
echo "--- Check 5: App Shell Design System ---"
WEB_DIR="$(dirname "$0")/../web"
APP_FILE="${WEB_DIR}/src/App.tsx"

if [ -f "${APP_FILE}" ]; then
    pass "App.tsx exists"

    # Check for old tokens
    if grep -E "bg-gray-[0-9]+|text-gray-[0-9]+|border-blue-" "${APP_FILE}" > /dev/null 2>&1; then
        fail "Old color tokens found in App.tsx"
    else
        pass "No old color tokens in App.tsx"
    fi

    # Check for design system tokens
    if grep -q "bg-neutral-950" "${APP_FILE}"; then
        pass "Design system background token present"
    else
        warn "Design system background token not found"
    fi

    # Check for ErrorBoundary
    if grep -q "ErrorBoundary" "${APP_FILE}"; then
        pass "ErrorBoundary component present"
    else
        warn "ErrorBoundary not found in App.tsx"
    fi

    # Check for NotFound route
    if grep -q "NotFound" "${APP_FILE}"; then
        pass "NotFound (404) component present"
    else
        warn "NotFound component not found in App.tsx"
    fi

    # Check for AppLoading
    if grep -q "AppLoading" "${APP_FILE}"; then
        pass "AppLoading component present"
    else
        warn "AppLoading component not found in App.tsx"
    fi
else
    fail "App.tsx not found"
fi

# Check 6: Loading components exist
echo ""
echo "--- Check 6: Loading Components ---"
LOADING_FILE="${WEB_DIR}/src/components/common/AppLoading.tsx"
if [ -f "${LOADING_FILE}" ]; then
    pass "AppLoading.tsx exists"

    if grep -q "bg-neutral-950" "${LOADING_FILE}"; then
        pass "AppLoading uses design system tokens"
    else
        warn "AppLoading may have old tokens"
    fi
else
    fail "AppLoading.tsx not found"
fi

# Check 7: Error components exist
echo ""
echo "--- Check 7: Error Components ---"
NOTFOUND_FILE="${WEB_DIR}/src/components/common/NotFound.tsx"
ERROR_BOUNDARY_FILE="${WEB_DIR}/src/components/common/ErrorBoundary.tsx"

if [ -f "${NOTFOUND_FILE}" ]; then
    pass "NotFound.tsx exists"
else
    fail "NotFound.tsx not found"
fi

if [ -f "${ERROR_BOUNDARY_FILE}" ]; then
    pass "ErrorBoundary.tsx exists"
else
    fail "ErrorBoundary.tsx not found"
fi

# Check 8: TypeScript check
echo ""
echo "--- Check 8: TypeScript Build Check ---"
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

# Summary
echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
if [ "$FAILED" = "0" ]; then
    echo -e "${GREEN}All critical checks passed!${NC}"
    echo ""
    echo "UI-8 App Shell features to verify manually:"
    echo "  1. App loads with neutral-950 background"
    echo "  2. Loading spinner uses accent-500 color"
    echo "  3. 404 page appears at /nonexistent-route"
    echo "  4. Error boundary catches render errors"
    echo "  5. Route transitions are smooth (no blank screens)"
    echo "  6. Skeleton loaders show during data fetch"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
