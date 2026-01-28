#!/bin/bash
#
# Argus Edge Health Check
#
# Quick pass/fail check of all edge subsystems.
# Returns exit 0 if all Tier 1 systems are healthy, exit 1 otherwise.
# Designed for automated monitoring and manual triage.
#
# Usage:
#   ./scripts/edge_health_check.sh
#   ./scripts/edge_health_check.sh --verbose
#
# Exit codes:
#   0 - All Tier 1 systems healthy (Tier 2/3 may be degraded)
#   1 - One or more Tier 1 systems failed
#
# Created by EDGE-2: Power Loss Resilience
# Updated by EDGE-3: Device presence checks, last-sample timestamps,
#                     crash vs missing distinction

set -u

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]] || [[ "${1:-}" == "-v" ]]; then
    VERBOSE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TIER1_FAIL=0
TIER2_FAIL=0
CHECK=0

pass() {
    CHECK=$((CHECK + 1))
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    CHECK=$((CHECK + 1))
    echo -e "${RED}[FAIL]${NC} $1"
}

warn() {
    CHECK=$((CHECK + 1))
    echo -e "${YELLOW}[WARN]${NC} $1"
}

tier1_fail() {
    fail "$1"
    TIER1_FAIL=$((TIER1_FAIL + 1))
}

tier2_fail() {
    warn "$1 (degraded)"
    TIER2_FAIL=$((TIER2_FAIL + 1))
}

echo "======================================"
echo "  Argus Edge Health Check"
echo "  $(date)"
echo "======================================"
echo ""

# ============================================================
echo "--- Tier 1: Must Have ---"
# ============================================================

# 1. Pit Crew Dashboard reachable
DASHBOARD_PORT="${ARGUS_DASHBOARD_PORT:-8080}"
if curl -sf -o /dev/null -m 3 "http://localhost:${DASHBOARD_PORT}/" 2>/dev/null; then
    pass "Pit Crew Dashboard reachable (port ${DASHBOARD_PORT})"
else
    tier1_fail "Pit Crew Dashboard NOT reachable (port ${DASHBOARD_PORT})"
fi

# 2. GPS service running
# EDGE-3: Distinguish missing-hardware from service-crash
GPS_ACTIVE=$(systemctl is-active argus-gps 2>/dev/null || echo "not-found")
if [ "$GPS_ACTIVE" = "active" ]; then
    pass "GPS service running"
elif [ "$GPS_ACTIVE" = "failed" ]; then
    GPS_RESULT=$(systemctl show argus-gps --property=Result 2>/dev/null || echo "")
    if echo "$GPS_RESULT" | grep -q "start-limit-hit"; then
        tier1_fail "GPS service CRASHED (hit restart limit — likely bug, not hw)"
    else
        tier1_fail "GPS service FAILED ($GPS_RESULT)"
    fi
else
    tier1_fail "GPS service NOT running (status: $GPS_ACTIVE)"
fi

# 3. Uplink service running
# EDGE-7: Uplink runs independently of GPS — it queues whatever data is available.
# If GPS is missing, uplink still sends CAN/ANT data.
if systemctl is-active argus-uplink > /dev/null 2>&1; then
    pass "Uplink service running (independent of GPS)"
else
    tier1_fail "Uplink service NOT running"
fi

# 4. Provisioned
if [ -f /etc/argus/.provisioned ]; then
    pass "Device provisioned"
else
    tier1_fail "Device NOT provisioned (/etc/argus/.provisioned missing)"
fi

# 5. Config file exists and is non-empty
if [ -s /etc/argus/config.env ]; then
    pass "Config file present (/etc/argus/config.env)"
else
    tier1_fail "Config file missing or empty"
fi

echo ""

# ============================================================
echo "--- Tier 2: Should Have ---"
# ============================================================

# 6. CAN setup completed
CAN_IF="${ARGUS_CAN_INTERFACE:-can0}"
if systemctl is-active argus-can-setup > /dev/null 2>&1; then
    # Oneshot with RemainAfterExit=yes shows as "active" when it succeeded
    pass "CAN interface setup completed (argus-can-setup)"
