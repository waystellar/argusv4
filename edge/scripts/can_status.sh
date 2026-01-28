#!/bin/bash
#
# Argus CAN Status Script
#
# Prints the current state of the CAN interface and argus-can service.
# Designed for quick triage — run from SSH or pit crew dashboard.
#
# Usage:
#   ./scripts/can_status.sh
#   sudo ./scripts/can_status.sh   (for full ip link details)
#
# Created by EDGE-2: Power Loss Resilience — CAN Bringup

set -u

CAN_IF="${ARGUS_CAN_INTERFACE:-can0}"

echo "=============================="
echo "  Argus CAN Status Report"
echo "=============================="
echo ""

# --- Interface existence ---
echo "--- Interface: $CAN_IF ---"
if ip link show "$CAN_IF" > /dev/null 2>&1; then
    echo "[OK] Interface '$CAN_IF' exists"

    # Operstate
    STATE=$(cat "/sys/class/net/${CAN_IF}/operstate" 2>/dev/null || echo "unknown")
    echo "     operstate: $STATE"

    # Detailed link info (bitrate, etc)
    echo ""
    echo "--- ip -details link show $CAN_IF ---"
    ip -details link show "$CAN_IF" 2>/dev/null || echo "(requires root for full details)"

    # Stats
    echo ""
    echo "--- Interface Statistics ---"
    if [ -f "/sys/class/net/${CAN_IF}/statistics/rx_packets" ]; then
        RX=$(cat "/sys/class/net/${CAN_IF}/statistics/rx_packets")
        TX=$(cat "/sys/class/net/${CAN_IF}/statistics/tx_packets")
        RX_ERR=$(cat "/sys/class/net/${CAN_IF}/statistics/rx_errors")
        TX_ERR=$(cat "/sys/class/net/${CAN_IF}/statistics/tx_errors")
        echo "  RX packets: $RX  (errors: $RX_ERR)"
        echo "  TX packets: $TX  (errors: $TX_ERR)"
    else
        echo "  (statistics not available)"
    fi
else
    echo "[MISSING] Interface '$CAN_IF' not found"
    echo ""
    echo "Possible causes:"
    echo "  - CAN adapter not plugged in"
    echo "  - USB hub not powered"
    echo "  - Driver not loaded (check: lsmod | grep can)"
    echo ""
    echo "Available network interfaces:"
    ip link show 2>/dev/null | grep -E "^[0-9]+" | awk '{print "  " $2}' | sed 's/://'
fi

# --- Systemd services ---
echo ""
echo "--- Systemd Services ---"
for svc in argus-can-setup argus-can; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
    ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not-found")
    case "$STATUS" in
        active)     ICON="[OK]" ;;
        inactive)   ICON="[--]" ;;
        failed)     ICON="[FAIL]" ;;
        *)          ICON="[??]" ;;
    esac
    echo "$ICON $svc: $STATUS (enabled: $ENABLED)"
done

# --- Recent journal entries ---
echo ""
echo "--- Recent CAN Logs (last 10 lines) ---"
journalctl -u argus-can-setup -u argus-can --no-pager -n 10 --no-hostname 2>/dev/null || echo "(journalctl not available)"

echo ""
echo "=============================="
echo "  End CAN Status Report"
echo "=============================="
