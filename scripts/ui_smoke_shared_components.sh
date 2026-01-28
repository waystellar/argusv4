#!/bin/bash
#
# UI Smoke Test for Shared Components (UI-20)
#
# Verifies ConfirmModal, Toast, and ThemeToggle use design system tokens,
# have no legacy color signals, and key features are intact.
#
# Checks:
# 1. Files exist
# 2. No legacy color tokens (gray-*, green-*, red-*, yellow-*, blue-*, primary-*, bg-surface)
# 3. Design system tokens present (neutral-*, status-*, accent-*, ds-*)
# 4. Component-specific features intact
# 5. Accessibility attributes present
#
# Usage:
#   ./scripts/ui_smoke_shared_components.sh

set -e

echo "==========================================="
echo "  UI Smoke Test: Shared Components (UI-20)"
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
CONFIRM_MODAL="${WEB_DIR}/src/components/common/ConfirmModal.tsx"
TOAST="${WEB_DIR}/src/components/common/Toast.tsx"
THEME_TOGGLE="${WEB_DIR}/src/components/common/ThemeToggle.tsx"
SHOWCASE="${WEB_DIR}/src/pages/ComponentShowcase.tsx"

# ==========================================
# CONFIRM MODAL
# ==========================================
echo "=========================================="
echo "  ConfirmModal.tsx"
echo "=========================================="

# --- Check 1: File exists ---
echo ""
echo "--- Check 1: File Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${CONFIRM_MODAL}" ]; then
    pass "ConfirmModal.tsx exists"
else
    fail "ConfirmModal.tsx not found"
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "text-green-" "bg-green-" "bg-gray-" "text-red-" "bg-red-" "text-blue-" "text-yellow-" "bg-yellow-" "primary-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${CONFIRM_MODAL}" 2>/dev/null; then
        fail "ConfirmModal: Legacy token '${pattern}' found"
    else
        pass "ConfirmModal: No '${pattern}'"
    fi
done

# Non-ds sizing
CHECK=$((CHECK + 1))
if grep -E '\btext-xs\b|\btext-sm\b|\btext-lg\b|\btext-base\b' "${CONFIRM_MODAL}" > /dev/null 2>&1; then
    fail "ConfirmModal: Non-ds text sizing found"
else
    pass "ConfirmModal: No non-ds text sizing"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-xl\b|\brounded-md\b' "${CONFIRM_MODAL}" > /dev/null 2>&1; then
    fail "ConfirmModal: Non-ds radius found"
else
    pass "ConfirmModal: No non-ds radius"
fi

CHECK=$((CHECK + 1))
if grep -E '\bshadow-lg\b|\bshadow-xl\b|\bshadow-2xl\b' "${CONFIRM_MODAL}" > /dev/null 2>&1; then
    fail "ConfirmModal: Non-ds shadow found"
else
    pass "ConfirmModal: No non-ds shadow"
fi

# --- Check 3: DS tokens present ---
echo ""
echo "--- Check 3: Design System Tokens ---"

for token in "bg-neutral-" "text-neutral-" "border-neutral-" "bg-status-error" "bg-status-warning" "bg-accent-" "text-ds-" "rounded-ds-" "shadow-ds-" "duration-ds-" "p-ds-" "gap-ds-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${token}" "${CONFIRM_MODAL}"; then
        pass "ConfirmModal: Token '${token}' present"
    else
        fail "ConfirmModal: Token '${token}' missing"
    fi
done

# --- Check 4: Features intact ---
echo ""
echo "--- Check 4: Features Intact ---"

CHECK=$((CHECK + 1))
if grep -q "danger.*warning.*info" "${CONFIRM_MODAL}" 2>/dev/null || grep -q "ModalVariant" "${CONFIRM_MODAL}"; then
    pass "ConfirmModal: Three variants defined"
else
    fail "ConfirmModal: Variants missing"
fi

CHECK=$((CHECK + 1))
if grep -q "useConfirmModal" "${CONFIRM_MODAL}"; then
    pass "ConfirmModal: useConfirmModal hook exported"
else
    fail "ConfirmModal: useConfirmModal hook missing"
fi

CHECK=$((CHECK + 1))
if grep -q "aria-modal" "${CONFIRM_MODAL}"; then
    pass "ConfirmModal: aria-modal present"