else
    SETUP_STATUS=$(systemctl is-active argus-can-setup 2>/dev/null || echo "not-found")
    if [ "$SETUP_STATUS" = "inactive" ]; then
        tier2_fail "CAN interface setup inactive (hardware may be missing)"
    else
        tier2_fail "CAN interface setup: $SETUP_STATUS"
    fi
fi

# 7. CAN interface up
if ip link show "$CAN_IF" > /dev/null 2>&1; then
    STATE=$(cat "/sys/class/net/${CAN_IF}/operstate" 2>/dev/null || echo "unknown")
    if [ "$STATE" = "up" ] || [ "$STATE" = "unknown" ]; then
        pass "CAN interface '$CAN_IF' is up (operstate=$STATE)"
    else
        tier2_fail "CAN interface '$CAN_IF' operstate=$STATE"
    fi
else
    tier2_fail "CAN interface '$CAN_IF' not found"
fi

# 8. CAN telemetry service running
if systemctl is-active argus-can > /dev/null 2>&1; then
    pass "CAN telemetry service running"
else
    tier2_fail "CAN telemetry service NOT running"
fi

# 9. ANT+ service running
# EDGE-3: Distinguish missing-hardware from service-crash
ANT_ACTIVE=$(systemctl is-active argus-ant 2>/dev/null || echo "not-found")
if [ "$ANT_ACTIVE" = "active" ]; then
    pass "ANT+ heart rate service running"
elif [ "$ANT_ACTIVE" = "failed" ]; then
    ANT_RESULT=$(systemctl show argus-ant --property=Result 2>/dev/null || echo "")
    if echo "$ANT_RESULT" | grep -q "start-limit-hit"; then
        tier2_fail "ANT+ service CRASHED (hit restart limit)"
    else
        tier2_fail "ANT+ service FAILED ($ANT_RESULT)"
    fi
else
    tier2_fail "ANT+ heart rate service NOT running (status: $ANT_ACTIVE)"
fi

# 10. Video director running
# EDGE-3: Distinguish missing-hardware from service-crash
VIDEO_ACTIVE=$(systemctl is-active argus-video 2>/dev/null || echo "not-found")
if [ "$VIDEO_ACTIVE" = "active" ]; then
    pass "Video director service running"
elif [ "$VIDEO_ACTIVE" = "failed" ]; then
    VIDEO_RESULT=$(systemctl show argus-video --property=Result 2>/dev/null || echo "")
    if echo "$VIDEO_RESULT" | grep -q "start-limit-hit"; then
        tier2_fail "Video director CRASHED (hit restart limit)"
    else
        tier2_fail "Video director FAILED ($VIDEO_RESULT)"
    fi
else
    tier2_fail "Video director service NOT running (status: $VIDEO_ACTIVE)"
fi

# 11. At least one camera detected
CAMERA_COUNT=$(ls /dev/video* 2>/dev/null | wc -l)
if [ "$CAMERA_COUNT" -ge 1 ]; then
    pass "Camera(s) detected: $CAMERA_COUNT video devices"
    if [ "$CAMERA_COUNT" -lt 4 ]; then
        warn "  (expected 4 cameras, found $CAMERA_COUNT — partial coverage)"
    fi
else
    tier2_fail "No cameras detected (/dev/video* empty)"
fi

echo ""

# ============================================================
echo "--- Device Presence (EDGE-3) ---"
# ============================================================

# GPS device
GPS_DEV="/dev/argus_gps"
GPS_FOUND=false
for dev in "$GPS_DEV" /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyACM0 /dev/ttyACM1; do
    if [ -e "$dev" ]; then
        pass "GPS device present: $dev"
        GPS_FOUND=true
        break
    fi
done
if ! $GPS_FOUND; then
    warn "GPS device not detected (checked $GPS_DEV, ttyUSB*, ttyACM*)"
fi

