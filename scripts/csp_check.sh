#!/bin/bash
#
# CSP Header Check
#
# Fetches the fan page and prints the Content-Security-Policy header.
# Verifies that required tile domains are permitted.
#
# Usage:
#   scripts/csp_check.sh                    # Default: http://localhost
#   scripts/csp_check.sh http://192.168.0.19  # Custom host
#
# Exit codes:
#   0 - CSP present and tile domains permitted
#   1 - CSP missing or tile domains not permitted

set -euo pipefail

BASE_URL="${1:-http://localhost}"
FAIL=0

echo "==============================="
echo "  Argus CSP Header Check"
echo "==============================="
echo "  URL: ${BASE_URL}/"
echo ""

# Fetch headers
HEADERS=$(curl -sI -o /dev/null -w '%{http_code}' -D - "${BASE_URL}/" 2>/dev/null || echo "CURL_FAILED")

if echo "$HEADERS" | grep -q "CURL_FAILED"; then
    echo "FAIL: Could not reach ${BASE_URL}/"
    exit 1
fi

# Extract CSP header (case-insensitive)
CSP=$(echo "$HEADERS" | grep -i "^content-security-policy:" | head -1)

if [ -z "$CSP" ]; then
    echo "FAIL: No Content-Security-Policy header found"
    exit 1
fi

echo "CSP header found:"
echo "  $CSP"
echo ""

# Check required domains
REQUIRED_DOMAINS=(
    "basemaps.cartocdn.com"
    "tile.openstreetmap.org"
)

echo "Checking required tile domains..."
for domain in "${REQUIRED_DOMAINS[@]}"; do
    if echo "$CSP" | grep -q "$domain"; then
        echo "  PASS: $domain found in CSP"
    else
        echo "  FAIL: $domain NOT found in CSP"
        FAIL=1
    fi
done

# Check required directives
echo ""
echo "Checking CSP directives..."
for directive in "img-src" "connect-src" "worker-src"; do
    if echo "$CSP" | grep -q "$directive"; then
        echo "  PASS: $directive directive present"
    else
        echo "  FAIL: $directive directive missing"
        FAIL=1
    fi
done

echo ""
echo "==============================="
if [ $FAIL -eq 0 ]; then
    echo "  PASS: CSP configured correctly"
else
    echo "  FAIL: CSP issues found"
fi
echo "==============================="

exit $FAIL
