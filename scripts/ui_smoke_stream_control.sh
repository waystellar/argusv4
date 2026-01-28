#!/bin/bash
#
# UI Smoke Test for StreamControlPanel (UI-21)
#
# Verifies StreamControlPanel.tsx uses design system tokens,
# has no legacy color signals, and key features are intact.
#
# Checks:
# 1. File exists
# 2. No legacy color tokens (gray-*, green-*, red-*, yellow-*, blue-*, orange-*, primary-*, bg-surface)
# 3. No legacy sizing tokens (text-sm, text-xs, rounded-lg, p-N, gap-N non-ds)
# 4. Design system tokens present (neutral-*, status-*, accent-*, ds-*)
# 5. Component features intact (state machine, camera selection, error handling)
# 6. Accessibility attributes present
#
# Usage:
#   ./scripts/ui_smoke_stream_control.sh

set -e

echo "==========================================="
echo "  UI Smoke Test: StreamControlPanel (UI-21)"
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
SCP="${WEB_DIR}/src/components/StreamControl/StreamControlPanel.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: File Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${SCP}" ]; then
    pass "StreamControlPanel.tsx exists"
else
    fail "StreamControlPanel.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "bg-gray-" "text-green-" "bg-green-" "text-red-" "bg-red-" "text-blue-" "bg-blue-" "text-yellow-" "bg-yellow-" "bg-orange-" "text-orange-" "primary-" "ring-red-" "ring-blue-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${SCP}" 2>/dev/null; then
        fail "Legacy token '${pattern}' found"
    else
        pass "No '${pattern}'"
    fi
done

# --- Check 3: No legacy sizing tokens ---
echo ""
echo "--- Check 3: No Legacy Sizing Tokens ---"

CHECK=$((CHECK + 1))
if grep -E '\btext-xs\b|\btext-sm\b|\btext-lg\b|\btext-base\b' "${SCP}" > /dev/null 2>&1; then
    fail "Non-ds text sizing found"
else
    pass "No non-ds text sizing"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-xl\b|\brounded-md\b' "${SCP}" > /dev/null 2>&1; then
    fail "Non-ds radius found"
else
    pass "No non-ds radius"
fi

CHECK=$((CHECK + 1))
if grep -E '\bspace-y-[0-9]' "${SCP}" > /dev/null 2>&1; then
    fail "Non-ds space-y found"
else
    pass "No non-ds space-y"
fi

CHECK=$((CHECK + 1))
if grep -E '\bp-[0-9]\b|\bgap-[0-9]\b|\bpx-[0-9]\b|\bpy-[0-9]' "${SCP}" > /dev/null 2>&1; then
    fail "Non-ds spacing found (p-N, gap-N, px-N, py-N)"
else
    pass "No non-ds spacing"
fi

CHECK=$((CHECK + 1))
if grep -E '\bmb-[1-9][0-9]*\b|\bmt-[1-9][0-9]*\b' "${SCP}" > /dev/null 2>&1; then
    fail "Non-ds margin found (mb-N, mt-N)"
else
    pass "No non-ds margin"
fi

# --- Check 4: Design system tokens present ---
echo ""
echo "--- Check 4: Design System Tokens ---"

for token in "bg-neutral-" "text-neutral-" "bg-status-success" "bg-status-error" "bg-status-warning" "text-status-" "bg-accent-600" "text-ds-body-sm" "text-ds-caption" "rounded-ds-lg" "p-ds-" "gap-ds-" "duration-ds-" "ds-stack"; do
    CHECK=$((CHECK + 1))
    if grep -q "${token}" "${SCP}"; then
        pass "Token '${token}' present"
    else
        fail "Token '${token}' missing"
    fi
done

# --- Check 5: Component features intact ---
echo ""
echo "--- Check 5: Component Features ---"

CHECK=$((CHECK + 1))
if grep -q "StreamState" "${SCP}"; then
    pass "StreamState type exported"
else
    fail "StreamState type missing"
