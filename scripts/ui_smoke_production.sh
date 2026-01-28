#!/bin/bash
#
# UI Smoke Test for ProductionEventPicker (UI-24)
#
# Verifies ProductionEventPicker.tsx uses design system tokens,
# has no legacy color/sizing signals, and key features are intact.
#
# Checks:
# 1. File exists
# 2. No legacy color tokens (gray-*, green-*, red-*, yellow-*, blue-*, primary-*, bg-surface)
# 3. No legacy sizing tokens (text-sm, text-xs, rounded-lg, space-y-*, text-2xl)
# 4. No invalid DS tokens (text-ds-headline)
# 5. Design system tokens present
# 6. Component features intact (auth, events, navigation, filter)
# 7. Accessibility attributes present
#
# Usage:
#   ./scripts/ui_smoke_production.sh

set -e

echo "==========================================="
echo "  UI Smoke Test: ProductionEventPicker (UI-24)"
echo "==========================================="
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
PEP="${WEB_DIR}/src/pages/ProductionEventPicker.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: File Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${PEP}" ]; then
    pass "ProductionEventPicker.tsx exists"
else
    fail "ProductionEventPicker.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "bg-gray-" "text-green-" "bg-green-" "text-red-" "bg-red-" "text-blue-" "bg-blue-" "text-yellow-" "bg-yellow-" "primary-[0-9]"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${PEP}" 2>/dev/null; then
        fail "Legacy token '${pattern}' found"
    else
        pass "No '${pattern}'"
    fi
done

CHECK=$((CHECK + 1))
if grep -q "bg-gradient" "${PEP}" 2>/dev/null; then
    fail "Gradient found (bg-gradient-*)"
else
    pass "No gradients"
fi

# --- Check 3: No legacy sizing tokens ---
echo ""
echo "--- Check 3: No Legacy Sizing Tokens ---"

CHECK=$((CHECK + 1))
if grep -E '\btext-sm\b|\btext-xs\b|\btext-lg\b|\btext-base\b' "${PEP}" > /dev/null 2>&1; then
    fail "Non-ds text sizing found"
else
    pass "No non-ds text sizing"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-xl\b|\brounded-md\b' "${PEP}" > /dev/null 2>&1; then
    fail "Non-ds radius found"
else
    pass "No non-ds radius"
fi

CHECK=$((CHECK + 1))
if grep -E '\bspace-y-[0-9]' "${PEP}" > /dev/null 2>&1; then
    fail "Non-ds space-y found"
else
    pass "No non-ds space-y"
fi

CHECK=$((CHECK + 1))
if grep -E '\btext-2xl\b|\btext-3xl\b' "${PEP}" > /dev/null 2>&1; then
    fail "Non-ds heading size found (text-2xl/3xl)"
else
    pass "No non-ds heading sizes"
fi

CHECK=$((CHECK + 1))
if grep -E '\bmt-[1-9][0-9]*\b|\bmb-[1-9][0-9]*\b' "${PEP}" > /dev/null 2>&1; then
    fail "Non-ds margin found (mt-N, mb-N)"
else
    pass "No non-ds margin"
fi

# --- Check 4: No invalid DS tokens ---
echo ""
echo "--- Check 4: No Invalid DS Tokens ---"

CHECK=$((CHECK + 1))
if grep -q "text-ds-headline" "${PEP}" 2>/dev/null; then
    fail "Invalid token 'text-ds-headline' found (should be text-ds-heading)"
else
    pass "No invalid 'text-ds-headline'"
fi

# --- Check 5: Design system tokens present ---
echo ""
echo "--- Check 5: Design System Tokens ---"

for token in "bg-neutral-950" "bg-neutral-900" "bg-neutral-800" "text-neutral-50" "text-neutral-400" "text-neutral-500" "border-neutral-800" "border-neutral-700" "bg-status-error" "border-status-success" "text-status-error" "bg-accent-600" "text-accent-400" "text-ds-title" "text-ds-heading" "text-ds-body-sm" "text-ds-body" "text-ds-caption" "rounded-ds-lg" "rounded-ds-md" "rounded-ds-sm" "px-ds-" "py-ds-" "p-ds-" "gap-ds-" "mt-ds-" "mb-ds-" "duration-ds-fast"; do
    CHECK=$((CHECK + 1))
    if grep -q "${token}" "${PEP}"; then
        pass "Token '${token}' present"
    else
        fail "Token '${token}' missing"
    fi
