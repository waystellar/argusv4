#!/bin/bash
#
# UI Smoke Test for AdminLogin Page (UI-17)
#
# Verifies the admin login page uses design system tokens,
# has no legacy color signals, and key form elements are present.
#
# Checks:
# 1. AdminLogin.tsx exists
# 2. No legacy color tokens (gray-*, blue-*, red-*, purple-*, gradient, primary-*)
# 3. Design system tokens present (neutral-*, accent-*, status-*, ds-*)
# 4. Form elements present (input, label, button, error state)
# 5. Accessibility attributes present (role, focus rings, htmlFor/id)
# 6. Loading and disabled states present
#
# Usage:
#   ./scripts/ui_smoke_admin_login.sh

set -e

echo "=========================================="
echo "  UI Smoke Test: AdminLogin (UI-17)"
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
ADMIN_LOGIN="${WEB_DIR}/src/pages/admin/AdminLogin.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: AdminLogin.tsx Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${ADMIN_LOGIN}" ]; then
    pass "AdminLogin.tsx exists"
else
    fail "AdminLogin.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-gray-" "text-gray-" "border-gray-" "bg-blue-" "text-blue-" "border-blue-" "bg-red-" "text-red-" "border-red-" "bg-purple-" "from-blue-" "to-purple-" "bg-gradient" "primary-" "hover:scale"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${ADMIN_LOGIN}" 2>/dev/null; then
        fail "Legacy token '${pattern}' found in AdminLogin.tsx"
    else
        pass "No '${pattern}' legacy tokens"
    fi
done

# Check for non-ds text sizing
CHECK=$((CHECK + 1))
if grep -E '\btext-xs\b|\btext-sm\b|\btext-2xl\b' "${ADMIN_LOGIN}" > /dev/null 2>&1; then
    fail "Non-ds text sizing found"
else
    pass "No non-ds text sizing tokens"
fi

# Check for non-ds spacing
CHECK=$((CHECK + 1))
if grep -E '\bmb-[0-9]+\b|\bmt-[0-9]+\b|\bp-[0-9]+\b' "${ADMIN_LOGIN}" > /dev/null 2>&1; then
    fail "Non-ds spacing tokens found"
else
    pass "No non-ds spacing tokens"
fi

# --- Check 3: Design system tokens present ---
echo ""
echo "--- Check 3: Design System Tokens ---"

CHECK=$((CHECK + 1))
if grep -q "bg-neutral-950" "${ADMIN_LOGIN}"; then
    pass "Page background uses neutral-950"
else
    fail "Page background not using neutral-950"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-neutral-900" "${ADMIN_LOGIN}"; then
    pass "Form card uses neutral-900"
else
    fail "Form card not using neutral-900"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-accent-600" "${ADMIN_LOGIN}"; then
    pass "Primary button uses accent-600"
else
    fail "Primary button not using accent-600"
fi

CHECK=$((CHECK + 1))
if grep -q "text-status-error" "${ADMIN_LOGIN}"; then
    pass "Error state uses status-error"
else
    fail "Error state not using status-error"
fi

CHECK=$((CHECK + 1))
if grep -q "text-ds-" "${ADMIN_LOGIN}"; then
    pass "Typography tokens present (text-ds-*)"
else
    fail "No typography tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "px-ds-\|py-ds-\|p-ds-\|mb-ds-\|mt-ds-\|gap-ds-" "${ADMIN_LOGIN}"; then
    pass "Spacing tokens present (*-ds-*)"
else
    fail "No spacing tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "rounded-ds-" "${ADMIN_LOGIN}"; then
    pass "Radius tokens present (rounded-ds-*)"
else
    fail "No radius tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "shadow-ds-" "${ADMIN_LOGIN}"; then
    pass "Shadow tokens present (shadow-ds-*)"
else
    warn "No shadow tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "duration-ds-" "${ADMIN_LOGIN}"; then
    pass "Transition tokens present (duration-ds-*)"
else
    warn "No transition tokens found"
fi

# --- Check 4: Form elements ---
echo ""
echo "--- Check 4: Form Elements ---"

CHECK=$((CHECK + 1))
if grep -q '<form' "${ADMIN_LOGIN}"; then
    pass "Form element present"
else
    fail "No form element found"
fi

CHECK=$((CHECK + 1))
if grep -q '<input' "${ADMIN_LOGIN}"; then
    pass "Input element present"
else
    fail "No input element found"
fi

CHECK=$((CHECK + 1))
if grep -q '<label' "${ADMIN_LOGIN}"; then
    pass "Label element present"
else
    fail "No label element found"
fi

CHECK=$((CHECK + 1))
if grep -q 'type="submit"' "${ADMIN_LOGIN}"; then
    pass "Submit button present"
else
    fail "No submit button found"
fi

CHECK=$((CHECK + 1))
if grep -q 'placeholder=' "${ADMIN_LOGIN}"; then
    pass "Input placeholder present"
else
    warn "No input placeholder found"
fi

# --- Check 5: Accessibility ---
echo ""
echo "--- Check 5: Accessibility ---"

CHECK=$((CHECK + 1))
if grep -q 'htmlFor="password"' "${ADMIN_LOGIN}"; then
    pass "Label htmlFor attribute present"
else
    fail "Label htmlFor missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'id="password"' "${ADMIN_LOGIN}"; then
    pass "Input id matches label htmlFor"
else
    fail "Input id missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'role="alert"' "${ADMIN_LOGIN}"; then
    pass "Error message has role=alert"
else
    warn "Error message missing role=alert"
fi

CHECK=$((CHECK + 1))
if grep -q 'focus:ring-' "${ADMIN_LOGIN}"; then
    pass "Focus ring styles present"
else
    fail "No focus ring styles found"
fi

# --- Check 6: Loading and disabled states ---
echo ""
echo "--- Check 6: Loading & Disabled States ---"

CHECK=$((CHECK + 1))
if grep -q 'disabled=' "${ADMIN_LOGIN}"; then
    pass "Disabled state present on submit button"
else
    fail "No disabled state found"
fi

CHECK=$((CHECK + 1))
if grep -q 'disabled:bg-neutral-' "${ADMIN_LOGIN}"; then
    pass "Disabled styling uses neutral token"
else
    fail "Disabled styling not using neutral token"
fi

CHECK=$((CHECK + 1))
if grep -q 'animate-spin' "${ADMIN_LOGIN}"; then
    pass "Loading spinner present"
else
    fail "No loading spinner found"
fi

CHECK=$((CHECK + 1))
if grep -q 'isLoading' "${ADMIN_LOGIN}"; then
    pass "Loading state management present"
else
    fail "No loading state management"
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
    echo "  [ ] Page centered with neutral-950 background"
    echo "  [ ] Lock icon in accent-600 rounded box"
    echo "  [ ] Title 'Argus Admin' in ds-title"
    echo "  [ ] Helper text 'Sign in to manage your events'"
    echo "  [ ] Form card with neutral-900 bg and neutral-700 border"
    echo "  [ ] Password input with neutral-950 bg and accent focus ring"
    echo "  [ ] Sign In button accent-600, disabled state neutral-700"
    echo "  [ ] Error state shows red status-error banner with icon"
    echo "  [ ] Loading state shows spinner in button"
    echo "  [ ] 'Back to Home' link at bottom"
    echo "  [ ] Mobile: form fills width with padding"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