fi

CHECK=$((CHECK + 1))
if grep -q "EdgeStatusInfo" "${SCP}"; then
    pass "EdgeStatusInfo interface exported"
else
    fail "EdgeStatusInfo interface missing"
fi

CHECK=$((CHECK + 1))
if grep -q "getActionableError" "${SCP}"; then
    pass "Actionable error system present"
else
    fail "Actionable error system missing"
fi

CHECK=$((CHECK + 1))
if grep -q "formatLastSeen" "${SCP}"; then
    pass "Last seen formatter present"
else
    fail "Last seen formatter missing"
fi

CHECK=$((CHECK + 1))
if grep -q "getStatusColor" "${SCP}"; then
    pass "Status color function present"
else
    fail "Status color function missing"
fi

CHECK=$((CHECK + 1))
if grep -q "CAMERA_LABELS" "${SCP}"; then
    pass "Camera labels mapping present"
else
    fail "Camera labels mapping missing"
fi

CHECK=$((CHECK + 1))
if grep -q "onStartStream" "${SCP}"; then
    pass "Start stream callback prop present"
else
    fail "Start stream callback missing"
fi

CHECK=$((CHECK + 1))
if grep -q "onStopStream" "${SCP}"; then
    pass "Stop stream callback prop present"
else
    fail "Stop stream callback missing"
fi

CHECK=$((CHECK + 1))
if grep -q "onDiagnostics" "${SCP}"; then
    pass "Diagnostics callback prop present"
else
    fail "Diagnostics callback missing"
fi

CHECK=$((CHECK + 1))
if grep -q "pendingCommand" "${SCP}"; then
    pass "Pending command handling present"
else
    fail "Pending command handling missing"
fi

CHECK=$((CHECK + 1))
if grep -q "animate-spin" "${SCP}"; then
    pass "Loading spinner animation present"
else
    fail "Loading spinner missing"
fi

CHECK=$((CHECK + 1))
if grep -q "animate-pulse" "${SCP}"; then
    pass "Pulse animation for active states present"
else
    fail "Pulse animation missing"
fi

# --- Check 6: Accessibility ---
echo ""
echo "--- Check 6: Accessibility ---"

CHECK=$((CHECK + 1))
if grep -q 'role="alert"' "${SCP}"; then
    pass "Error alert role present"
else
    fail "Error alert role missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'aria-pressed' "${SCP}"; then
    pass "Camera button aria-pressed present"
else
    fail "Camera button aria-pressed missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'focus:ring-' "${SCP}"; then
    pass "Focus ring styles present"
else
    warn "No focus ring styles found"
fi

CHECK=$((CHECK + 1))
if grep -q 'sr-only' "${SCP}"; then
    pass "Screen reader text present"
else
    warn "No screen reader text found"
fi

CHECK=$((CHECK + 1))
if grep -q 'min-h-\[44px\]' "${SCP}"; then
    pass "44px touch targets present"
else
    fail "44px touch targets missing"
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
    echo "  [ ] Status bar shows Edge Connected/Disconnected with green/red dot"
    echo "  [ ] Stream status shows correct label (Ready/Live/Starting/Stopping/Error)"
    echo "  [ ] Error alerts show warning (amber) or error (red) backgrounds"
    echo "  [ ] Camera grid shows 4 buttons in 2x2 layout"
    echo "  [ ] Selected camera uses accent-600 blue with ring"
    echo "  [ ] Streaming camera uses status-error red with ring + pulse dot"
    echo "  [ ] Unavailable cameras are dimmed and disabled"
    echo "  [ ] Start button is green, Stop button is red"
    echo "  [ ] Disabled buttons use neutral-700 background"
    echo "  [ ] Loading spinners appear during Starting/Stopping states"
    echo "  [ ] Diagnostics button visible with chart icon"
    echo "  [ ] All buttons meet 44px minimum touch target"
    echo "  [ ] Responsive: works at mobile and 1440px widths"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
