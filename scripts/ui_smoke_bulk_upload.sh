#!/bin/bash
#
# UI Smoke Test for VehicleBulkUpload (UI-27)
#
# Verifies VehicleBulkUpload.tsx uses design system tokens,
# has no legacy color/sizing signals, and key features are intact.
#
# Checks:
# 1. File exists
# 2. No legacy color tokens (gray-*, green-*, red-*, yellow-*, blue-*, primary-*)
# 3. No legacy sizing tokens (text-sm, text-xs, text-lg, text-2xl, rounded-lg, rounded-xl, space-y-*)
# 4. Design system tokens present
# 5. Component features intact (upload, drag/drop, download, auth)
# 6. No hardcoded hex colors
#
# Usage:
#   ./scripts/ui_smoke_bulk_upload.sh

set -e

echo "==========================================="
echo "  UI Smoke Test: VehicleBulkUpload (UI-27)"
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
BU="${WEB_DIR}/src/components/admin/VehicleBulkUpload.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: File Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${BU}" ]; then
    pass "VehicleBulkUpload.tsx exists"
else
    fail "VehicleBulkUpload.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "text-gray-" "border-gray-" "bg-gray-" "hover:bg-gray-" "hover:border-gray-" "text-green-" "bg-green-" "border-green-" "hover:bg-green-" "text-red-" "bg-red-" "border-red-" "text-yellow-" "bg-yellow-" "border-yellow-" "text-blue-" "bg-blue-" "hover:bg-blue-" "hover:text-blue-" "primary-[0-9]" "bg-surface"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${BU}" 2>/dev/null; then
        fail "Legacy token '${pattern}' found"
    else
        pass "No '${pattern}'"
    fi
done

# --- Check 3: No legacy sizing tokens ---
echo ""
echo "--- Check 3: No Legacy Sizing Tokens ---"

CHECK=$((CHECK + 1))
if grep -E '\btext-sm\b|\btext-xs\b|\btext-lg\b|\btext-base\b' "${BU}" > /dev/null 2>&1; then
    fail "Non-ds text sizing found"
else
    pass "No non-ds text sizing"
fi

CHECK=$((CHECK + 1))
if grep -E '\btext-2xl\b|\btext-3xl\b' "${BU}" > /dev/null 2>&1; then
    fail "Non-ds heading size found (text-2xl/3xl)"
else
    pass "No non-ds heading sizes"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-xl\b|\brounded-md\b' "${BU}" > /dev/null 2>&1; then
    fail "Non-ds radius found"
else
    pass "No non-ds radius"
fi

CHECK=$((CHECK + 1))
if grep -E '\bspace-y-[0-9]' "${BU}" > /dev/null 2>&1; then
    fail "Non-ds space-y found"
else
    pass "No non-ds space-y"
fi

CHECK=$((CHECK + 1))
if grep -E '\bgap-[0-9]+\b' "${BU}" 2>/dev/null | grep -v 'gap-[0-9]\.' > /dev/null 2>&1; then
    fail "Non-ds gap found (gap-N)"
else
    pass "No non-ds gap"
fi

CHECK=$((CHECK + 1))
if grep -E '\bpx-[0-9]+\b' "${BU}" 2>/dev/null | grep -v 'px-ds-' > /dev/null 2>&1; then
    fail "Non-ds px found"
else
    pass "No non-ds px"
fi

CHECK=$((CHECK + 1))
if grep -E '\bpy-[0-9]+\b' "${BU}" 2>/dev/null | grep -v 'py-ds-' | grep -v 'py-[0-9]\.' > /dev/null 2>&1; then
    fail "Non-ds py found (integer)"
else
    pass "No non-ds py (integer)"
fi

CHECK=$((CHECK + 1))
if grep -E '\bp-[0-9]+\b' "${BU}" 2>/dev/null | grep -v 'p-ds-' > /dev/null 2>&1; then
    fail "Non-ds p found"
else
    pass "No non-ds p"
fi

CHECK=$((CHECK + 1))
if grep -E '\bmt-[0-9]+\b' "${BU}" 2>/dev/null | grep -v 'mt-ds-' | grep -v 'mt-[0-9]\.' > /dev/null 2>&1; then
    fail "Non-ds mt found"
else
    pass "No non-ds mt"
fi

CHECK=$((CHECK + 1))
if grep -E '\bmb-[0-9]+\b' "${BU}" 2>/dev/null | grep -v 'mb-ds-' | grep -v 'mb-[0-9]\.' > /dev/null 2>&1; then
    fail "Non-ds mb found"
else
    pass "No non-ds mb"
fi

# --- Check 4: Design system tokens present ---
echo ""
echo "--- Check 4: Design System Tokens ---"