# ANT+ USB stick (Dynastream vendor 0fcf)
if lsusb -d 0fcf: > /dev/null 2>&1; then
    ANT_DEV=$(lsusb -d 0fcf: 2>/dev/null | head -1)
    pass "ANT+ USB stick detected: $ANT_DEV"
else
    warn "ANT+ USB stick not detected (vendor 0fcf)"
fi

# CAN interface
CAN_IF="${ARGUS_CAN_INTERFACE:-can0}"
if ip link show "$CAN_IF" > /dev/null 2>&1; then
    CAN_STATE=$(cat "/sys/class/net/${CAN_IF}/operstate" 2>/dev/null || echo "unknown")
    pass "CAN interface '$CAN_IF' present (operstate=$CAN_STATE)"
else
    warn "CAN interface '$CAN_IF' not present"
fi

# Video devices
VIDEO_COUNT=$(ls /dev/video* 2>/dev/null | wc -l)
if [ "$VIDEO_COUNT" -gt 0 ]; then
    pass "Video devices: $VIDEO_COUNT found"
else
    warn "No video devices detected"
fi

# Audio device
if [ -d /proc/asound ] && ls /proc/asound/card* > /dev/null 2>&1; then
    AUDIO_COUNT=$(ls -d /proc/asound/card* 2>/dev/null | wc -l)
    pass "Audio devices: $AUDIO_COUNT sound card(s)"
else
    warn "No audio devices detected"
fi

echo ""

# ============================================================
echo "--- Last Sample Timestamps (EDGE-3) ---"
# ============================================================

# Try to get last sample timestamps from the dashboard API
DASHBOARD_PORT="${ARGUS_DASHBOARD_PORT:-8080}"
TELEM_JSON=$(curl -sf -m 3 "http://localhost:${DASHBOARD_PORT}/api/telemetry/current" 2>/dev/null || echo "")
if [ -n "$TELEM_JSON" ]; then
    NOW_MS=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo "0")
    # GPS timestamp
    GPS_TS=$(echo "$TELEM_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('gps_ts_ms',0))" 2>/dev/null || echo "0")
    if [ "$GPS_TS" -gt 0 ] 2>/dev/null; then
        GPS_AGE=$(( (${NOW_MS:-0} - GPS_TS) / 1000 ))
        if [ "$GPS_AGE" -lt 10 ]; then
            pass "GPS last sample: ${GPS_AGE}s ago (fresh)"
        elif [ "$GPS_AGE" -lt 60 ]; then
            warn "GPS last sample: ${GPS_AGE}s ago (stale)"
        else
            warn "GPS last sample: ${GPS_AGE}s ago (very stale)"
        fi
    else
        warn "GPS: no sample timestamp available"
    fi
    # CAN timestamp
    CAN_TS=$(echo "$TELEM_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('last_update_ms',0))" 2>/dev/null || echo "0")
    if [ "$CAN_TS" -gt 0 ] 2>/dev/null; then
        CAN_AGE=$(( (${NOW_MS:-0} - CAN_TS) / 1000 ))
        if [ "$CAN_AGE" -lt 10 ]; then
            pass "CAN last sample: ${CAN_AGE}s ago (fresh)"
        elif [ "$CAN_AGE" -lt 60 ]; then
            warn "CAN last sample: ${CAN_AGE}s ago (stale)"
        else
            warn "CAN last sample: ${CAN_AGE}s ago (very stale)"
        fi
    else
        warn "CAN: no sample timestamp available"
    fi
    # ANT+ — check heart_rate > 0 as proxy
    ANT_HR=$(echo "$TELEM_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('heart_rate',0))" 2>/dev/null || echo "0")
    if [ "$ANT_HR" -gt 0 ] 2>/dev/null; then
        pass "ANT+ heart rate: ${ANT_HR} BPM (active)"
    else
        warn "ANT+ heart rate: no data (0 BPM)"
    fi
    # Device statuses
    GPS_DS=$(echo "$TELEM_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('gps_device_status','unknown'))" 2>/dev/null || echo "unknown")
    CAN_DS=$(echo "$TELEM_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('can_device_status','unknown'))" 2>/dev/null || echo "unknown")
    ANT_DS=$(echo "$TELEM_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ant_device_status','unknown'))" 2>/dev/null || echo "unknown")
    echo "  Device status — GPS: $GPS_DS | CAN: $CAN_DS | ANT+: $ANT_DS"
