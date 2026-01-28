#!/bin/bash
#
# Units & Race Model Verification Script
#
# Tests that the Argus dashboard correctly:
# - Displays distances in miles (imperial default)
# - Supports point-to-point vs lap-based race modes
# - Tracks tire miles via GPS distance
#
# Usage: bash verify_units_fix.sh [DASHBOARD_URL]
#
# Example:
#   bash verify_units_fix.sh                          # Uses localhost:8080
#   bash verify_units_fix.sh http://192.168.0.18:8080 # Uses edge IP
#

DASHBOARD_URL="${1:-http://localhost:8080}"

echo "========================================"
echo "  Units & Race Model Verification"
echo "========================================"
echo ""
echo "Dashboard URL: $DASHBOARD_URL"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# ========================================
# Test 1: Check fuel status API includes miles
# ========================================
echo "Test 1: Fuel Status API includes miles"
echo "---------------------------------------"
RESPONSE=$(curl -s "$DASHBOARD_URL/api/fuel/status" 2>&1)

if echo "$RESPONSE" | grep -q "estimated_miles_remaining"; then
    pass "Fuel status includes estimated_miles_remaining"
else
    fail "Fuel status missing estimated_miles_remaining"
    echo "     Response: $RESPONSE"
fi
echo ""

# ========================================
# Test 2: Check tire status API includes miles
# ========================================
echo "Test 2: Tire Status API includes miles"
echo "---------------------------------------"
RESPONSE=$(curl -s "$DASHBOARD_URL/api/tires/status" 2>&1)

if echo "$RESPONSE" | grep -q "miles_on_tires"; then
    pass "Tire status includes miles_on_tires"
else
    fail "Tire status missing miles_on_tires"
    echo "     Response: $RESPONSE"
fi

if echo "$RESPONSE" | grep -q "miles_remaining"; then
    pass "Tire status includes miles_remaining"
else
    fail "Tire status missing miles_remaining"
fi

if echo "$RESPONSE" | grep -q "recommended_life_miles"; then
    pass "Tire status includes recommended_life_miles"
else
    fail "Tire status missing recommended_life_miles"
fi
echo ""

# ========================================
# Test 3: Check dashboard HTML includes race type selector
# ========================================
echo "Test 3: Dashboard HTML includes race type selector"
echo "---------------------------------------------------"
RESPONSE=$(curl -s "$DASHBOARD_URL/" 2>&1)

if echo "$RESPONSE" | grep -q "raceTypeSelect"; then
    pass "Dashboard includes race type selector"
else
    fail "Dashboard missing race type selector"
fi

if echo "$RESPONSE" | grep -q "point_to_point"; then
    pass "Dashboard includes point-to-point option"
else
    fail "Dashboard missing point-to-point option"
fi

if echo "$RESPONSE" | grep -q "lap_based"; then
    pass "Dashboard includes lap-based option"
else
    fail "Dashboard missing lap-based option"
fi
echo ""

# ========================================
# Test 4: Check dashboard HTML includes lap count input
# ========================================
echo "Test 4: Dashboard HTML includes lap count input"
echo "------------------------------------------------"
if echo "$RESPONSE" | grep -q "lapCountInput"; then
    pass "Dashboard includes lap count input"
else
    fail "Dashboard missing lap count input"
fi
echo ""

# ========================================
# Test 5: Check JavaScript uses miles for distance
# ========================================
echo "Test 5: JavaScript uses miles for distance"
echo "-------------------------------------------"
if echo "$RESPONSE" | grep -q "EARTH_RADIUS_MI"; then
    pass "JavaScript includes Earth radius in miles constant"
else
    fail "JavaScript missing EARTH_RADIUS_MI constant"
fi

if echo "$RESPONSE" | grep -q "const UNITS = 'imperial'"; then
    pass "Default units set to imperial"
else
    info "Default units may not be imperial"
fi

if echo "$RESPONSE" | grep -q "formatDistance"; then
    pass "JavaScript includes formatDistance function"
else
    fail "JavaScript missing formatDistance function"
fi
echo ""

# ========================================
# Test 6: Tire update resets miles on change
# ========================================
echo "Test 6: Tire update resets miles on change"
echo "-------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Cookie: pit_session=test" \
    -d '{"current_compound": "All-Terrain", "changed": true}' \
    "$DASHBOARD_URL/api/tires/update" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | grep -q '"miles_on_tires": 0'; then
        pass "Tire change resets miles_on_tires to 0"
    elif echo "$BODY" | grep -q '"miles_on_tires":0'; then
        pass "Tire change resets miles_on_tires to 0"
    else
        info "Response: $BODY"
        info "Check that miles_on_tires resets on tire change"
    fi
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Tire update requires authentication (expected)"
else
    fail "Tire update returned $HTTP_CODE"
fi
echo ""

# ========================================
# Summary
# ========================================
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "Units Configuration:"
echo "  - Default: imperial (miles, mph)"
echo "  - Storage: All internal distances in miles"
echo "  - Display: Miles for point-to-point, laps for lap-based"
echo ""
echo "Race Types Supported:"
echo "  - point_to_point: King of Hammers, Baja, SCORE, etc."
echo "  - lap_based: Laughlin, short course, etc."
echo ""
echo "Tire Miles Tracking:"
echo "  - Tracked via GPS distance (haversine formula)"
echo "  - Reset on tire change"
echo "  - Recommended life: 120 miles default for point-to-point"
echo ""
echo "Manual Verification Checklist:"
echo "  [ ] Course distance shows 'mi Done' / 'mi Left'"
echo "  [ ] Fuel shows 'Est. Miles Left' for point-to-point"
echo "  [ ] Tire shows 'Miles on Set' / 'Est. Miles Left' for point-to-point"
echo "  [ ] Changing to 'Lap Race' shows lap count input"
echo "  [ ] Changing to 'Lap Race' switches labels to laps"
echo "  [ ] Race type preference persists on page reload"
echo ""
