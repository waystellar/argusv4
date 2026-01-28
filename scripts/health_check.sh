#!/bin/bash
#
# Health Check Script for Argus v4
#
# Checks that all critical services are running and responding.
# Used for regression testing and deployment verification.
#
# Usage:
#   ./scripts/health_check.sh [api_url] [frontend_url]
#
# Defaults:
#   API: http://localhost:8000
#   Frontend: http://localhost:5173

set -e

API_URL="${1:-http://localhost:8000}"
FRONTEND_URL="${2:-http://localhost:5173}"

echo "=========================================="
echo "  Argus v4 Health Check"
echo "=========================================="
echo ""
echo "API URL: ${API_URL}"
echo "Frontend URL: ${FRONTEND_URL}"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

check() {
    local name=$1
    local url=$2
    local expected=$3

    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")

    if [ "$STATUS" = "$expected" ] || [ "$STATUS" = "200" ]; then
        echo -e "${GREEN}[OK]${NC} $name - HTTP $STATUS"
    elif [ "$STATUS" = "000" ]; then
        echo -e "${RED}[FAIL]${NC} $name - Connection failed"
        FAILED=1
    else
        echo -e "${YELLOW}[WARN]${NC} $name - HTTP $STATUS (expected $expected)"
    fi
}

echo "--- Backend API ---"
check "API Health" "${API_URL}/api/v1/health" "200"
check "API Events Endpoint" "${API_URL}/api/v1/events" "200"

echo ""
echo "--- Frontend ---"
check "Frontend Root" "${FRONTEND_URL}/" "200"
check "Events Page" "${FRONTEND_URL}/events" "200"
check "Admin Page" "${FRONTEND_URL}/admin" "200"
check "Team Login" "${FRONTEND_URL}/team/login" "200"

echo ""
echo "--- Critical Pages ---"

# These may require auth, so we just check they don't 500
PAGES=("/admin" "/team/dashboard" "/production" "/events")

for page in "${PAGES[@]}"; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${FRONTEND_URL}${page}" 2>/dev/null || echo "000")
    if [ "$STATUS" = "000" ]; then
        echo -e "${RED}[FAIL]${NC} Page ${page} - Connection failed"
        FAILED=1
    elif [ "$STATUS" -ge "500" ]; then
        echo -e "${RED}[FAIL]${NC} Page ${page} - Server error (HTTP $STATUS)"
        FAILED=1
    else
        echo -e "${GREEN}[OK]${NC} Page ${page} - HTTP $STATUS"
    fi
done

echo ""
echo "=========================================="
if [ "$FAILED" = "0" ]; then
    echo -e "${GREEN}Health check PASSED${NC}"
    exit 0
else
    echo -e "${RED}Health check FAILED${NC}"
    exit 1
fi
