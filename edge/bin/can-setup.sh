#!/bin/bash
#
# Argus CAN Bus Interface Setup Script
#
# Called by argus-can-setup.service (oneshot) at boot.
# Brings up the CAN interface with the correct bitrate.
#
# Environment variables (from /etc/argus/config.env):
#   ARGUS_CAN_INTERFACE  - CAN interface name (default: can0)
#   ARGUS_CAN_BITRATE    - CAN bus bitrate in bps (default: 500000)
#
# Exit codes:
#   0 - CAN interface configured and up
#   1 - CAN hardware not detected (degraded mode — not a fatal error)
#
# Created by EDGE-2: Power Loss Resilience — CAN Bringup

set -u

CAN_IF="${ARGUS_CAN_INTERFACE:-can0}"
CAN_BITRATE="${ARGUS_CAN_BITRATE:-500000}"

log() {
    echo "[can-setup] $1"
    logger -t argus-can-setup "$1"
}

# --- Check if CAN interface exists ---
if ! ip link show "$CAN_IF" > /dev/null 2>&1; then
    log "WARNING: CAN interface '$CAN_IF' not found. Hardware may not be connected."
    log "System will operate in degraded mode (no CAN telemetry)."
    log "Plug in a CAN adapter and run: sudo systemctl restart argus-can-setup argus-can"
    exit 1  # SuccessExitStatus includes 1, so systemd treats this as OK
fi

# --- Bring interface down first (idempotent) ---
ip link set "$CAN_IF" down 2>/dev/null || true

# --- Configure bitrate and bring up ---
if ip link set "$CAN_IF" up type can bitrate "$CAN_BITRATE"; then
    log "CAN interface '$CAN_IF' configured: bitrate=${CAN_BITRATE}, state=UP"
else
    log "ERROR: Failed to configure CAN interface '$CAN_IF' with bitrate ${CAN_BITRATE}"
    log "Check: ip -details link show $CAN_IF"
    exit 1
fi

# --- Verify interface is up ---
STATE=$(cat "/sys/class/net/${CAN_IF}/operstate" 2>/dev/null || echo "unknown")
if [ "$STATE" = "up" ] || [ "$STATE" = "unknown" ]; then
    # CAN interfaces report "unknown" as operstate when they're actually up
    log "CAN interface '$CAN_IF' is operational (operstate=$STATE)"
    exit 0
else
    log "WARNING: CAN interface '$CAN_IF' operstate is '$STATE' (expected 'up' or 'unknown')"
    exit 1
fi
