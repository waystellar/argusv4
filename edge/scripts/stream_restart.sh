#!/bin/bash
#
# Argus Stream Restart
#
# Safely restarts the YouTube streaming service after a "paused" state.
# Resets failure counters by restarting the argus-video systemd service.
#
# Usage:
#   sudo scripts/stream_restart.sh
#
# This is the recommended way to recover from:
#   - Auth failures (bad YouTube key)
#   - Too many consecutive failures
#   - Camera device errors
#
# Created by EDGE-6: YouTube Stream Supervisor

set -u

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

STATUS_FILE="/opt/argus/state/stream_status.json"

echo "=============================="
echo "  Argus Stream Restart"
echo "=============================="

# Show current state
if [[ -f "$STATUS_FILE" ]]; then
    STATE=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('state','unknown'))" 2>/dev/null || echo "unknown")
    echo "  Current state: $STATE"
else
    echo "  Current state: unknown (no status file)"
fi

echo ""

# Check if running as root (needed for systemctl restart)
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: Must run as root (use sudo)${NC}"
    echo "  sudo $0"
    exit 1
fi

# Restart the service
echo "Restarting argus-video service..."
systemctl restart argus-video

# Wait briefly and check
sleep 3
NEW_STATUS=$(systemctl is-active argus-video 2>/dev/null || echo "unknown")

if [[ "$NEW_STATUS" == "active" ]]; then
    echo -e "${GREEN}argus-video restarted successfully${NC}"
    echo ""
    echo "Monitor with: journalctl -u argus-video -f"
    echo "Check status: scripts/stream_status.sh"
else
    echo -e "${RED}argus-video failed to start (status: $NEW_STATUS)${NC}"
    echo ""
    echo "Check logs: journalctl -u argus-video -n 20 --no-pager"
    exit 1
fi

echo ""
echo "=============================="
