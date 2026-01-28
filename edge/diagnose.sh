#!/bin/bash
#
# Argus Edge Diagnostic Script
# Outputs all diagnostics to a single text file
#
# Usage: sudo ./diagnose.sh
# Output: /tmp/argus_diag.txt
#

OUTPUT="/tmp/argus_diag.txt"

# Clear/create output file
> "$OUTPUT"

section() {
    echo "" >> "$OUTPUT"
    echo "================================================================================" >> "$OUTPUT"
    echo "=== $1" >> "$OUTPUT"
    echo "================================================================================" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
}

subsection() {
    echo "" >> "$OUTPUT"
    echo "--- $1 ---" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
}

run_cmd() {
    echo "\$ $1" >> "$OUTPUT"
    eval "$1" >> "$OUTPUT" 2>&1
    echo "" >> "$OUTPUT"
}

echo "Argus Edge Diagnostic Tool"
echo "Collecting diagnostics to: $OUTPUT"
echo ""

# Header
echo "ARGUS EDGE DIAGNOSTIC REPORT" >> "$OUTPUT"
echo "Generated: $(date)" >> "$OUTPUT"
echo "Hostname: $(hostname)" >> "$OUTPUT"

#------------------------------------------------------------------------------
section "1. SYSTEM INFO"
#------------------------------------------------------------------------------

subsection "OS Version"
run_cmd "cat /etc/os-release"

subsection "Kernel"
run_cmd "uname -a"

subsection "Uptime"
run_cmd "uptime"

subsection "Memory"
run_cmd "free -h"

subsection "Disk"
run_cmd "df -h /"

subsection "Network Interfaces"
run_cmd "ip addr | grep -E '^[0-9]+:|inet '"

#------------------------------------------------------------------------------
section "2. ARGUS SERVICE STATUS"
#------------------------------------------------------------------------------

for svc in argus-gps argus-can argus-uplink argus-ant argus-video argus-dashboard argus-provision; do
    subsection "Service: $svc"
    run_cmd "systemctl status $svc --no-pager -l 2>/dev/null || echo 'Service not found'"
done

subsection "All Argus Services Summary"
run_cmd "systemctl list-units 'argus-*' --no-pager --all"

#------------------------------------------------------------------------------
section "3. CONFIGURATION FILES"
#------------------------------------------------------------------------------

subsection "/etc/argus/config.env"
if [[ -f /etc/argus/config.env ]]; then
    echo "(Sensitive values redacted)" >> "$OUTPUT"
    # Show config but redact tokens
    sed 's/TOKEN=.*/TOKEN=***REDACTED***/' /etc/argus/config.env >> "$OUTPUT" 2>&1
else
    echo "FILE NOT FOUND" >> "$OUTPUT"
fi

subsection "/etc/argus/.provisioned"
if [[ -f /etc/argus/.provisioned ]]; then
    echo "EXISTS (device is provisioned)" >> "$OUTPUT"
else
    echo "NOT FOUND (device not provisioned)" >> "$OUTPUT"
fi

subsection "/opt/argus/config/ contents"
run_cmd "ls -la /opt/argus/config/ 2>/dev/null || echo 'Directory not found'"

subsection "Dashboard config.json"
run_cmd "cat /opt/argus/config/config.json 2>/dev/null | head -50 || echo 'Not found'"

subsection "Course GPX files"
run_cmd "ls -la /opt/argus/config/*.gpx 2>/dev/null || echo 'No GPX files found'"
run_cmd "ls -la /opt/argus/data/*.gpx 2>/dev/null || echo 'No GPX files in data/'"

#------------------------------------------------------------------------------
section "4. JOURNAL LOGS (Last 100 lines each)"
#------------------------------------------------------------------------------

for svc in argus-gps argus-can argus-uplink argus-ant argus-video argus-dashboard; do
    subsection "Logs: $svc"
    run_cmd "journalctl -u $svc --no-pager -n 100 2>/dev/null || echo 'No logs available'"
done

#------------------------------------------------------------------------------
section "5. HARDWARE DETECTION"
#------------------------------------------------------------------------------

subsection "GPS Device"
run_cmd "ls -la /dev/argus_gps 2>/dev/null || echo 'Symlink not found'"
run_cmd "ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo 'No USB serial devices'"

subsection "CAN Interface"
run_cmd "ip link show can0 2>/dev/null || echo 'can0 interface not found'"
run_cmd "cat /sys/class/net/can0/operstate 2>/dev/null || echo 'CAN state unknown'"

subsection "ANT+ USB"
run_cmd "lsusb 2>/dev/null | grep -i 'dynastream\|ant\|0fcf' || echo 'No ANT+ USB device detected'"

subsection "Video Devices"
run_cmd "v4l2-ctl --list-devices 2>/dev/null || echo 'v4l2-ctl not available or no devices'"
run_cmd "ls -la /dev/video* 2>/dev/null || echo 'No /dev/video* devices'"

subsection "USB Devices (all)"
run_cmd "lsusb"

#------------------------------------------------------------------------------
section "6. PYTHON ENVIRONMENT"
#------------------------------------------------------------------------------

subsection "Python Version"
run_cmd "/opt/argus/venv/bin/python --version 2>/dev/null || echo 'Venv not found'"

subsection "Key Packages"
run_cmd "/opt/argus/venv/bin/pip list 2>/dev/null | grep -E 'gpxpy|httpx|zmq|pyserial|can|openant|flask' || echo 'Cannot list packages'"

