#!/bin/bash
#
# UI Smoke Test for Migrated Offender Components (UI-14)
#
# Checks that StatusPill, SystemHealthIndicator, and DiagnosticsModal
# have been migrated to design system tokens and have no legacy signals.
#
# Usage:
#   ./scripts/ui_smoke_components_offenders.sh [frontend_url]
#
# Default URL: http://localhost:5173

set -e

FRONTEND_URL="${1:-http://localhost:5173}"
SHOWCASE_PATH="/dev/components"
FULL_URL="${FRONTEND_URL}${SHOWCASE_PATH}"

echo "=========================================="
echo "  UI Smoke Test: Migrated Components (UI-14)"
echo "=========================================="
echo ""
echo "Target Showcase URL: ${FULL_URL}"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Check 2: Component Showcase page is reachable
echo ""
echo "--- Check 2: Component Showcase Page ---"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${FULL_URL}" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    pass "Component Showcase returns HTTP 200"
else
    warn "Component Showcase returned HTTP ${HTTP_STATUS} (SPA routing may differ)"
fi

# Resolve web directory
WEB_DIR="$(dirname "$0")/../web"

# Check 3: StatusPill.tsx — zero legacy signals
echo ""
echo "--- Check 3: StatusPill.tsx Design System Compliance ---"
STATUS_PILL="${WEB_DIR}/src/components/common/StatusPill.tsx"

if [ -f "${STATUS_PILL}" ]; then
    pass "StatusPill.tsx exists"

    if grep -E "(gray-[0-9]+|bg-surface|primary-[0-9]+|blue-[0-9]+|green-[0-9]+|red-[0-9]+|yellow-[0-9]+)" "${STATUS_PILL}" > /dev/null 2>&1; then
        fail "Legacy tokens found in StatusPill.tsx"
    else
        pass "No legacy tokens in StatusPill.tsx"
    fi

    if grep -q "status-" "${STATUS_PILL}"; then
        pass "StatusPill uses status-* tokens"
    else
        warn "status-* tokens not found in StatusPill.tsx"
    fi

    if grep -q "neutral-" "${STATUS_PILL}"; then
        pass "StatusPill uses neutral-* tokens"
    else
        warn "neutral-* tokens not found in StatusPill.tsx"
    fi

    if grep -q "rounded-ds-" "${STATUS_PILL}"; then
        pass "StatusPill uses rounded-ds-* tokens"
    else
        warn "rounded-ds-* tokens not found"
    fi

    if grep -q "text-ds-" "${STATUS_PILL}"; then
        pass "StatusPill uses text-ds-* typography tokens"
    else
        warn "text-ds-* tokens not found"
    fi
else
    fail "StatusPill.tsx not found"
fi

# Check 4: SystemHealthIndicator.tsx — zero legacy signals
echo ""
echo "--- Check 4: SystemHealthIndicator.tsx Design System Compliance ---"
HEALTH_IND="${WEB_DIR}/src/components/common/SystemHealthIndicator.tsx"

if [ -f "${HEALTH_IND}" ]; then
    pass "SystemHealthIndicator.tsx exists"

    if grep -E "(gray-[0-9]+|bg-surface|primary-[0-9]+|blue-[0-9]+|green-[0-9]+|red-[0-9]+|yellow-[0-9]+)" "${HEALTH_IND}" > /dev/null 2>&1; then
        fail "Legacy tokens found in SystemHealthIndicator.tsx"
    else
        pass "No legacy tokens in SystemHealthIndicator.tsx"
    fi

    if grep -q "status-" "${HEALTH_IND}"; then
        pass "SystemHealthIndicator uses status-* tokens"
    else
        warn "status-* tokens not found"
    fi

    if grep -q "neutral-" "${HEALTH_IND}"; then
        pass "SystemHealthIndicator uses neutral-* tokens"
    else
        warn "neutral-* tokens not found"
    fi

    if grep -q "focus:ring" "${HEALTH_IND}"; then
        pass "Focus ring accessible"
    else
        warn "Focus ring not found"
    fi
else
    fail "SystemHealthIndicator.tsx not found"
fi

# Check 5: DiagnosticsModal.tsx — zero legacy signals
echo ""
echo "--- Check 5: DiagnosticsModal.tsx Design System Compliance ---"
DIAG_MODAL="${WEB_DIR}/src/components/StreamControl/DiagnosticsModal.tsx"

if [ -f "${DIAG_MODAL}" ]; then
    pass "DiagnosticsModal.tsx exists"

    if grep -E "(gray-[0-9]+|bg-surface|primary-[0-9]+|blue-[0-9]+|green-[0-9]+|red-[0-9]+|yellow-[0-9]+)" "${DIAG_MODAL}" > /dev/null 2>&1; then
        fail "Legacy tokens found in DiagnosticsModal.tsx"
    else
        pass "No legacy tokens in DiagnosticsModal.tsx"
    fi

    if grep -q "status-" "${DIAG_MODAL}"; then
        pass "DiagnosticsModal uses status-* tokens"
    else
        warn "status-* tokens not found"
    fi

    if grep -q "neutral-" "${DIAG_MODAL}"; then
        pass "DiagnosticsModal uses neutral-* tokens"
    else
        warn "neutral-* tokens not found"
    fi

    if grep -q "accent-" "${DIAG_MODAL}"; then
        pass "DiagnosticsModal uses accent-* tokens"
    else
        warn "accent-* tokens not found"
    fi

    if grep -q 'role="dialog"' "${DIAG_MODAL}"; then
        pass "DiagnosticsModal has role=dialog (ARIA)"
    else
        warn "role=dialog not found"
    fi

    if grep -q 'aria-modal' "${DIAG_MODAL}"; then
        pass "DiagnosticsModal has aria-modal"
    else
        warn "aria-modal not found"
    fi

    if grep -q 'aria-label' "${DIAG_MODAL}"; then
        pass "Close button has aria-label"
    else
        warn "aria-label not found on close button"
    fi

    if grep -q "focus:ring" "${DIAG_MODAL}"; then
        pass "Focus ring accessible on interactive elements"
    else
        warn "Focus ring not found"
    fi
else
    fail "DiagnosticsModal.tsx not found"
fi

# Check 6: ComponentShowcase has StatusPill section
echo ""
echo "--- Check 6: ComponentShowcase Integration ---"
SHOWCASE="${WEB_DIR}/src/pages/ComponentShowcase.tsx"

if [ -f "${SHOWCASE}" ]; then
    if grep -q "StatusPill" "${SHOWCASE}"; then
        pass "ComponentShowcase includes StatusPill harness"
    else
        warn "StatusPill not found in ComponentShowcase"
    fi
else
    warn "ComponentShowcase.tsx not found"
fi

# Summary
echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
if [ "$FAILED" = "0" ]; then
    echo -e "${GREEN}All critical checks passed!${NC}"
    echo ""
    echo "Component Showcase URL: ${FRONTEND_URL}/dev/components"
    echo ""
    echo "Manual verification checklist:"
    echo "  [ ] StatusPill: All variants render with correct colors"
    echo "  [ ] StatusPill: Pulse animation visible on live/disconnected/reconnecting"
    echo "  [ ] StatusPill: xs/sm/md sizes visually distinct"
    echo "  [ ] SystemHealthIndicator: Collapsed badge shows health %"
    echo "  [ ] SystemHealthIndicator: Expanded panel shows all metrics"
    echo "  [ ] DiagnosticsModal: Opens with overlay backdrop"
    echo "  [ ] DiagnosticsModal: Sections render with neutral backgrounds"
    echo "  [ ] DiagnosticsModal: Focus rings visible on Tab navigation"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
