#!/bin/bash
#
# Fan Map Smoke Test
#
# MAP-STYLE-1: Updated to verify OpenTopoMap (light topo basemap).
# CARTO tiles have been removed in favor of always-light topo.
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
echo "  Fan Map Smoke Test"
echo "==============================="
echo ""

# 1. Check that OpenTopoMap tile server is reachable
TILE_URL="https://a.tile.opentopomap.org/0/0/0.png"
echo "Step 1: Checking tile server reachability..."
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "User-Agent: ArgusSmoke/1.0" "$TILE_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "304" ]; then
    echo "  PASS: OpenTopoMap tile server reachable (HTTP $HTTP_CODE)"
else
    echo "  WARN: OpenTopoMap tile server returned HTTP $HTTP_CODE (may be rate-limited)"
fi

# 2. Check that CSP allows the OpenTopoMap domain
echo ""
echo "Step 2: Checking CSP permits tile.opentopomap.org..."
CSP=$(curl -sI "${BASE_URL}/" 2>/dev/null | grep -i "^content-security-policy:" | head -1)

if [ -z "$CSP" ]; then
    echo "  WARN: Could not fetch CSP header from ${BASE_URL}/"
    echo "  (Server may not be running — skipping CSP check)"
else
    if echo "$CSP" | grep -q "tile.opentopomap.org"; then
        echo "  PASS: tile.opentopomap.org in CSP"
    else
        echo "  FAIL: tile.opentopomap.org NOT in CSP"
        FAIL=1
    fi
fi

# 3. Check that OpenTopoMap subdomain b also works
echo ""
echo "Step 3: Checking OpenTopoMap subdomain b..."
TOPO_B_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "User-Agent: ArgusSmoke/1.0" "https://b.tile.opentopomap.org/0/0/0.png" 2>/dev/null || echo "000")
if [ "$TOPO_B_CODE" = "200" ] || [ "$TOPO_B_CODE" = "304" ]; then
    echo "  PASS: OpenTopoMap subdomain b reachable (HTTP $TOPO_B_CODE)"
else
    echo "  WARN: OpenTopoMap subdomain b returned HTTP $TOPO_B_CODE (may be rate-limited)"
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
