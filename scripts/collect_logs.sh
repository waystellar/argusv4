#!/bin/bash
#
# Log Collection Script for Argus v4
#
# Collects logs from all services for debugging and regression testing.
# Outputs to stdout or a file.
#
# Usage:
#   ./scripts/collect_logs.sh [output_file]
#
# If no output file specified, logs are printed to stdout.

OUTPUT_FILE="${1:-}"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

echo "=========================================="
echo "  Argus v4 Log Collection"
echo "  Timestamp: ${TIMESTAMP}"
echo "=========================================="
echo ""

# Function to collect and output logs
collect() {
    local section=$1
    local command=$2
    
    echo "=== ${section} ==="
    echo ""
    eval "$command" 2>&1 || echo "(No output or command failed)"
    echo ""
}

# Collect Docker container logs if running
if command -v docker &> /dev/null; then
    echo "--- Docker Containers ---"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "(Docker not running or no containers)"
    echo ""
    
    # Collect logs from argus containers
    for container in $(docker ps --format "{{.Names}}" 2>/dev/null | grep -i argus || true); do
        collect "Docker: $container (last 50 lines)" "docker logs --tail 50 $container"
    done
fi

# Check for local process logs
echo "--- Local Processes ---"
if command -v pgrep &> /dev/null; then
    echo "Python processes:"
    pgrep -af "python.*uvicorn\|python.*fastapi" 2>/dev/null || echo "(None running)"
    echo ""
    echo "Node processes:"
    pgrep -af "node.*vite\|npm.*dev" 2>/dev/null || echo "(None running)"
    echo ""
fi

# Check log files if they exist
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "--- Log Files ---"
for logfile in "${PROJECT_DIR}/logs/"*.log "${PROJECT_DIR}/cloud/"*.log; do
    if [ -f "$logfile" ]; then
        collect "File: $logfile (last 30 lines)" "tail -30 '$logfile'"
    fi
done

# System info
echo "--- System Info ---"
echo "Date: $(date)"
echo "User: $(whoami)"
echo "Working Dir: $(pwd)"
echo "Node Version: $(node --version 2>/dev/null || echo 'Not installed')"
echo "Python Version: $(python3 --version 2>/dev/null || echo 'Not installed')"
echo ""

# If output file specified, redirect everything
if [ -n "$OUTPUT_FILE" ]; then
    exec > "$OUTPUT_FILE" 2>&1
    echo "Logs saved to: $OUTPUT_FILE"
fi

echo "=========================================="
echo "  Log collection complete"
echo "=========================================="