done

# --- Check 6: Component features intact ---
echo ""
echo "--- Check 6: Component Features ---"

CHECK=$((CHECK + 1))
if grep -q "authState" "${PEP}"; then
    pass "Auth state management present"
else
    fail "Auth state management missing"
fi

CHECK=$((CHECK + 1))
if grep -q "handleLogin" "${PEP}"; then
    pass "Login handler present"
else
    fail "Login handler missing"
fi

CHECK=$((CHECK + 1))
if grep -q "handleSelectEvent" "${PEP}"; then
    pass "Event selection handler present"
else
    fail "Event selection handler missing"
fi

CHECK=$((CHECK + 1))
if grep -q "sortedEvents" "${PEP}"; then
    pass "Event sorting logic present"
else
    fail "Event sorting logic missing"
fi

CHECK=$((CHECK + 1))
if grep -q "StatusPill" "${PEP}"; then
    pass "StatusPill component used"
else
    fail "StatusPill component missing"
fi

CHECK=$((CHECK + 1))
if grep -q "getEventStatusVariant" "${PEP}"; then
    pass "Event status variant helper used"
else
    fail "Event status variant helper missing"
fi

CHECK=$((CHECK + 1))
if grep -q "AppLoading" "${PEP}"; then
    pass "AppLoading component used"
else
    fail "AppLoading component missing"
fi

CHECK=$((CHECK + 1))
if grep -q "Spinner" "${PEP}"; then
    pass "Spinner component used"
else
    fail "Spinner component missing"
fi

CHECK=$((CHECK + 1))
if grep -q "EventCard" "${PEP}"; then
    pass "EventCard sub-component present"
else
    fail "EventCard sub-component missing"
fi

CHECK=$((CHECK + 1))
if grep -q "/production/events/" "${PEP}"; then
    pass "Control Room navigation route present"
else
    fail "Control Room navigation route missing"
fi

CHECK=$((CHECK + 1))
if grep -q "admin_token" "${PEP}"; then
    pass "Admin token auth flow present"
else
    fail "Admin token auth flow missing"
fi

CHECK=$((CHECK + 1))
if grep -q "refetchInterval" "${PEP}"; then
    pass "Auto-refresh interval present"
else
    fail "Auto-refresh interval missing"
fi

# --- Check 7: Accessibility ---
echo ""
echo "--- Check 7: Accessibility ---"

CHECK=$((CHECK + 1))
if grep -q "focus:ring-" "${PEP}"; then
    pass "Focus ring styles present"
else
    warn "No focus ring styles found"
fi

CHECK=$((CHECK + 1))
if grep -q "autoFocus" "${PEP}"; then
    pass "Auto-focus on login input present"
else
    warn "No auto-focus on login input"
fi

CHECK=$((CHECK + 1))
if grep -q "placeholder" "${PEP}"; then
    pass "Input placeholders present"
else
    fail "Input placeholders missing"
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
    echo "  [ ] Login screen shows camera icon with 'Production Control' title"
    echo "  [ ] Error messages show red alert with icon"
    echo "  [ ] Login input has focus ring on focus"
    echo "  [ ] Event cards show StatusPill badges (LIVE/UPCOMING/FINISHED)"
    echo "  [ ] LIVE events have green border, UPCOMING neutral, FINISHED dimmed"
    echo "  [ ] Event cards show event name, ID badge, date, laps, distance"
    echo "  [ ] 'Open Control Room' link in accent color on each card"
    echo "  [ ] Empty state shows calendar icon and 'Go to Admin Dashboard' button"
    echo "  [ ] Loading state shows centered Spinner"
    echo "  [ ] Filter tabs visible (All Events, Live Now, Upcoming)"
    echo "  [ ] Logout button in header"
    echo "  [ ] Responsive: cards stack to single column on mobile"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