else
    fail "ConfirmModal: aria-modal missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'role="dialog"' "${CONFIRM_MODAL}"; then
    pass "ConfirmModal: role=dialog present"
else
    fail "ConfirmModal: role=dialog missing"
fi

CHECK=$((CHECK + 1))
if grep -q "Escape" "${CONFIRM_MODAL}"; then
    pass "ConfirmModal: Escape key handler present"
else
    fail "ConfirmModal: Escape key handler missing"
fi

# ==========================================
# TOAST
# ==========================================
echo ""
echo "=========================================="
echo "  Toast.tsx"
echo "=========================================="

# --- Check 1: File exists ---
echo ""
echo "--- Check 1: File Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${TOAST}" ]; then
    pass "Toast.tsx exists"
else
    fail "Toast.tsx not found"
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "text-green-" "bg-green-" "bg-gray-" "text-red-" "bg-red-" "text-blue-" "text-yellow-" "bg-yellow-" "primary-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${TOAST}" 2>/dev/null; then
        fail "Toast: Legacy token '${pattern}' found"
    else
        pass "Toast: No '${pattern}'"
    fi
done

CHECK=$((CHECK + 1))
if grep -E '\btext-xs\b|\btext-sm\b|\btext-lg\b' "${TOAST}" > /dev/null 2>&1; then
    fail "Toast: Non-ds text sizing found"
else
    pass "Toast: No non-ds text sizing"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-xl\b' "${TOAST}" > /dev/null 2>&1; then
    fail "Toast: Non-ds radius found"
else
    pass "Toast: No non-ds radius"
fi

# --- Check 3: DS tokens present ---
echo ""
echo "--- Check 3: Design System Tokens ---"

for token in "bg-status-success" "bg-status-error" "bg-status-warning" "bg-status-info" "text-status-success" "text-status-error" "text-status-warning" "text-status-info" "text-neutral-" "text-ds-" "rounded-ds-" "gap-ds-" "p-ds-" "duration-ds-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${token}" "${TOAST}"; then
        pass "Toast: Token '${token}' present"
    else
        fail "Toast: Token '${token}' missing"
    fi
done

# --- Check 4: Features intact ---
echo ""
echo "--- Check 4: Features Intact ---"

CHECK=$((CHECK + 1))
if grep -q 'role="alert"' "${TOAST}"; then
    pass "Toast: role=alert present"
else
    fail "Toast: role=alert missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'aria-live' "${TOAST}"; then
    pass "Toast: aria-live present"
else
    fail "Toast: aria-live missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'aria-label="Dismiss"' "${TOAST}"; then
    pass "Toast: dismiss aria-label present"
else
    fail "Toast: dismiss aria-label missing"
fi

CHECK=$((CHECK + 1))
if grep -q "ToastContainer" "${TOAST}"; then
    pass "Toast: ToastContainer exported"
else
    fail "Toast: ToastContainer missing"
fi

CHECK=$((CHECK + 1))
if grep -q "toast.action" "${TOAST}"; then
    pass "Toast: Action button support present"
else
    fail "Toast: Action button support missing"
fi

# ==========================================
# THEME TOGGLE
# ==========================================
echo ""
echo "=========================================="
echo "  ThemeToggle.tsx"
echo "=========================================="

# --- Check 1: File exists ---
echo ""
echo "--- Check 1: File Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${THEME_TOGGLE}" ]; then
    pass "ThemeToggle.tsx exists"
else
    fail "ThemeToggle.tsx not found"
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "bg-gray-" "text-yellow-" "bg-yellow-" "primary-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${THEME_TOGGLE}" 2>/dev/null; then
        fail "ThemeToggle: Legacy token '${pattern}' found"
    else
        pass "ThemeToggle: No '${pattern}'"
    fi
done

CHECK=$((CHECK + 1))
if grep -E '\btext-xs\b|\btext-sm\b|\btext-base\b' "${THEME_TOGGLE}" > /dev/null 2>&1; then
    fail "ThemeToggle: Non-ds text sizing found"
else
    pass "ThemeToggle: No non-ds text sizing"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-md\b' "${THEME_TOGGLE}" > /dev/null 2>&1; then
    fail "ThemeToggle: Non-ds radius found"
