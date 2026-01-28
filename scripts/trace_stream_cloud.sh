#!/bin/bash
#
# Argus v4 - Cloud Stream Control Trace
#
# Tails cloud API logs and highlights stream control events:
# - STREAM_CONTROL log entries
# - start_stream / stop_stream commands
# - Edge ACK responses
# - Camera selection
#
# Usage: ./scripts/trace_stream_cloud.sh [--save]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/artifacts/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${LOG_DIR}/${TIMESTAMP}_trace_stream_cloud.txt"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

SAVE_TO_FILE=false
if [ "$1" = "--save" ]; then
    SAVE_TO_FILE=true
fi

echo "============================================================"
echo "  Argus Cloud Stream Control Trace"
echo "============================================================"
echo ""
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Container: argus-api"
echo ""
echo "Filtering for:"
echo "  - [STREAM_CONTROL] log entries"
echo "  - start_stream / stop_stream commands"
echo "  - edge ACK / response events"
echo "  - camera / source selection"
echo ""
if [ "$SAVE_TO_FILE" = true ]; then
    echo "Output file: $OUTPUT_FILE"
    echo ""
fi
echo "Press Ctrl+C to stop"
echo "============================================================"
echo ""

# Colors for highlighting (when not saving to file)
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
            -e "s/(STREAM_CONTROL)/$(printf "${CYAN}")\\1$(printf "${NC}")/g" \
            -e "s/(START_STREAM|start_stream)/$(printf "${GREEN}")\\1$(printf "${NC}")/g" \
            -e "s/(STOP_STREAM|stop_stream)/$(printf "${RED}")\\1$(printf "${NC}")/g" \
            -e "s/(EDGE_RESPONSE|edge.?response|ACK)/$(printf "${YELLOW}")\\1$(printf "${NC}")/gi" \
            -e "s/(STREAMING|STARTING|STOPPING|IDLE|ERROR)/$(printf "${BLUE}")\\1$(printf "${NC}")/g" \
            -e "s/(camera|source_id)([=:]['\"]?[a-z_]+)/$(printf "${CYAN}")\\1\\2$(printf "${NC}")/gi" \
            -e "s/(command_id[=:]['\"]?cmd_[a-z0-9]+)/$(printf "${YELLOW}")\\1$(printf "${NC}")/gi"
    fi
}

# Filter pattern for stream control related logs
FILTER_PATTERN="STREAM_CONTROL|stream_control|start_stream|stop_stream|camera|source_id|streaming|STREAMING|STARTING|STOPPING|IDLE|edge.*response|command_id"

if [ "$SAVE_TO_FILE" = true ]; then
    # Save header to file
    {
        echo "============================================================"
        echo "  Argus Cloud Stream Control Trace"
        echo "============================================================"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Container: argus-api"
        echo ""
    } > "$OUTPUT_FILE"

    # Tail logs, filter, and save
    docker logs argus-api --tail 100 -f 2>&1 | \
        grep -E --line-buffered "$FILTER_PATTERN" | \
        tee -a "$OUTPUT_FILE"
else
    # Tail logs, filter, and highlight
    docker logs argus-api --tail 100 -f 2>&1 | \
        grep -E --line-buffered "$FILTER_PATTERN" | \
        highlight
fi
