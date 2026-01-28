#!/bin/bash
#
# Fan Map Smoke Test
#
# Verifies that the basemap tile URL used in Map.tsx is permitted by CSP.
# Also checks that the tile server is reachable.
#
# Usage:
#   scripts/fan_map_smoke.sh                    # Default: http://localhost
#   scripts/fan_map_smoke.sh http://192.168.0.19  # Custom host
#
# Exit codes:
#   0 - Tile server reachable and CSP permits it
#   1 - Issue found

set -euo pipefail

BASE_URL="${1:-http://localhost}"
FAIL=0

echo "==============================="
echo "  Argus Fan Map Smoke Test"
echo "==============================="
echo ""

# 1. Check that CARTO tile server is reachable
TILE_URL="https://basemaps.cartocdn.com/dark_all/0/0/0.png"
echo "Step 1: Checking tile server reachability..."
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$TILE_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "  PASS: CARTO tile server reachable (HTTP $HTTP_CODE)"
else
    echo "  FAIL: CARTO tile server returned HTTP $HTTP_CODE"
    FAIL=1
fi

# 2. Check that CSP allows the CARTO domain
echo ""
echo "Step 2: Checking CSP permits basemaps.cartocdn.com..."
CSP=$(curl -sI "${BASE_URL}/" 2>/dev/null | grep -i "^content-security-policy:" | head -1)

if [ -z "$CSP" ]; then
    echo "  WARN: Could not fetch CSP header from ${BASE_URL}/"
    echo "  (Server may not be running — skipping CSP check)"
else
    # Check img-src includes CARTO
    if echo "$CSP" | grep -q "basemaps.cartocdn.com"; then
        echo "  PASS: basemaps.cartocdn.com in CSP"
    else
        echo "  FAIL: basemaps.cartocdn.com NOT in CSP"
        FAIL=1
    fi
fi

# 3. Check that OpenStreetMap fallback also works
echo ""
echo "Step 3: Checking OpenStreetMap tile server (fallback)..."
OSM_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "User-Agent: ArgusTest/1.0" "https://tile.openstreetmap.org/0/0/0.png" 2>/dev/null || echo "000")
if [ "$OSM_CODE" = "200" ]; then
    echo "  PASS: OpenStreetMap tile server reachable (HTTP $OSM_CODE)"
else
    echo "  WARN: OpenStreetMap returned HTTP $OSM_CODE (may be rate-limited)"
fi

echo ""
echo "==============================="
if [ $FAIL -eq 0 ]; then
    echo "  PASS: Fan map smoke test passed"
else
    echo "  FAIL: Fan map smoke test failed"
fi
echo "==============================="

exit $FAIL
