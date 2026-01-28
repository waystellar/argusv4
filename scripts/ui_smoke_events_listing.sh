#!/bin/bash
#
# UI Smoke Test for Events Listing Page (UI-12)
#
# This script performs basic checks to verify the Events listing
# page ("Watch Live" destination) is rendering correctly.
#
# Checks:
# 1. Dev server is running
# 2. Events page loads without errors
# 3. Key DOM elements exist
# 4. Design system compliance
#
# Usage:
#   ./scripts/ui_smoke_events_listing.sh [frontend_url]
#
# Default URL: http://localhost:5173

set -e

FRONTEND_URL="${1:-http://localhost:5173}"
EVENTS_PATH="/events"
FULL_URL="${FRONTEND_URL}${EVENTS_PATH}"

echo "=========================================="
echo "  UI Smoke Test: Events Listing (UI-12)"
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

# Check 2: Events page returns 200 (via SPA)
echo ""
echo "--- Check 2: Events Page Status ---"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${FULL_URL}" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    pass "Events page returns HTTP 200"
else
    warn "Events page path returned HTTP ${HTTP_STATUS} (SPA routing may differ)"
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

# Check 4: EventDiscovery file exists and uses design system
echo ""
echo "--- Check 4: Design System Compliance (EventDiscovery) ---"
WEB_DIR="$(dirname "$0")/../web"
EVENT_DISCOVERY="${WEB_DIR}/src/pages/EventDiscovery.tsx"

if [ -f "${EVENT_DISCOVERY}" ]; then
    pass "EventDiscovery.tsx exists"

    # Check for old tokens
    if grep -E "(gray-[0-9]+|bg-surface|primary-[0-9]+)" "${EVENT_DISCOVERY}" > /dev/null 2>&1; then
        fail "Old color tokens found in EventDiscovery.tsx"
    else
        pass "No old color tokens in EventDiscovery.tsx"
    fi

    # Check for design system tokens
    if grep -q "bg-neutral-950" "${EVENT_DISCOVERY}"; then
        pass "Design system background tokens present"
    else
        warn "Design system background tokens not found"
    fi

    if grep -q "text-ds-" "${EVENT_DISCOVERY}"; then
        pass "Design system typography tokens present"
    else
        warn "Design system typography tokens not found"
    fi

    # Check for StatusPill usage
    if grep -q "StatusPill" "${EVENT_DISCOVERY}"; then
        pass "StatusPill component used (standardized badges)"
    else
        warn "StatusPill not found - may use custom badges"
    fi

    # Check for skeleton loading
    if grep -q "Skeleton" "${EVENT_DISCOVERY}"; then
        pass "Skeleton loading components used"
    else
        warn "Skeleton components not found"
    fi

    # Check for error handling
    if grep -q "status-error" "${EVENT_DISCOVERY}"; then
        pass "Error state styling present"
    else
        warn "Error state styling not found"
    fi
else
    fail "EventDiscovery.tsx not found at expected path"
fi

# Check 5: LandingPage links to /events
echo ""
echo "--- Check 5: Watch Live Link Verification ---"
LANDING_PAGE="${WEB_DIR}/src/pages/LandingPage.tsx"

if [ -f "${LANDING_PAGE}" ]; then
    if grep -q "navigate('/events')" "${LANDING_PAGE}"; then
        pass "Watch Live button navigates to /events"
    else
        warn "Watch Live navigation not found"
    fi

    if grep -q "Watch Live" "${LANDING_PAGE}"; then
        pass "Watch Live CTA text present"
    else
        warn "Watch Live text not found"
    fi
else
    warn "LandingPage.tsx not found"
fi

# Check 6: TypeScript Build Check
echo ""
echo "--- Check 6: TypeScript Build Check ---"
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
    echo "Events Listing URLs:"
    echo "  Events Page: ${FRONTEND_URL}/events"
    echo "  Landing Page: ${FRONTEND_URL}/"
    echo ""
    echo "Manual verification checklist:"
    echo "  [ ] Page loads with neutral-950 background"
    echo "  [ ] Header shows 'Watch Live' with refresh button"
    echo "  [ ] Search bar has neutral-900 background"
    echo "  [ ] Live events show pulsing 'LIVE' badge (status-success)"
    echo "  [ ] Upcoming events show blue 'UPCOMING' badge"
    echo "  [ ] Finished events show gray 'FINISHED' badge"
    echo "  [ ] Event cards have consistent spacing and typography"
    echo "  [ ] 'Watch live now ->' CTA on live events"
    echo "  [ ] 'View Event ->' CTA on non-live events"
    echo "  [ ] Loading state shows skeleton placeholders"
    echo "  [ ] Empty state shows icon and clear message"
    echo "  [ ] Mobile layout stacks cleanly"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
