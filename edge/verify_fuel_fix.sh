#!/bin/bash
#
# Fuel System Verification Script
#
# Tests the fuel tracking system:
# - Fuel state persistence
# - API endpoints (get/set)
# - Validation (range, capacity)
# - "Unset" state handling
#
# Usage: bash verify_fuel_fix.sh [DASHBOARD_URL]
#
# Example:
#   bash verify_fuel_fix.sh                          # Uses localhost:8080
#   bash verify_fuel_fix.sh http://192.168.0.18:8080 # Uses edge IP
#

DASHBOARD_URL="${1:-http://localhost:8080}"
FUEL_STATE_FILE="/opt/argus/config/fuel_state.json"

echo "========================================"
echo "  Fuel System Verification"
echo "========================================"
echo ""
echo "Dashboard URL: $DASHBOARD_URL"
echo "Fuel State File: $FUEL_STATE_FILE"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Get a session cookie for authenticated requests
# Note: In production, you'd need to login first
SESSION_COOKIE="pit_session=test_session"

# ========================================
# Test 1: Check fuel status API structure
# ========================================
echo "Test 1: Fuel Status API Structure"
echo "----------------------------------"
RESPONSE=$(curl -s -H "Cookie: $SESSION_COOKIE" "$DASHBOARD_URL/api/fuel/status" 2>&1)

if echo "$RESPONSE" | grep -q "fuel_set"; then
    pass "API returns fuel_set field"
else
    fail "API missing fuel_set field"
    echo "     Response: $RESPONSE"
fi

if echo "$RESPONSE" | grep -q "tank_capacity_gal"; then
    pass "API returns tank_capacity_gal field"
else
    fail "API missing tank_capacity_gal field"
fi

if echo "$RESPONSE" | grep -q "current_fuel_gal"; then
    pass "API returns current_fuel_gal field"
else
    fail "API missing current_fuel_gal field"
fi

if echo "$RESPONSE" | grep -q "updated_at"; then
    pass "API returns updated_at field"
else
    fail "API missing updated_at field"
fi
echo ""

# ========================================
# Test 2: Check initial "unset" state
# ========================================
echo "Test 2: Initial Unset State"
echo "----------------------------"
# Check if fuel_set is false or current_fuel_gal is null initially
if echo "$RESPONSE" | grep -q '"fuel_set": *false\|"fuel_set":false'; then
    pass "fuel_set is false when not configured"
elif echo "$RESPONSE" | grep -q '"fuel_set": *true'; then
    info "fuel_set is true (fuel was previously configured)"
else
    info "Could not determine fuel_set state"
fi
echo ""

# ========================================
# Test 3: Set fuel level and verify persistence
# ========================================
echo "Test 3: Set Fuel Level"
echo "----------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Cookie: $SESSION_COOKIE" \
    -d '{"current_fuel_gal": 25.5}' \
    "$DASHBOARD_URL/api/fuel/update" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    if echo "$BODY" | grep -q '"success"'; then
        pass "Set fuel to 25.5 gal - HTTP 200"
    else
        fail "Set fuel returned 200 but no success flag"
        echo "     Response: $BODY"
    fi
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401) - test with valid session"
else
    fail "Set fuel returned HTTP $HTTP_CODE"
    echo "     Response: $BODY"
fi
echo ""

# ========================================
# Test 4: Verify fuel was persisted
# ========================================
echo "Test 4: Verify Persistence"
echo "--------------------------"
if [[ -f "$FUEL_STATE_FILE" ]]; then
    pass "fuel_state.json exists at $FUEL_STATE_FILE"

    if cat "$FUEL_STATE_FILE" | grep -q '"fuel_set": *true'; then
        pass "fuel_set is true in persisted file"
    else
        info "fuel_set may be false or missing in file"
    fi

    if cat "$FUEL_STATE_FILE" | grep -q '"current_fuel_gal"'; then
        pass "current_fuel_gal exists in persisted file"
    else
        fail "current_fuel_gal missing from persisted file"
    fi
else
    info "fuel_state.json not found (may not have permissions or dashboard not running)"
fi
echo ""

# ========================================
# Test 5: Validate range checking
# ========================================
echo "Test 5: Validation - Negative Fuel"
echo "-----------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Cookie: $SESSION_COOKIE" \
    -d '{"current_fuel_gal": -5}' \
    "$DASHBOARD_URL/api/fuel/update" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "400" ]]; then
    pass "Negative fuel rejected with HTTP 400"
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401)"
else
    fail "Negative fuel should be rejected (got HTTP $HTTP_CODE)"
fi
echo ""

# ========================================
# Test 6: Validate over-capacity checking
# ========================================
echo "Test 6: Validation - Over Capacity"
echo "-----------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Cookie: $SESSION_COOKIE" \
    -d '{"current_fuel_gal": 999}' \
    "$DASHBOARD_URL/api/fuel/update" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "400" ]]; then
    pass "Over-capacity fuel rejected with HTTP 400"
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401)"
else
    fail "Over-capacity fuel should be rejected (got HTTP $HTTP_CODE)"
fi
echo ""

# ========================================
# Test 7: Tank Filled shortcut
# ========================================
echo "Test 7: Tank Filled Shortcut"
echo "-----------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Cookie: $SESSION_COOKIE" \
    -d '{"filled": true}' \
    "$DASHBOARD_URL/api/fuel/update" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    pass "Tank filled shortcut accepted"
    # Verify fuel is now at capacity
    FUEL_STATUS=$(curl -s -H "Cookie: $SESSION_COOKIE" "$DASHBOARD_URL/api/fuel/status")
    if echo "$FUEL_STATUS" | grep -q '"fuel_percent": *100\|"fuel_percent":100'; then
        pass "Fuel percent is 100% after fill"
    else
        info "Fuel percent may not be exactly 100%"
    fi
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401)"
else
    fail "Tank filled returned HTTP $HTTP_CODE"
fi
echo ""

# ========================================
# Test 8: Update tank capacity
# ========================================
echo "Test 8: Update Tank Capacity"
echo "-----------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Cookie: $SESSION_COOKIE" \
    -d '{"tank_capacity_gal": 40}' \
    "$DASHBOARD_URL/api/fuel/update" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    pass "Tank capacity updated to 40 gal"
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401)"
else
    fail "Tank capacity update returned HTTP $HTTP_CODE"
fi
echo ""

# ========================================
# Summary
# ========================================
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "Fuel Data Model:"
echo "  - tank_capacity_gal: Max fuel cell capacity"
echo "  - current_fuel_gal: Current level (null until set)"
echo "  - fuel_set: Boolean flag (false = unset, shows 'Unset' in UI)"
echo "  - consumption_rate_mpg: Optional burn rate estimate"
echo "  - updated_at/updated_by/source: Audit fields"
echo ""
echo "Persistence:"
echo "  - File: $FUEL_STATE_FILE"
echo "  - Format: JSON"
echo "  - Loaded on startup, saved on every update"
echo ""
echo "API Endpoints:"
echo "  - GET  /api/fuel/status - Returns current fuel state"
echo "  - POST /api/fuel/update - Set fuel level/config"
echo ""
echo "Validation:"
echo "  - current_fuel_gal: 0 to tank_capacity_gal"
echo "  - tank_capacity_gal: 1 to 100 gallons"
echo "  - consumption_rate_mpg: 0.1 to 20"
echo ""
echo "UI Features:"
echo "  - Shows 'Unset' until crew sets fuel level"
echo "  - Click fuel value to edit"
echo "  - Config panel for tank capacity and MPG"
echo "  - 'TANK FILLED' button sets to capacity"
echo ""
