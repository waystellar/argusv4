#!/bin/bash
#
# Cloud Web Build Check
#
# Runs the web TypeScript + Vite build in the correct working directory.
# Exits non-zero on failure. Suitable for CI or manual pre-deploy checks.
#
# Usage:
#   scripts/cloud_web_build_check.sh           # Uses Docker (default)
#   scripts/cloud_web_build_check.sh --local   # Uses local Node.js
#
# Exit codes:
#   0 - Build succeeded
#   1 - Build failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"

MODE="${1:-docker}"

echo "==============================="
echo "  Argus Cloud Web Build Check"
echo "==============================="
echo "  Web dir: $WEB_DIR"
echo "  Mode:    $MODE"
echo ""

if [ ! -d "$WEB_DIR" ]; then
    echo "FAIL: Web directory not found at $WEB_DIR"
    exit 1
fi

if [ "$MODE" = "--local" ]; then
    # Local mode: requires Node.js installed
    if ! command -v node &>/dev/null; then
        echo "FAIL: Node.js not found. Install Node 20+ or use Docker mode (default)."
        exit 1
    fi

    echo "Installing dependencies..."
    cd "$WEB_DIR"
    npm install --silent 2>&1 | tail -3

    echo ""
    echo "Running tsc && vite build..."
    npm run build 2>&1

else
    # Docker mode (default): uses node:20-alpine
    if ! command -v docker &>/dev/null; then
        echo "FAIL: Docker not found. Install Docker or use --local mode."
        exit 1
    fi

    echo "Running build in Docker (node:20-alpine)..."
    docker run --rm \
        -v "$WEB_DIR:/app" \
        -w /app \
        node:20-alpine \
        sh -c "npm install --silent 2>&1 | tail -3 && npm run build 2>&1"
fi

BUILD_EXIT=$?

echo ""
if [ $BUILD_EXIT -eq 0 ]; then
    echo "==============================="
    echo "  PASS: Web build succeeded"
    echo "==============================="
else
    echo "==============================="
    echo "  FAIL: Web build failed (exit $BUILD_EXIT)"
    echo "==============================="
fi

exit $BUILD_EXIT