subsection "ZMQ Available"
run_cmd "/opt/argus/venv/bin/python -c 'import zmq; print(f\"ZMQ version: {zmq.zmq_version()}\")' 2>&1"

subsection "python-can Available"
run_cmd "/opt/argus/venv/bin/python -c 'import can; print(\"python-can: OK\")' 2>&1"

subsection "openant Available"
run_cmd "/opt/argus/venv/bin/python -c 'import openant; print(\"openant: OK\")' 2>&1"

#------------------------------------------------------------------------------
section "7. API ENDPOINT TESTS"
#------------------------------------------------------------------------------

DASH_URL="http://localhost:8080"

subsection "Dashboard /api/status"
run_cmd "curl -s -w '\\nHTTP: %{http_code}\\n' '$DASH_URL/api/status' 2>&1 | head -50"

subsection "Dashboard /api/course"
run_cmd "curl -s -w '\\nHTTP: %{http_code}\\n' '$DASH_URL/api/course' 2>&1 | head -50"

subsection "Dashboard /api/telemetry/current"
run_cmd "curl -s -w '\\nHTTP: %{http_code}\\n' '$DASH_URL/api/telemetry/current' 2>&1 | head -50"

subsection "Dashboard /api/cameras/status"
run_cmd "curl -s -w '\\nHTTP: %{http_code}\\n' '$DASH_URL/api/cameras/status' 2>&1 | head -50"

subsection "Dashboard /api/config"
run_cmd "curl -s -w '\\nHTTP: %{http_code}\\n' '$DASH_URL/api/config' 2>&1 | head -50"

#------------------------------------------------------------------------------
section "8. MOCK/SIMULATION DETECTION"
#------------------------------------------------------------------------------

subsection "Checking for simulation mode in logs"
echo "Searching for simulation/mock indicators..." >> "$OUTPUT"
run_cmd "journalctl -u argus-gps -n 500 --no-pager 2>/dev/null | grep -i 'simulat\|mock\|fake\|fallback' | tail -20 || echo 'None found'"
run_cmd "journalctl -u argus-can -n 500 --no-pager 2>/dev/null | grep -i 'simulat\|mock\|fake\|fallback' | tail -20 || echo 'None found'"
run_cmd "journalctl -u argus-ant -n 500 --no-pager 2>/dev/null | grep -i 'simulat\|mock\|fake\|fallback' | tail -20 || echo 'None found'"
run_cmd "journalctl -u argus-dashboard -n 500 --no-pager 2>/dev/null | grep -i 'simulat\|mock\|fake\|fallback' | tail -20 || echo 'None found'"

subsection "ZMQ Port Listeners"
run_cmd "ss -tlnp | grep -E '5556|5557|5558' || echo 'No ZMQ ports listening'"

#------------------------------------------------------------------------------
section "9. CLOUD CONNECTIVITY"
#------------------------------------------------------------------------------

subsection "Config CLOUD_URL"
CLOUD_URL=$(grep ARGUS_CLOUD_URL /etc/argus/config.env 2>/dev/null | cut -d= -f2)
echo "CLOUD_URL from config: ${CLOUD_URL:-NOT SET}" >> "$OUTPUT"

if [[ -n "$CLOUD_URL" ]]; then
    subsection "Ping Cloud Server"
    CLOUD_HOST=$(echo "$CLOUD_URL" | sed 's|https\?://||' | cut -d: -f1 | cut -d/ -f1)
    run_cmd "ping -c 3 $CLOUD_HOST 2>&1 || echo 'Ping failed'"

    subsection "Curl Cloud Health"
    run_cmd "curl -s -m 5 -w '\\nHTTP: %{http_code}\\n' '${CLOUD_URL}/health' 2>&1 || echo 'Request failed'"
fi

#------------------------------------------------------------------------------
section "10. FILE PERMISSIONS"
#------------------------------------------------------------------------------

subsection "/opt/argus/ ownership"
run_cmd "ls -la /opt/argus/"

subsection "/etc/argus/ ownership"
run_cmd "ls -la /etc/argus/"

subsection "Screenshot cache"
run_cmd "ls -la /opt/argus/cache/screenshots/ 2>/dev/null || echo 'Directory not found'"

#------------------------------------------------------------------------------
section "11. RECENT ERRORS (dmesg)"
#------------------------------------------------------------------------------

subsection "USB/Serial errors"
run_cmd "dmesg | grep -i 'usb\|tty\|serial' | tail -30"

subsection "CAN errors"
run_cmd "dmesg | grep -i 'can' | tail -20"

#------------------------------------------------------------------------------
section "END OF DIAGNOSTIC REPORT"
#------------------------------------------------------------------------------

echo "" >> "$OUTPUT"
echo "Report complete. File: $OUTPUT" >> "$OUTPUT"
echo "Size: $(wc -c < "$OUTPUT") bytes" >> "$OUTPUT"

# Done
echo ""
echo "=============================================="
echo "  DIAGNOSTIC COMPLETE"
echo "=============================================="
echo ""
echo "Output file: $OUTPUT"
echo "File size: $(wc -c < "$OUTPUT" | tr -d ' ') bytes"
echo ""
echo "To view: cat $OUTPUT"
echo "To copy: cat $OUTPUT | pbcopy  (macOS)"
echo "         cat $OUTPUT | xclip   (Linux)"
echo ""
