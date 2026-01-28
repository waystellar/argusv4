#!/bin/bash
#
# UI Smoke Test for YouTubeEmbed (UI-22)
#
# Verifies YouTubeEmbed.tsx uses design system tokens,
# has no legacy color signals, and key features are intact.
#
# Checks:
# 1. File exists
# 2. No legacy color tokens
# 3. No legacy sizing tokens
# 4. Design system tokens present
# 5. Component features intact (video states, retry, accessibility)
#
# Usage:
#   ./scripts/ui_smoke_youtube_embed.sh

set -e

echo "==========================================="
echo "  UI Smoke Test: YouTubeEmbed (UI-22)"
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
YTE="${WEB_DIR}/src/components/VehicleDetail/YouTubeEmbed.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: File Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${YTE}" ]; then
    pass "YouTubeEmbed.tsx exists"
else
    fail "YouTubeEmbed.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "bg-gray-" "text-green-" "bg-green-" "text-red-" "bg-red-" "text-blue-" "bg-blue-" "text-yellow-" "bg-yellow-" "primary-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${YTE}" 2>/dev/null; then
        fail "Legacy token '${pattern}' found"
    else
        pass "No '${pattern}'"
    fi
done

# --- Check 3: No legacy sizing tokens ---
echo ""
echo "--- Check 3: No Legacy Sizing Tokens ---"

CHECK=$((CHECK + 1))
if grep -E '\btext-xs\b|\btext-sm\b|\btext-lg\b|\btext-base\b' "${YTE}" > /dev/null 2>&1; then
    fail "Non-ds text sizing found"
else
    pass "No non-ds text sizing"
fi

CHECK=$((CHECK + 1))
if grep -E '\brounded-lg\b|\brounded-xl\b|\brounded-md\b' "${YTE}" > /dev/null 2>&1; then
    fail "Non-ds radius found"
else
    pass "No non-ds radius"
fi

CHECK=$((CHECK + 1))
if grep -E '\bmt-[1-9][0-9]*\b|\bmb-[1-9][0-9]*\b' "${YTE}" > /dev/null 2>&1; then
    fail "Non-ds margin found"
else
    pass "No non-ds margin"
fi

CHECK=$((CHECK + 1))
if grep -E '\bp-[0-9]\b|\bpx-[0-9]\b|\bpy-[0-9]\b' "${YTE}" > /dev/null 2>&1; then
    fail "Non-ds padding found"
else
    pass "No non-ds padding"
fi

# --- Check 4: Design system tokens present ---
echo ""
echo "--- Check 4: Design System Tokens ---"

for token in "bg-neutral-900" "text-neutral-" "text-status-error" "bg-accent-" "border-accent-" "text-ds-body-sm" "text-ds-caption" "rounded-ds-lg" "mt-ds-" "mb-ds-" "px-ds-" "py-ds-" "duration-ds-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${token}" "${YTE}"; then
        pass "Token '${token}' present"
    else
        fail "Token '${token}' missing"
    fi
done

# --- Check 5: Component features intact ---
echo ""
echo "--- Check 5: Component Features ---"

CHECK=$((CHECK + 1))
if grep -q "VideoState" "${YTE}"; then
    pass "VideoState type defined"
else
    fail "VideoState type missing"
fi

CHECK=$((CHECK + 1))
if grep -q "ErrorInfo" "${YTE}"; then
    pass "ErrorInfo interface defined"
else
    fail "ErrorInfo interface missing"
fi

CHECK=$((CHECK + 1))
if grep -q "handleRetry" "${YTE}"; then
    pass "Retry functionality present"
else
    fail "Retry functionality missing"
fi

CHECK=$((CHECK + 1))
if grep -q "LOAD_TIMEOUT_MS" "${YTE}"; then
    pass "Load timeout constant present"
else
    fail "Load timeout missing"
fi

CHECK=$((CHECK + 1))
if grep -q "handleLoad" "${YTE}"; then
    pass "Load handler present"
else
    fail "Load handler missing"
fi

CHECK=$((CHECK + 1))
if grep -q "handleError" "${YTE}"; then
    pass "Error handler present"
else
    fail "Error handler missing"
fi

CHECK=$((CHECK + 1))
if grep -q "youtube.com/embed" "${YTE}"; then
    pass "YouTube embed URL present"
else
    fail "YouTube embed URL missing"
fi

CHECK=$((CHECK + 1))
if grep -q "allowFullScreen" "${YTE}"; then
    pass "Fullscreen support present"
else
    fail "Fullscreen support missing"
fi

CHECK=$((CHECK + 1))
if grep -q "_retry" "${YTE}"; then
    pass "Cache-busting retry mechanism present"
else
    fail "Cache-busting retry missing"
fi

CHECK=$((CHECK + 1))
if grep -q "VideoOffIcon" "${YTE}"; then
    pass "VideoOffIcon component present"
else
    fail "VideoOffIcon missing"
fi

CHECK=$((CHECK + 1))
if grep -q "LoadingSpinner" "${YTE}"; then
    pass "LoadingSpinner component present"
else
    fail "LoadingSpinner missing"
fi

CHECK=$((CHECK + 1))
if grep -q "animate-spin" "${YTE}"; then
    pass "Spinner animation present"
else
    fail "Spinner animation missing"
fi

# --- Check 6: Accessibility ---
echo ""
echo "--- Check 6: Accessibility ---"

CHECK=$((CHECK + 1))
if grep -q 'role="alert"' "${YTE}"; then
    pass "Error role=alert present"
else
    warn "No role=alert on error state"
fi

CHECK=$((CHECK + 1))
if grep -q 'title=' "${YTE}"; then
    pass "iframe title attribute present"
else
    fail "iframe title missing"
fi

CHECK=$((CHECK + 1))
if grep -q 'focus:ring-' "${YTE}"; then
    pass "Focus ring on retry button present"
else
    warn "No focus ring found"
fi

CHECK=$((CHECK + 1))
if grep -q 'min-h-\[44px\]' "${YTE}"; then
    pass "44px touch target on retry button"
else
    warn "No 44px touch target found"
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
    echo "  [ ] No-video state shows camera-off icon + 'No video available'"
    echo "  [ ] Loading state shows spinner + 'Loading video...' text"
    echo "  [ ] Error state shows warning icon in status-error red"
    echo "  [ ] Error state shows hint text in neutral-500"
    echo "  [ ] Retry button uses accent-600 with hover/focus states"
    echo "  [ ] YouTube iframe fills container with correct aspect ratio"
    echo "  [ ] Vehicle number shown in caption style below state text"
    echo "  [ ] Responsive: scales correctly at mobile and 1440px"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
