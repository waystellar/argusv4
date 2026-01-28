#!/bin/bash
#
# UI Smoke Test for EventLive Page (UI-15)
#
# Verifies the live event watching page uses design system tokens,
# has no legacy color signals, and key components are wired up.
#
# Checks:
# 1. EventLive.tsx exists
# 2. No legacy color tokens
# 3. Design system tokens present (neutral-*, status-*, ds-*)
# 4. Key components imported (Map, Leaderboard, Header, ConnectionStatus)
# 5. Accessibility attributes present
# 6. ConnectionStatus.tsx migrated (dependency)
#
# Usage:
#   ./scripts/ui_smoke_event_live.sh

set -e

echo "=========================================="
echo "  UI Smoke Test: EventLive Page (UI-15)"
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
EVENT_LIVE="${WEB_DIR}/src/pages/EventLive.tsx"
CONN_STATUS="${WEB_DIR}/src/components/common/ConnectionStatus.tsx"

# --- Check 1: File exists ---
echo "--- Check 1: EventLive.tsx Exists ---"
CHECK=$((CHECK + 1))
if [ -f "${EVENT_LIVE}" ]; then
    pass "EventLive.tsx exists"
else
    fail "EventLive.tsx not found"
    exit 1
fi

# --- Check 2: No legacy color tokens ---
echo ""
echo "--- Check 2: No Legacy Color Tokens ---"

for pattern in "bg-surface" "text-gray-" "border-gray-" "text-green-" "bg-green-" "bg-gray-" "text-red-" "text-blue-" "text-yellow-" "primary-"; do
    CHECK=$((CHECK + 1))
    if grep -q "${pattern}" "${EVENT_LIVE}" 2>/dev/null; then
        fail "Legacy token '${pattern}' found in EventLive.tsx"
    else
        pass "No '${pattern}' legacy tokens"
    fi
done

# --- Check 3: Design system tokens present ---
echo ""
echo "--- Check 3: Design System Tokens ---"

CHECK=$((CHECK + 1))
if grep -q "bg-neutral-" "${EVENT_LIVE}"; then
    pass "Neutral background tokens present"
else
    fail "No neutral background tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-neutral-" "${EVENT_LIVE}"; then
    pass "Neutral text tokens present"
else
    fail "No neutral text tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "border-neutral-" "${EVENT_LIVE}"; then
    pass "Neutral border tokens present"
else
    fail "No neutral border tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-status-success" "${EVENT_LIVE}"; then
    pass "Status success token present"
else
    fail "No status-success token found"
fi

CHECK=$((CHECK + 1))
if grep -q "text-ds-" "${EVENT_LIVE}"; then
    pass "Typography tokens present (text-ds-*)"
else
    fail "No typography tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "px-ds-\|py-ds-\|p-ds-\|gap-ds-" "${EVENT_LIVE}"; then
    pass "Spacing tokens present (*-ds-*)"
else
    fail "No spacing tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "rounded-ds-" "${EVENT_LIVE}"; then
    pass "Radius tokens present (rounded-ds-*)"
else
    fail "No radius tokens found"
fi

CHECK=$((CHECK + 1))
if grep -q "duration-ds-" "${EVENT_LIVE}"; then
    pass "Transition tokens present (duration-ds-*)"
else
    warn "No transition tokens found"
fi

# --- Check 4: Key components imported ---
echo ""
echo "--- Check 4: Key Component Imports ---"

for component in "Map" "Leaderboard" "Header" "ConnectionStatus" "SystemHealthIndicator" "Skeleton"; do
    CHECK=$((CHECK + 1))
    if grep -q "import.*${component}" "${EVENT_LIVE}"; then
        pass "${component} imported"
    else
        fail "${component} not imported"
    fi
done

# --- Check 5: Accessibility ---
echo ""
echo "--- Check 5: Accessibility ---"

CHECK=$((CHECK + 1))
if grep -q 'aria-label' "${EVENT_LIVE}"; then
    pass "aria-label attributes present"
else
    warn "No aria-label attributes found"
fi

CHECK=$((CHECK + 1))
if grep -q 'focus:ring-' "${EVENT_LIVE}"; then
    pass "Focus ring styles present"
else
    warn "No focus ring styles found"
fi

# --- Check 6: ConnectionStatus dependency migrated ---
echo ""
echo "--- Check 6: ConnectionStatus.tsx Migrated ---"

CHECK=$((CHECK + 1))
if [ -f "${CONN_STATUS}" ]; then
    if grep -E "(text-gray-|bg-gray-|border-gray-|text-green-|bg-green-)" "${CONN_STATUS}" > /dev/null 2>&1; then
        fail "ConnectionStatus.tsx still has legacy tokens"
    else
        pass "ConnectionStatus.tsx fully migrated"
    fi
else
    fail "ConnectionStatus.tsx not found"
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
    echo "  [ ] Event title + status visible above the fold"
    echo "  [ ] Event info bar shows distance/laps/vehicles with ds tokens"
    echo "  [ ] Active vehicle count uses status-success green"
    echo "  [ ] Share button has focus ring and hover state"
    echo "  [ ] Map occupies remaining viewport height"
    echo "  [ ] Leaderboard section has neutral-850 background"
    echo "  [ ] Loading state shows skeleton placeholders"
    echo "  [ ] Connection status bar renders when disconnected"
    echo "  [ ] Responsive: mobile stacks, 1440px fills"
    echo ""
    exit 0
else
    echo -e "${RED}Some checks failed!${NC}"
    echo "Review the output above for details."
    exit 1
fi