else
    warn "Could not reach dashboard API for telemetry timestamps"
fi

echo ""

# ============================================================
echo "--- Tier 3: System Resources ---"
# ============================================================

# 12. Disk space
# EDGE-5: Critical disk usage (>=95%) is a Tier 1 failure — system may crash.
#          High usage (>=85%) is a warning. Below 85% is healthy.
DISK_PCT=$(df /opt/argus 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
if [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -ge 95 ]; then
    tier1_fail "Disk usage CRITICAL: ${DISK_PCT}% (system at risk of failure)"
elif [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -ge 85 ]; then
    warn "Disk usage: ${DISK_PCT}% (high — check logs and queue)"
elif [ -n "$DISK_PCT" ]; then
    pass "Disk usage: ${DISK_PCT}% (healthy)"
else
    warn "Could not check disk usage"
fi

# 13. SQLite queue size
# EDGE-5: Show queue depth and byte size from state file
QUEUE_DB="/opt/argus/data/queue.db"
QUEUE_STATUS_FILE="/opt/argus/state/queue_status.json"
if [ -f "$QUEUE_STATUS_FILE" ]; then
    Q_DEPTH=$(python3 -c "import json; print(json.load(open('$QUEUE_STATUS_FILE')).get('depth',0))" 2>/dev/null || echo "?")
    Q_MB=$(python3 -c "import json; print(json.load(open('$QUEUE_STATUS_FILE')).get('db_mb',0))" 2>/dev/null || echo "?")
    Q_CONNECTED=$(python3 -c "import json; print(json.load(open('$QUEUE_STATUS_FILE')).get('cloud_connected',False))" 2>/dev/null || echo "?")
    if [ "$Q_CONNECTED" = "True" ]; then
        pass "Uplink queue: ${Q_DEPTH} records (${Q_MB} MB) — cloud connected"
    else
        warn "Uplink queue: ${Q_DEPTH} records (${Q_MB} MB) — cloud DISCONNECTED (queuing)"
    fi
elif [ -f "$QUEUE_DB" ]; then
    QUEUE_SIZE=$(du -h "$QUEUE_DB" 2>/dev/null | awk '{print $1}')
    pass "Uplink queue exists (size: $QUEUE_SIZE)"
else
    pass "Uplink queue not yet created (normal on first boot)"
fi

# 14. System uptime
UPTIME=$(uptime -p 2>/dev/null || uptime)
pass "System uptime: $UPTIME"

# ============================================================
# Verbose: show service statuses
# ============================================================
if $VERBOSE; then
    echo ""
    echo "--- All Argus Services ---"
    for svc in argus-provision argus-gps argus-can-setup argus-can argus-uplink argus-ant argus-dashboard argus-video; do
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
        ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not-found")
        printf "  %-25s active=%-10s enabled=%s\n" "$svc" "$STATUS" "$ENABLED"
    done
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "======================================"
echo "  Summary: ${CHECK} checks run"
echo "======================================"

if [ "$TIER1_FAIL" -gt 0 ]; then
    echo -e "${RED}FAIL: $TIER1_FAIL Tier 1 failures (system not operational)${NC}"
    if [ "$TIER2_FAIL" -gt 0 ]; then
        echo -e "${YELLOW}WARN: $TIER2_FAIL Tier 2 items degraded${NC}"
    fi
    exit 1
elif [ "$TIER2_FAIL" -gt 0 ]; then
    echo -e "${YELLOW}DEGRADED: All Tier 1 OK, but $TIER2_FAIL Tier 2 items degraded${NC}"
    echo "System is operational with reduced capability."
    exit 0
else
    echo -e "${GREEN}ALL OK: System fully operational${NC}"
    exit 0
fi