else
    pass "ThemeToggle: No non-ds radius"
fi

# --- Check 3: DS tokens present ---
echo ""
echo "--- Check 3: Design System Tokens ---"

for token in "bg-neutral-" "text-neutral-" "border-neutral-" "bg-status-warning" "bg-accent-600" "text-ds-" "rounded-ds-" "gap-ds-" "duration-ds-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${token}" "${THEME_TOGGLE}"; then
        pass "ThemeToggle: Token '${token}' present"
    else
        fail "ThemeToggle: Token '${token}' missing"
    fi
done

# --- Check 4: Features intact ---
echo ""
echo "--- Check 4: Features Intact ---"

CHECK=$((CHECK + 1))
if grep -q "aria-label" "${THEME_TOGGLE}"; then
    pass "ThemeToggle: aria-label present"
else
    fail "ThemeToggle: aria-label missing"
fi

CHECK=$((CHECK + 1))
if grep -q "aria-pressed" "${THEME_TOGGLE}"; then
    pass "ThemeToggle: aria-pressed present (ThemeSelector)"
else
    fail "ThemeToggle: aria-pressed missing"
fi

CHECK=$((CHECK + 1))
if grep -q "ThemeSelector" "${THEME_TOGGLE}"; then
    pass "ThemeToggle: ThemeSelector exported"
else
    fail "ThemeToggle: ThemeSelector missing"
fi

CHECK=$((CHECK + 1))
if grep -q "sunlight" "${THEME_TOGGLE}"; then
    pass "ThemeToggle: Sunlight mode support present"
else
    fail "ThemeToggle: Sunlight mode missing"
fi

CHECK=$((CHECK + 1))
if grep -q "'dark'" "${THEME_TOGGLE}"; then
    pass "ThemeToggle: Dark mode support present"
else
    fail "ThemeToggle: Dark mode missing"
fi

CHECK=$((CHECK + 1))
if grep -q "'system'" "${THEME_TOGGLE}"; then
    pass "ThemeToggle: System/Auto mode present"
else
    fail "ThemeToggle: System/Auto mode missing"
fi

# ==========================================
# COMPONENT SHOWCASE INTEGRATION
# ==========================================
echo ""
echo "=========================================="
echo "  ComponentShowcase Integration"
echo "=========================================="

CHECK=$((CHECK + 1))
if grep -q "import ConfirmModal" "${SHOWCASE}"; then
    pass "Showcase: ConfirmModal imported"
else
    fail "Showcase: ConfirmModal not imported"
fi

CHECK=$((CHECK + 1))
if grep -q "import.*Toast" "${SHOWCASE}"; then
    pass "Showcase: Toast imported"
else
    fail "Showcase: Toast not imported"
fi

CHECK=$((CHECK + 1))
if grep -q "import ThemeToggle" "${SHOWCASE}"; then
    pass "Showcase: ThemeToggle imported"
else
    fail "Showcase: ThemeToggle not imported"
fi

CHECK=$((CHECK + 1))
if grep -q "ThemeSelector" "${SHOWCASE}"; then
    pass "Showcase: ThemeSelector rendered"
else
    fail "Showcase: ThemeSelector not rendered"
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
    echo "  [ ] ConfirmModal danger variant shows red confirm button"
    echo "  [ ] ConfirmModal warning variant shows amber confirm button"
    echo "  [ ] ConfirmModal info variant shows accent confirm button"
    echo "  [ ] ConfirmModal loading state shows spinner"
    echo "  [ ] ConfirmModal closes on Escape key and backdrop click"
    echo "  [ ] Toast success/error/warning/info have distinct colors"
    echo "  [ ] Toast dismiss X button is 44px touch target"
    echo "  [ ] Toast action button renders and is clickable"
    echo "  [ ] ThemeToggle switches between sun/moon icons"
    echo "  [ ] ThemeToggle sunlight state uses warm amber bg"
    echo "  [ ] ThemeSelector shows all 3 options (Dark/Sunlight/Auto)"
    echo "  [ ] ThemeSelector active option uses accent-600 bg"
    echo "  [ ] All components visible in /dev/components showcase"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