for token in "bg-neutral-900" "bg-neutral-800" "text-neutral-50" "text-neutral-400" "text-neutral-300" "text-neutral-500" "border-neutral-800" "border-neutral-700" "hover:bg-neutral-700" "hover:border-neutral-600" "bg-status-success" "bg-status-warning" "bg-status-error" "text-status-success" "text-status-warning" "text-status-error" "bg-accent-600" "text-accent-400" "hover:text-accent-300" "border-accent-500" "text-ds-heading" "text-ds-title" "text-ds-body-sm" "text-ds-caption" "rounded-ds-lg" "rounded-ds-md" "rounded-ds-sm" "px-ds-" "py-ds-" "p-ds-" "gap-ds-" "mt-ds-" "mb-ds-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${token}" "${BU}"; then
        pass "Token '${token}' present"
    else
        fail "Token '${token}' missing"
    fi
done

# --- Check 5: Component features intact ---
echo ""
echo "--- Check 5: Component Features ---"

CHECK=$((CHECK + 1))
if grep -q "getAdminHeaders" "${BU}"; then
    pass "Admin auth headers present"
else
    fail "Admin auth headers missing"
fi

CHECK=$((CHECK + 1))
if grep -q "handleFileSelect" "${BU}"; then
    pass "File select handler present"
else
    fail "File select handler missing"
fi

CHECK=$((CHECK + 1))
if grep -q "handleDragOver" "${BU}"; then
    pass "Drag over handler present"
else
    fail "Drag over handler missing"
fi

CHECK=$((CHECK + 1))
if grep -q "handleDrop" "${BU}"; then
    pass "Drop handler present"
else
    fail "Drop handler missing"
fi

CHECK=$((CHECK + 1))
if grep -q "handleUpload" "${BU}"; then
    pass "Upload handler present"
else
    fail "Upload handler missing"
fi

CHECK=$((CHECK + 1))
if grep -q "downloadTokens" "${BU}"; then
    pass "Token download present"
else
    fail "Token download missing"
fi

CHECK=$((CHECK + 1))
if grep -q "downloadTemplate" "${BU}"; then
    pass "Template download present"
else
    fail "Template download missing"
fi

CHECK=$((CHECK + 1))
if grep -q "uploadMutation" "${BU}"; then
    pass "Upload mutation present"
else
    fail "Upload mutation missing"
fi

CHECK=$((CHECK + 1))
if grep -q "isPending" "${BU}"; then
    pass "Loading state check present"
else
    fail "Loading state check missing"
fi

CHECK=$((CHECK + 1))
if grep -q "isError" "${BU}"; then
    pass "Error state check present"
else
    fail "Error state check missing"
fi

CHECK=$((CHECK + 1))
if grep -q "Import Complete" "${BU}"; then
    pass "Result display present"
else
    fail "Result display missing"
fi

CHECK=$((CHECK + 1))
if grep -q "Import More Vehicles" "${BU}"; then
    pass "Reset button present"
else
    fail "Reset button missing"
fi

CHECK=$((CHECK + 1))
if grep -q "CSV Format" "${BU}"; then
    pass "CSV format help present"
else
    fail "CSV format help missing"
fi

CHECK=$((CHECK + 1))
if grep -q "flex flex-col gap-ds-" "${BU}"; then
    pass "DS flex gap layout used (replaces space-y)"
else
    fail "DS flex gap layout missing"
fi

# --- Check 6: No hardcoded hex colors ---
echo ""
echo "--- Check 6: No Hardcoded Hex Colors ---"

CHECK=$((CHECK + 1))
if grep -E '#[0-9a-fA-F]{3,8}' "${BU}" > /dev/null 2>&1; then
    fail "Hardcoded hex color found"
else
    pass "No hardcoded hex colors"
fi

# Summary
echo ""
echo "==========================================="
echo "  Summary: ${CHECK} checks run"
echo "==========================================="
if [ "$FAILED" = "0" ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "Manual verification checklist:"
    echo "  [ ] Upload card shows heading with 📥 icon and close button"
    echo "  [ ] Drag zone has dashed border, changes color on drag"
    echo "  [ ] File selected state shows green border + 'Ready to upload'"
    echo "  [ ] Download Template link in accent color"
    echo "  [ ] Upload & Import button green when file selected, gray when not"
    echo "  [ ] Spinner animation during upload"
    echo "  [ ] Result card shows Added/Skipped/Errors stats"
    echo "  [ ] Download Tokens button in accent color after success"
    echo "  [ ] Error list in red/error styling"
    echo "  [ ] 'Import More Vehicles' reset button visible after result"
    echo "  [ ] CSV Format help section with code sample"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
