#!/bin/bash
#
# Argus v4 - Edge Stream Control Trace
#
# Tails edge device logs and highlights stream control events.
# Works with both systemd services (real edge) and Docker containers (dev).
#
# Usage: ./scripts/trace_stream_edge.sh [--save] [--docker]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/artifacts/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${LOG_DIR}/${TIMESTAMP}_trace_stream_edge.txt"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

SAVE_TO_FILE=false
USE_DOCKER=false

for arg in "$@"; do
    case $arg in
        --save) SAVE_TO_FILE=true ;;
        --docker) USE_DOCKER=true ;;
    esac
done

echo "============================================================"
echo "  Argus Edge Stream Control Trace"
echo "============================================================"
echo ""
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "Filtering for:"
echo "  - stream / ffmpeg commands"
echo "  - camera selection"
echo "  - command receive / ACK"
echo "  - youtube / rtmp"
echo ""
if [ "$SAVE_TO_FILE" = true ]; then
    echo "Output file: $OUTPUT_FILE"
    echo ""
fi
echo "Press Ctrl+C to stop"
echo "============================================================"
echo ""

# Colors for highlighting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

highlight() {
    if [ "$SAVE_TO_FILE" = true ]; then
        cat
    else
        sed -E \
            -e "s/(start_stream|starting stream)/$(printf "${GREEN}")\\1$(printf "${NC}")/gi" \
            -e "s/(stop_stream|stopping stream)/$(printf "${RED}")\\1$(printf "${NC}")/gi" \
            -e "s/(command.*received|receive.*command)/$(printf "${YELLOW}")\\1$(printf "${NC}")/gi" \
            -e "s/(ACK|acknowledge|success)/$(printf "${GREEN}")\\1$(printf "${NC}")/gi" \
            -e "s/(error|fail|failed)/$(printf "${RED}")\\1$(printf "${NC}")/gi" \
            -e "s/(ffmpeg|gstreamer)/$(printf "${CYAN}")\\1$(printf "${NC}")/gi" \
            -e "s/(camera|video[0-9]+)/$(printf "${BLUE}")\\1$(printf "${NC}")/gi" \
            -e "s/(youtube|rtmp)/$(printf "${CYAN}")\\1$(printf "${NC}")/gi" \
            -e "s/(command_id[=:]['\"]?cmd_[a-z0-9]+)/$(printf "${YELLOW}")\\1$(printf "${NC}")/gi"
    fi
}

# Filter pattern for stream-related logs
FILTER_PATTERN="stream|camera|video|ffmpeg|gstreamer|rtmp|youtube|command|ACK|acknowledge"

# Determine log source
if [ "$USE_DOCKER" = true ]; then
    LOG_SOURCE="Docker (argus-edge or simulator)"

    # Check if argus-edge container exists, else try to find simulator
    if docker ps -q -f name=argus-edge 2>/dev/null | grep -q .; then
        CONTAINER="argus-edge"
    else
        echo "Note: argus-edge container not found."
        echo "Looking for edge simulator processes..."
        echo ""

        # For dev, edge logs might come from simulator running locally
        echo "To trace edge simulator, run it with:"
        echo "  python edge/simulator.py --api-url http://localhost:8000 --vehicles 1 2>&1 | tee edge.log"
        echo ""
        exit 0
    fi

    if [ "$SAVE_TO_FILE" = true ]; then
        {
            echo "============================================================"
            echo "  Argus Edge Stream Control Trace"
            echo "============================================================"
            echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Source: Docker container $CONTAINER"
            echo ""
        } > "$OUTPUT_FILE"

        docker logs "$CONTAINER" --tail 100 -f 2>&1 | \
            grep -E --line-buffered -i "$FILTER_PATTERN" | \
            tee -a "$OUTPUT_FILE"
    else
        docker logs "$CONTAINER" --tail 100 -f 2>&1 | \
            grep -E --line-buffered -i "$FILTER_PATTERN" | \
            highlight
    fi
else
    # Real edge device with systemd services
    LOG_SOURCE="Systemd (argus-video service)"

    if ! systemctl is-active --quiet argus-video 2>/dev/null; then
        echo "Note: argus-video service not running on this machine."
        echo ""
        echo "This script is designed to run on an edge device with:"
        echo "  - argus-video systemd service"
        echo "  - argus-uplink systemd service"
        echo ""
        echo "For development, use: ./scripts/trace_stream_edge.sh --docker"
        echo ""
        exit 0
    fi

    if [ "$SAVE_TO_FILE" = true ]; then
        {
            echo "============================================================"
            echo "  Argus Edge Stream Control Trace"
            echo "============================================================"
            echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Source: Systemd services"
            echo ""
        } > "$OUTPUT_FILE"

        journalctl -u argus-video -u argus-uplink -f --no-pager 2>&1 | \
            grep -E --line-buffered -i "$FILTER_PATTERN" | \
            tee -a "$OUTPUT_FILE"
    else
        journalctl -u argus-video -u argus-uplink -f --no-pager 2>&1 | \
            grep -E --line-buffered -i "$FILTER_PATTERN" | \
            highlight
    fi
fi
