#!/bin/bash
# Argus Device Wait Script
#
# Polls for a device/interface to appear before starting the real service.
# Uses exponential backoff (5s → 10s → 20s → 30s cap) to avoid thrashing
# CPU/logs when hardware is missing.
#
# Usage:
#   device-wait.sh <device_type> <device_path> [max_wait_secs]
#
# device_type:
#   serial  — waits for a character device (e.g. /dev/ttyUSB0)
#   usb     — waits for a USB vendor:product via lsusb (e.g. 0fcf:1008)
#   net     — waits for a network interface (e.g. can0)
#   file    — waits for any file/device node to exist
#   video   — waits for at least one /dev/videoN device
#
# Exit codes:
#   0 — device found
#   1 — timed out (max_wait reached), device not found
#   2 — usage error
#
# Designed to be called as ExecStartPre= in systemd units.
# If it exits 1, use RestartPreventExitStatus=1 to prevent thrash-restart
# and instead enter a "waiting for device" state.
#
# Created by EDGE-3: Stop Thrashing — Hardware-Missing vs Service-Crash

set -u

DEVICE_TYPE="${1:-}"
DEVICE_PATH="${2:-}"
MAX_WAIT="${3:-300}"  # Default: wait up to 5 minutes, then give up

if [[ -z "$DEVICE_TYPE" || -z "$DEVICE_PATH" ]]; then
    echo "Usage: device-wait.sh <device_type> <device_path> [max_wait_secs]"
    echo "  device_type: serial | usb | net | file | video"
    exit 2
fi

log() {
    echo "[device-wait] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

# Check if device is present based on type
check_device() {
    case "$DEVICE_TYPE" in
        serial|file)
            [[ -e "$DEVICE_PATH" ]]
            ;;
        usb)
            # DEVICE_PATH is vendor:product (e.g. 0fcf:1008)
            lsusb -d "$DEVICE_PATH" > /dev/null 2>&1
            ;;
        net)
            ip link show "$DEVICE_PATH" > /dev/null 2>&1
            ;;
        video)
            # Check if any /dev/videoN exists
            ls /dev/video* > /dev/null 2>&1
            ;;
        *)
            log "ERROR: Unknown device type '$DEVICE_TYPE'"
            exit 2
            ;;
    esac
}

# Quick check first — fast path if device is already present
if check_device; then
    log "Device present: $DEVICE_TYPE=$DEVICE_PATH"
    exit 0
fi

log "Device not found: $DEVICE_TYPE=$DEVICE_PATH — entering wait loop (max ${MAX_WAIT}s)"

ELAPSED=0
SLEEP=5  # Start at 5 seconds

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    sleep "$SLEEP"
    ELAPSED=$((ELAPSED + SLEEP))

    if check_device; then
        log "Device appeared after ${ELAPSED}s: $DEVICE_TYPE=$DEVICE_PATH"
        exit 0
    fi

    # Log at reasonable intervals (not every 5s — use the backoff interval)
    log "Still waiting for $DEVICE_TYPE=$DEVICE_PATH (${ELAPSED}/${MAX_WAIT}s)"

    # Exponential backoff: 5 → 10 → 20 → 30 (cap)
    SLEEP=$((SLEEP * 2))
    if [[ $SLEEP -gt 30 ]]; then
        SLEEP=30
    fi
done

log "TIMEOUT: Device not found after ${MAX_WAIT}s: $DEVICE_TYPE=$DEVICE_PATH"
exit 1
