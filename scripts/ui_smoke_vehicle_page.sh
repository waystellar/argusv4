#!/bin/bash
#
# UI Smoke Test for VehiclePage (UI-16, UI-25)
#
# Verifies the vehicle detail page uses design system tokens,
# has no legacy color signals, and key components are wired up.
#
# Checks:
# 1. VehiclePage.tsx exists
# 2. No legacy color tokens (gray-*, green-*, red-*, yellow-*, primary-*, bg-surface, glass)
# 3. Design system tokens present (neutral-*, status-*, accent-*, ds-*)
# 4. Key components imported (Header, ConnectionStatus, YouTubeEmbed, TelemetryTile, Skeleton)
# 5. Accessibility attributes present
# 6. Stream state indicators migrated (LIVE/Starting/Error/Offline)
#
# Usage:
#   ./scripts/ui_smoke_vehicle_page.sh

set -e

echo "=========================================="
echo "  UI Smoke Test: VehiclePage (UI-16, UI-25)"
echo "=========================================="
echo ""

# Colors for output
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
CHECK=0
WEB_DIR="$(dirname "$0")/../web"
VEHICLE_PAGE="${WEB_DIR}/src/pages/VehiclePage.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: VehiclePage.tsx Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${VEHICLE_PAGE}" ]; then
    pass "VehiclePage.tsx exists"
else
    fail "VehiclePage.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "text-green-" "bg-green-" "bg-gray-" "text-red-" "bg-red-" "text-blue-" "text-yellow-" "bg-yellow-" "primary-" "\"glass\""; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${VEHICLE_PAGE}" 2>/dev/null; then
        fail "Legacy token '${pattern}' found in VehiclePage.tsx"
    else
        pass "No '${pattern}' legacy tokens"
    fi
done

# Also check for non-ds text sizing
CHECK=$((CHECK + 1))
if grep -E '\btext-xs\b|\btext-sm\b|\btext-lg\b|\btext-base\b' "${VEHICLE_PAGE}" > /dev/null 2>&1; then
    fail "Non-ds text sizing (text-xs/text-sm/text-lg/text-base) found"
else
    pass "No non-ds text sizing tokens"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-xl\b|\brounded-md\b' "${VEHICLE_PAGE}" > /dev/null 2>&1; then
    fail "Non-ds radius found"
else
    pass "No non-ds radius"
fi

CHECK=$((CHECK + 1))
if grep -E '\bspace-y-[0-9]' "${VEHICLE_PAGE}" > /dev/null 2>&1; then
    fail "Non-ds space-y found"
else
    pass "No non-ds space-y"
fi

# Check for non-ds gap (integer only, not fractional like gap-1.5)
CHECK=$((CHECK + 1))
if grep -E '\bgap-[0-9]+\b' "${VEHICLE_PAGE}" 2>/dev/null | grep -v 'gap-[0-9]\.' > /dev/null 2>&1; then
    fail "Non-ds gap found (gap-N)"
else
    pass "No non-ds gap"
fi

# --- Check 3: Design system tokens present ---
echo ""
echo "--- Check 3: Design System Tokens ---"

CHECK=$((CHECK + 1))
if grep -q "bg-neutral-" "${VEHICLE_PAGE}"; then
    pass "Neutral background tokens present"
else
    fail "No neutral background tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-neutral-" "${VEHICLE_PAGE}"; then
    pass "Neutral text tokens present"
else
    fail "No neutral text tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "border-neutral-" "${VEHICLE_PAGE}"; then
    pass "Neutral border tokens present"
else
    fail "No neutral border tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-status-success" "${VEHICLE_PAGE}"; then
    pass "Status success token present"
else
    fail "No status-success token found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-status-warning" "${VEHICLE_PAGE}"; then
    pass "Status warning token present"
else
    fail "No status-warning token found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-status-error\|bg-status-error" "${VEHICLE_PAGE}"; then
    pass "Status error token present"
else
    fail "No status-error token found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-accent-\|bg-accent-" "${VEHICLE_PAGE}"; then
    pass "Accent tokens present"
else
    fail "No accent tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-ds-" "${VEHICLE_PAGE}"; then
    pass "Typography tokens present (text-ds-*)"
else
    fail "No typography tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "px-ds-\|py-ds-\|p-ds-\|gap-ds-\|mt-ds-\|mb-ds-" "${VEHICLE_PAGE}"; then
    pass "Spacing tokens present (*-ds-*)"
else
    fail "No spacing tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "rounded-ds-" "${VEHICLE_PAGE}"; then
    pass "Radius tokens present (rounded-ds-*)"
else
    fail "No radius tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "duration-ds-" "${VEHICLE_PAGE}"; then
    pass "Transition tokens present (duration-ds-*)"
else
    warn "No transition tokens found"
fi

# --- Check 4: Key component imports ---
echo ""
echo "--- Check 4: Key Component Imports ---"

for component in "Header" "ConnectionStatus" "YouTubeEmbed" "TelemetryTile" "Skeleton"; do
    CHECK=$((CHECK + 1))
    if grep -q "import.*${component}" "${VEHICLE_PAGE}"; then
        pass "${component} imported"
    else
        fail "${component} not imported"
    fi
done

# --- Check 5: Accessibility ---
echo ""
echo "--- Check 5: Accessibility ---"

CHECK=$((CHECK + 1))
if grep -q 'aria-label' "${VEHICLE_PAGE}"; then
    pass "aria-label attributes present"
else
    warn "No aria-label attributes found"
fi

CHECK=$((CHECK + 1))
if grep -q 'focus:ring-' "${VEHICLE_PAGE}"; then
    pass "Focus ring styles present"
else
    warn "No focus ring styles found"
fi

# --- Check 6: Stream state indicators ---
echo ""
echo "--- Check 6: Stream State Indicators ---"

CHECK=$((CHECK + 1))
if grep -q "bg-status-error/80" "${VEHICLE_PAGE}"; then
    pass "LIVE indicator uses status-error token"
else
    fail "LIVE indicator missing status-error token"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-status-warning/80" "${VEHICLE_PAGE}"; then
    pass "Starting indicator uses status-warning token"
else
    fail "Starting indicator missing status-warning token"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-neutral-700/80" "${VEHICLE_PAGE}"; then
    pass "Offline indicator uses neutral token"
else
    fail "Offline indicator missing neutral token"
fi

# Summary
echo ""
echo "=========================================="
echo "  Summary: ${CHECK} checks run"
echo "=========================================="
if [ "$FAILED" = "0" ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "Manual verification checklist:"
    echo "  [ ] Vehicle header shows #number + team name"
    echo "  [ ] Stream status pill (LIVE/Starting/Error/Offline) visible"
    echo "  [ ] Camera switcher buttons use accent-600 for active"
    echo "  [ ] Position badge shows P# in accent-400"
    echo "  [ ] Telemetry tiles render with ds spacing"
    echo "  [ ] Section headings use neutral-400 + ds-caption"
    echo "  [ ] Share button has focus ring and hover state"
    echo "  [ ] No-telemetry message uses neutral card"
    echo "  [ ] Wake lock indicator uses status-success green"
    echo "  [ ] Mobile scrollable, 1440px usable"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
