#!/bin/bash
#
# UI Smoke Test for EventDetail (UI-26)
#
# Verifies EventDetail.tsx uses design system tokens,
# has no legacy color/sizing signals, and key features are intact.
#
# Checks:
# 1. File exists
# 2. No legacy color tokens
# 3. No legacy sizing tokens (space-y-*, text-sm, text-lg, rounded-lg)
# 4. Design system tokens present
# 5. Component features intact (vehicles, course map, edit modal, pagination)
# 6. Base component usage (Badge, EmptyState, Skeleton)
#
# Usage:
#   ./scripts/ui_smoke_event_detail.sh

set -e

echo "==========================================="
echo "  UI Smoke Test: EventDetail (UI-26)"
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
ED="${WEB_DIR}/src/pages/admin/EventDetail.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: File Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${ED}" ]; then
    pass "EventDetail.tsx exists"
else
    fail "EventDetail.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "bg-gray-" "text-green-" "bg-green-" "text-red-" "bg-red-" "text-blue-" "bg-blue-" "text-yellow-" "bg-yellow-" "primary-[0-9]"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${ED}" 2>/dev/null; then
        fail "Legacy token '${pattern}' found"
    else
        pass "No '${pattern}'"
    fi
done

CHECK=$((CHECK + 1))
if grep -q "bg-gradient" "${ED}" 2>/dev/null; then
    fail "Gradient found (bg-gradient-*)"
else
    pass "No gradients"
fi

# --- Check 3: No legacy sizing tokens ---
echo ""
echo "--- Check 3: No Legacy Sizing Tokens ---"

CHECK=$((CHECK + 1))
if grep -E '\btext-sm\b|\btext-xs\b|\btext-lg\b|\btext-base\b' "${ED}" > /dev/null 2>&1; then
    fail "Non-ds text sizing found"
else
    pass "No non-ds text sizing"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-xl\b' "${ED}" > /dev/null 2>&1; then
    fail "Non-ds radius found"
else
    pass "No non-ds radius"
fi

CHECK=$((CHECK + 1))
if grep -E '\bspace-y-[0-9]' "${ED}" > /dev/null 2>&1; then
    fail "Non-ds space-y found"
else
    pass "No non-ds space-y"
fi

CHECK=$((CHECK + 1))
if grep -E '\btext-2xl\b|\btext-3xl\b' "${ED}" > /dev/null 2>&1; then
    fail "Non-ds heading size found (text-2xl/3xl)"
else
    pass "No non-ds heading sizes"
fi

# --- Check 4: Design system tokens present ---
echo ""
echo "--- Check 4: Design System Tokens ---"

for token in "bg-neutral-900" "bg-neutral-800" "text-neutral-50" "text-neutral-400" "text-neutral-300" "border-neutral-700" "bg-status-success" "bg-status-error" "text-status-error" "text-status-success" "text-status-warning" "bg-accent-500" "text-accent-400" "text-ds-heading" "text-ds-body-sm" "text-ds-caption" "rounded-ds-lg" "rounded-ds-md" "rounded-ds-sm" "px-ds-" "py-ds-" "p-ds-" "gap-ds-" "mt-ds-" "mb-ds-" "ml-ds-" "shadow-ds-overlay"; do
    CHECK=$((CHECK + 1))
    if grep -q "${token}" "${ED}"; then
        pass "Token '${token}' present"
    else
        fail "Token '${token}' missing"
    fi
done

# --- Check 5: Component features intact ---
echo ""
echo "--- Check 5: Component Features ---"

CHECK=$((CHECK + 1))
if grep -q "getAdminHeaders" "${ED}"; then
    pass "Admin auth headers present"
else
    fail "Admin auth headers missing"
fi

CHECK=$((CHECK + 1))
if grep -q "CourseMap" "${ED}"; then
    pass "CourseMap component present"
else
    fail "CourseMap component missing"
fi

CHECK=$((CHECK + 1))
if grep -q "AddVehicleForm" "${ED}"; then
    pass "AddVehicleForm component present"
else
    fail "AddVehicleForm component missing"
fi

CHECK=$((CHECK + 1))
if grep -q "VehicleCard" "${ED}"; then
    pass "VehicleCard component present"
else
    fail "VehicleCard component missing"
fi

CHECK=$((CHECK + 1))
if grep -q "EditEventModal" "${ED}"; then
    pass "EditEventModal component present"
else
    fail "EditEventModal component missing"
fi

CHECK=$((CHECK + 1))
if grep -q "updateStatusMutation" "${ED}"; then
    pass "Status mutation present"
else
    fail "Status mutation missing"
fi

CHECK=$((CHECK + 1))
if grep -q "paginatedVehicles" "${ED}"; then
    pass "Vehicle pagination present"
else
    fail "Vehicle pagination missing"
fi

CHECK=$((CHECK + 1))
if grep -q "exportVehiclesToCSV" "${ED}"; then
    pass "CSV export present"
else
    fail "CSV export missing"
fi

CHECK=$((CHECK + 1))
if grep -q "uploadCourse" "${ED}"; then
    pass "Course upload present"
else
    fail "Course upload missing"
fi

CHECK=$((CHECK + 1))
if grep -q "deleteEvent" "${ED}"; then
    pass "Delete event present"
else
    fail "Delete event missing"
fi

CHECK=$((CHECK + 1))
if grep -q "confirmDialog" "${ED}"; then
    pass "Confirmation dialog present"
else
    fail "Confirmation dialog missing"
fi

CHECK=$((CHECK + 1))
if grep -q "copyToClipboard" "${ED}"; then
    pass "Clipboard copy utility present"
else
    fail "Clipboard copy utility missing"
fi

# --- Check 6: Base component usage ---
echo ""
echo "--- Check 6: Base Component Usage ---"

CHECK=$((CHECK + 1))
if grep -q "import Badge" "${ED}"; then
    pass "Badge component imported"
else
    fail "Badge not imported"
fi

CHECK=$((CHECK + 1))
if grep -q "import EmptyState" "${ED}"; then
    pass "EmptyState component imported"
else
    fail "EmptyState not imported"
fi

CHECK=$((CHECK + 1))
if grep -q "SkeletonVehicleCard" "${ED}"; then
    pass "SkeletonVehicleCard imported"
else
    fail "SkeletonVehicleCard missing"
fi

CHECK=$((CHECK + 1))
if grep -q "flex flex-col gap-ds-" "${ED}"; then
    pass "DS flex gap layout used (replaces space-y)"
else
    fail "DS flex gap layout missing"
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
    echo "  [ ] Event header shows name, location, event ID badge"
    echo "  [ ] Status Badge shows LIVE/UPCOMING/FINISHED with correct variant"
    echo "  [ ] Start Race / End Race buttons in header"
    echo "  [ ] Course map renders with OpenTopoMap tiles"
    echo "  [ ] Upload GPX/KML link visible in map panel"
    echo "  [ ] Event Details grid shows start/end/classes/max vehicles"
    echo "  [ ] Vehicle list with pagination controls"
    echo "  [ ] Add Vehicle form with validation"
    echo "  [ ] Auth token show/copy/regenerate in each VehicleCard"
    echo "  [ ] Quick Links to Fan Portal and Production Director"
    echo "  [ ] Edit Event modal with form fields"
    echo "  [ ] Delete confirmation dialog with danger styling"
    echo "  [ ] Empty state when no vehicles registered"
    echo "  [ ] Responsive: stacks to single column on mobile"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
