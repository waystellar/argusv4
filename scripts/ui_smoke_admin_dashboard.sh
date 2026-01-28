#!/bin/bash
#
# UI Smoke Test for AdminDashboard (UI-23)
#
# Verifies AdminDashboard.tsx uses design system tokens,
# has no legacy color/sizing signals, and key features are intact.
#
# Checks:
# 1. File exists
# 2. No legacy color tokens (gray-*, primary-*, gradient)
# 3. No legacy sizing tokens (space-y-*, text-2xl, text-sm, rounded-lg)
# 4. Design system tokens present
# 5. Component features intact (health panel, events, quick actions, search)
# 6. Base component usage (Badge, EmptyState, Skeleton)
#
# Usage:
#   ./scripts/ui_smoke_admin_dashboard.sh

set -e

echo "============================================"
echo "  UI Smoke Test: AdminDashboard (UI-23)"
echo "============================================"
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
AD="${WEB_DIR}/src/pages/admin/AdminDashboard.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: File Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${AD}" ]; then
    pass "AdminDashboard.tsx exists"
else
    fail "AdminDashboard.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "bg-gray-" "text-green-" "bg-green-" "text-red-" "bg-red-" "text-blue-" "bg-blue-" "text-yellow-" "bg-yellow-" "primary-[0-9]"; do
    CHECK=$((CHECK + 1))
    if grep -E "${pattern}" "${AD}" 2>/dev/null | grep -v "^.*\*.*UI-" > /dev/null 2>&1; then
        fail "Legacy token '${pattern}' found"
    else
        pass "No '${pattern}'"
    fi
done

CHECK=$((CHECK + 1))
if grep -q "bg-gradient" "${AD}" 2>/dev/null; then
    fail "Gradient found (bg-gradient-*)"
else
    pass "No gradients"
fi

# --- Check 3: No legacy sizing tokens ---
echo ""
echo "--- Check 3: No Legacy Sizing Tokens ---"

CHECK=$((CHECK + 1))
if grep -E '\btext-sm\b|\btext-xs\b|\btext-lg\b|\btext-base\b' "${AD}" > /dev/null 2>&1; then
    fail "Non-ds text sizing found"
else
    pass "No non-ds text sizing"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-xl\b' "${AD}" > /dev/null 2>&1; then
    fail "Non-ds radius found"
else
    pass "No non-ds radius"
fi

CHECK=$((CHECK + 1))
if grep -E '\bspace-y-[0-9]' "${AD}" > /dev/null 2>&1; then
    fail "Non-ds space-y found"
else
    pass "No non-ds space-y"
fi

CHECK=$((CHECK + 1))
if grep -E '\btext-2xl\b|\btext-3xl\b' "${AD}" > /dev/null 2>&1; then
    fail "Non-ds heading size found (text-2xl/3xl)"
else
    pass "No non-ds heading sizes"
fi

# --- Check 4: Design system tokens present ---
echo ""
echo "--- Check 4: Design System Tokens ---"

for token in "bg-neutral-950" "bg-neutral-900" "bg-neutral-800" "text-neutral-50" "text-neutral-400" "text-neutral-500" "border-neutral-800" "border-neutral-700" "bg-status-success" "bg-status-warning" "bg-status-error" "text-status-" "bg-accent-" "text-ds-title" "text-ds-heading" "text-ds-body-sm" "text-ds-caption" "rounded-ds-lg" "rounded-ds-md" "rounded-ds-sm" "px-ds-" "py-ds-" "p-ds-" "gap-ds-" "mt-ds-" "mb-ds-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${token}" "${AD}"; then
        pass "Token '${token}' present"
    else
        fail "Token '${token}' missing"
    fi
done

# --- Check 5: Component features intact ---
echo ""
echo "--- Check 5: Component Features ---"

CHECK=$((CHECK + 1))
if grep -q "SystemHealth" "${AD}"; then
    pass "SystemHealth interface defined"
else
    fail "SystemHealth interface missing"
fi

CHECK=$((CHECK + 1))
if grep -q "EventSummary" "${AD}"; then
    pass "EventSummary interface defined"
else
    fail "EventSummary interface missing"
fi

CHECK=$((CHECK + 1))
if grep -q "getHealthStatusColor" "${AD}"; then
    pass "Health status color function present"
else
    fail "Health status color function missing"
fi

CHECK=$((CHECK + 1))
if grep -q "runHealthCheck" "${AD}"; then
    pass "Health check action present"
else
    fail "Health check action missing"
fi

CHECK=$((CHECK + 1))
if grep -q "searchQuery" "${AD}"; then
    pass "Search functionality present"
else
    fail "Search functionality missing"
fi

CHECK=$((CHECK + 1))
if grep -q "statusFilter" "${AD}"; then
    pass "Status filter present"
else
    fail "Status filter missing"
fi

CHECK=$((CHECK + 1))
if grep -q "filteredEvents" "${AD}"; then
    pass "Event filtering logic present"
else
    fail "Event filtering missing"
fi

CHECK=$((CHECK + 1))
if grep -q "VehicleBulkUpload" "${AD}"; then
    pass "Bulk upload integration present"
else
    fail "Bulk upload missing"
fi

CHECK=$((CHECK + 1))
if grep -q "getAdminHeaders" "${AD}"; then
    pass "Admin auth headers present"
else
    fail "Admin auth headers missing"
fi

# --- Check 6: Base component usage ---
echo ""
echo "--- Check 6: Base Component Usage ---"

CHECK=$((CHECK + 1))
if grep -q "import Badge" "${AD}"; then
    pass "Badge component imported"
else
    fail "Badge not imported"
fi

CHECK=$((CHECK + 1))
if grep -q "import EmptyState" "${AD}"; then
    pass "EmptyState component imported"
else
    fail "EmptyState not imported"
fi

CHECK=$((CHECK + 1))
if grep -q "SkeletonHealthPanel" "${AD}"; then
    pass "SkeletonHealthPanel imported"
else
    fail "SkeletonHealthPanel missing"
fi

CHECK=$((CHECK + 1))
if grep -q "SkeletonEventItem" "${AD}"; then
    pass "SkeletonEventItem imported"
else
    fail "SkeletonEventItem missing"
fi

CHECK=$((CHECK + 1))
if grep -q "focus:ring-" "${AD}"; then
    pass "Focus ring styles present"
else
    warn "No focus ring styles"
fi

CHECK=$((CHECK + 1))
if grep -q "flex flex-col gap-ds-" "${AD}"; then
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
    echo "  [ ] Header shows 'Argus Control Center' with timestamp"
    echo "  [ ] Health panel shows 4 metric tiles (DB, Redis, Trucks, Last Data)"
    echo "  [ ] Metric values use text-ds-title size"
    echo "  [ ] Health dots use status-success/warning/error colors"
    echo "  [ ] Events list with search input and status filter dropdown"
    echo "  [ ] Event rows show name, Badge, event ID, date, vehicle count"
    echo "  [ ] Empty states rendered via EmptyState component"
    echo "  [ ] Quick Actions sidebar with cards for each action"
    echo "  [ ] Getting Started guide uses flat accent bg (no gradient)"
    echo "  [ ] System Info shows version and API URL"
    echo "  [ ] Bulk Upload modal opens correctly"
    echo "  [ ] Responsive: stacks to single column on mobile"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
