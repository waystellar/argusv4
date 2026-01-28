#!/bin/bash
#
# UI Smoke Test for EventCreate Page (UI-18)
#
# Verifies the event creation wizard uses design system tokens,
# has no legacy color signals, and key form elements are wired up.
#
# Checks:
# 1. EventCreate.tsx exists
# 2. No legacy color tokens (gray-*, blue-*, green-*, red-*, yellow-*, purple-*, gradient, primary-*)
# 3. Design system tokens present (neutral-*, accent-*, status-*, ds-*)
# 4. Form elements present (input, label, button, textarea, file upload)
# 5. Accessibility attributes present (role, aria-label, focus rings)
# 6. Multi-step wizard structure (step state, progress bar, navigation)
#
# Usage:
#   ./scripts/ui_smoke_event_create.sh

set -e

echo "=========================================="
echo "  UI Smoke Test: EventCreate (UI-18)"
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
EVENT_CREATE="${WEB_DIR}/src/pages/admin/EventCreate.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: EventCreate.tsx Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${EVENT_CREATE}" ]; then
    pass "EventCreate.tsx exists"
else
    fail "EventCreate.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-gray-" "text-gray-" "border-gray-" "bg-blue-" "text-blue-" "border-blue-" "bg-red-" "text-red-" "border-red-" "bg-green-" "text-green-" "border-green-" "bg-yellow-" "text-yellow-" "bg-purple-" "text-purple-" "from-blue-" "to-purple-" "bg-gradient" "primary-" "hover:scale"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${EVENT_CREATE}" 2>/dev/null; then
        fail "Legacy token '${pattern}' found in EventCreate.tsx"
    else
        pass "No '${pattern}' legacy tokens"
    fi
done

# Check for non-ds text sizing
CHECK=$((CHECK + 1))
if grep -E '\btext-xs\b|\btext-sm\b|\btext-2xl\b|\btext-xl\b' "${EVENT_CREATE}" > /dev/null 2>&1; then
    fail "Non-ds text sizing found"
else
    pass "No non-ds text sizing tokens"
fi

# Check for non-ds spacing
CHECK=$((CHECK + 1))
if grep -E '\bmb-[0-9]+\b|\bmt-[0-9]+\b|\bp-[0-9]+\b|\bgap-[0-9]+\b' "${EVENT_CREATE}" > /dev/null 2>&1; then
    fail "Non-ds spacing tokens found"
else
    pass "No non-ds spacing tokens"
fi

# Check for emoji icons (should use SVGs)
CHECK=$((CHECK + 1))
if grep -q '✅\|📍\|❌\|⚠️\|🏁' "${EVENT_CREATE}" 2>/dev/null; then
    fail "Emoji icons found (should use SVG)"
else
    pass "No emoji icons (using SVGs)"
fi

# --- Check 3: Design system tokens present ---
echo ""
echo "--- Check 3: Design System Tokens ---"

CHECK=$((CHECK + 1))
if grep -q "bg-neutral-950" "${EVENT_CREATE}"; then
    pass "Page background uses neutral-950"
else
    fail "Page background not using neutral-950"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-neutral-900" "${EVENT_CREATE}"; then
    pass "Form card uses neutral-900"
else
    fail "Form card not using neutral-900"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-neutral-800" "${EVENT_CREATE}"; then
    pass "Input background uses neutral-800"
else
    fail "Input background not using neutral-800"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-accent-600" "${EVENT_CREATE}"; then
    pass "Primary button uses accent-600"
else
    fail "Primary button not using accent-600"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-accent-500" "${EVENT_CREATE}"; then
    pass "Progress bar uses accent-500"
else
    fail "Progress bar not using accent-500"
fi

CHECK=$((CHECK + 1))
if grep -q "text-status-error" "${EVENT_CREATE}"; then
    pass "Error state uses status-error"
else
    fail "Error state not using status-error"
fi

CHECK=$((CHECK + 1))
if grep -q "text-status-warning" "${EVENT_CREATE}"; then
    pass "Warning state uses status-warning"
else
    fail "Warning state not using status-warning"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-status-success" "${EVENT_CREATE}"; then
    pass "Create button / file upload uses status-success"
else
    fail "No status-success token found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-ds-" "${EVENT_CREATE}"; then
    pass "Typography tokens present (text-ds-*)"
else
    fail "No typography tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "px-ds-\|py-ds-\|p-ds-\|mb-ds-\|mt-ds-\|gap-ds-\|mr-ds-" "${EVENT_CREATE}"; then
    pass "Spacing tokens present (*-ds-*)"
else
    fail "No spacing tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "rounded-ds-" "${EVENT_CREATE}"; then
    pass "Radius tokens present (rounded-ds-*)"
else
    fail "No radius tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "duration-ds-" "${EVENT_CREATE}"; then
    pass "Transition tokens present (duration-ds-*)"
else
    fail "No transition tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "bg-accent-500/10\|border-accent-500/20" "${EVENT_CREATE}"; then
    pass "Summary card uses accent opacity tokens"
else
    fail "Summary card not using accent opacity tokens"
fi

# --- Check 4: Form elements ---
echo ""
echo "--- Check 4: Form Elements ---"

CHECK=$((CHECK + 1))
if grep -q '<input' "${EVENT_CREATE}"; then
    pass "Input elements present"
else
    fail "No input elements found"
fi

CHECK=$((CHECK + 1))
if grep -q '<textarea' "${EVENT_CREATE}"; then
    pass "Textarea element present"
else
    fail "No textarea element found"
fi

CHECK=$((CHECK + 1))
if grep -q '<label' "${EVENT_CREATE}"; then
    pass "Label elements present"
else
    fail "No label elements found"
fi

CHECK=$((CHECK + 1))
if grep -q 'type="file"' "${EVENT_CREATE}"; then
    pass "File upload input present"
else
    fail "No file upload input found"
fi

CHECK=$((CHECK + 1))
if grep -q 'type="number"' "${EVENT_CREATE}"; then
    pass "Number input present"
else
    fail "No number input found"
fi

CHECK=$((CHECK + 1))
if grep -q 'type="datetime-local"' "${EVENT_CREATE}"; then
    pass "Datetime input present"
else
    fail "No datetime input found"
fi

CHECK=$((CHECK + 1))
if grep -q 'placeholder=' "${EVENT_CREATE}"; then
    pass "Input placeholders present"
else
    warn "No input placeholders found"
fi

CHECK=$((CHECK + 1))
if grep -q 'inputClasses' "${EVENT_CREATE}"; then
    pass "Shared inputClasses helper used"
else
    fail "No shared inputClasses helper found"
fi

# --- Check 5: Accessibility ---
echo ""
echo "--- Check 5: Accessibility ---"

CHECK=$((CHECK + 1))
if grep -q 'role="alert"' "${EVENT_CREATE}"; then
    pass "Error messages have role=alert"
else
    fail "Error messages missing role=alert"
fi

CHECK=$((CHECK + 1))
if grep -q 'role="progressbar"' "${EVENT_CREATE}"; then
    pass "Progress bar has role=progressbar"
else
    fail "Progress bar missing role=progressbar"
fi

CHECK=$((CHECK + 1))
if grep -q 'aria-label' "${EVENT_CREATE}"; then
    pass "aria-label attributes present"
else
    fail "No aria-label attributes found"
fi

CHECK=$((CHECK + 1))
if grep -q 'aria-valuenow' "${EVENT_CREATE}"; then
    pass "Progress bar has aria-valuenow"
else
    warn "Progress bar missing aria-valuenow"
fi

CHECK=$((CHECK + 1))
if grep -q 'focus:ring-' "${EVENT_CREATE}"; then
    pass "Focus ring styles present"
else
    fail "No focus ring styles found"
fi

CHECK=$((CHECK + 1))
if grep -q 'focus:outline-none' "${EVENT_CREATE}"; then
    pass "Focus outline reset present"
else
    fail "Focus outline reset not found"
fi

# --- Check 6: Multi-step wizard structure ---
echo ""
echo "--- Check 6: Multi-Step Wizard ---"

CHECK=$((CHECK + 1))
if grep -q 'useState(1)' "${EVENT_CREATE}"; then
    pass "Step state initialized"
else
    fail "No step state found"
fi

CHECK=$((CHECK + 1))
if grep -q 'step === 1' "${EVENT_CREATE}"; then
    pass "Step 1 conditional present"
else
    fail "Step 1 conditional missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'step === 2' "${EVENT_CREATE}"; then
    pass "Step 2 conditional present"
else
    fail "Step 2 conditional missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'step === 3' "${EVENT_CREATE}"; then
    pass "Step 3 conditional present"
else
    fail "Step 3 conditional missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'nextStep\|prevStep' "${EVENT_CREATE}"; then
    pass "Step navigation functions present"
else
    fail "Step navigation missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'validateStep' "${EVENT_CREATE}"; then
    pass "Step validation function present"
else
    fail "Step validation missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'disabled=' "${EVENT_CREATE}"; then
    pass "Disabled state present on submit button"
else
    fail "No disabled state found"
fi

CHECK=$((CHECK + 1))
if grep -q 'disabled:bg-neutral-' "${EVENT_CREATE}"; then
    pass "Disabled styling uses neutral token"
else
    fail "Disabled styling not using neutral token"
fi

CHECK=$((CHECK + 1))
if grep -q 'isPending\|isLoading\|Creating' "${EVENT_CREATE}"; then
    pass "Loading/pending state present"
else
    fail "No loading state found"
fi

CHECK=$((CHECK + 1))
if grep -q 'useMutation' "${EVENT_CREATE}"; then
    pass "React Query mutation used"
else
    fail "No mutation found"
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
    echo "  [ ] Header shows 'Create New Event' with back arrow"
    echo "  [ ] Step indicator shows 'Step N of 3'"
    echo "  [ ] Progress bar fills with accent-500 per step"
    echo "  [ ] Step 1: Event Details form card with neutral-900 bg"
    echo "  [ ] Step 1: Event name with character counter"
    echo "  [ ] Step 1: Description textarea with counter"
    echo "  [ ] Step 1: Date pickers side-by-side on desktop"
    echo "  [ ] Step 2: Race classes grouped by series in cards"
    echo "  [ ] Step 2: Selected classes use accent-600 bg"
    echo "  [ ] Step 2: Unselected classes use neutral-800 bg"
    echo "  [ ] Step 3: File upload drop zone with dashed border"
    echo "  [ ] Step 3: Uploaded file shows green check + name"
    echo "  [ ] Step 3: Summary card with accent tint"
    echo "  [ ] Create button green (status-success), disabled state neutral"
    echo "  [ ] Validation errors show in status-error with role=alert"
    echo "  [ ] Mobile: forms fill width, date fields stack"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
