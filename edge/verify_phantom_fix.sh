#!/bin/bash
#
# Phantom Telemetry Fix Verification Script
#
# This script verifies that the phantom telemetry fix is working correctly.
# Run this on the edge device after deploying the updated services.
#
# Usage: bash verify_phantom_fix.sh
#

set -e

echo "========================================"
echo "  Phantom Telemetry Fix Verification"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Temporary files to capture ZMQ output
CAN_OUTPUT="/tmp/verify_can_output.json"
ANT_OUTPUT="/tmp/verify_ant_output.json"

# ========================================
# Test 1: Check CAN service doesn't auto-simulate
# ========================================
echo "Test 1: CAN Service - No Auto-Simulation"
echo "-----------------------------------------"

# Check if CAN service is running
if systemctl is-active --quiet argus-can 2>/dev/null; then
    info "argus-can service is running"

    # Check recent logs for mock mode warnings
    if journalctl -u argus-can --since "1 min ago" 2>/dev/null | grep -q "MOCK MODE ACTIVE"; then
        fail "CAN service is running in MOCK MODE (should only happen with --mock flag)"
        echo "     Check if systemd service file has --mock flag"
    else
        # Check for error messages about CAN connection (expected when no hardware)
        if journalctl -u argus-can --since "1 min ago" 2>/dev/null | grep -q "Failed to connect to CAN\|Cannot read CAN data"; then
            pass "CAN service correctly reports hardware not connected (no phantom data)"
        else
            info "CAN service may have connected to real hardware or is starting up"
        fi
    fi
else
    info "argus-can service not running"
fi

echo ""

# ========================================
# Test 2: Check ANT+ service doesn't auto-simulate
# ========================================
echo "Test 2: ANT+ Service - No Auto-Simulation"
echo "------------------------------------------"

if systemctl is-active --quiet argus-ant 2>/dev/null; then
    info "argus-ant service is running"

    # Check recent logs for simulation mode warnings
    if journalctl -u argus-ant --since "1 min ago" 2>/dev/null | grep -q "SIMULATION MODE ACTIVE"; then
        fail "ANT+ service is running in SIMULATION MODE (should only happen with --simulate flag)"
        echo "     Check if systemd service file has --simulate flag"
    else
        # Check for error messages about ANT+ not available (expected when no hardware)
        if journalctl -u argus-ant --since "1 min ago" 2>/dev/null | grep -q "OpenANT library not installed\|ANT+ error\|Cannot read ANT+"; then
            pass "ANT+ service correctly reports hardware not connected (no phantom data)"
        else
            info "ANT+ service may have connected to real hardware or is starting up"
        fi
    fi
else
    info "argus-ant service not running"
fi

echo ""

# ========================================
# Test 3: Check data_valid flags in ZMQ output
# ========================================
echo "Test 3: ZMQ Output - data_valid Flags"
echo "--------------------------------------"

# Python script to capture one ZMQ message from each service
python3 << 'PYEOF'
import zmq
import json
import sys

def capture_zmq_message(port, timeout_ms=3000):
    """Capture one message from a ZMQ port, return parsed JSON or None."""
    ctx = zmq.Context()
    sock = ctx.socket(zmq.SUB)
    sock.setsockopt(zmq.RCVTIMEO, timeout_ms)
    sock.setsockopt_string(zmq.SUBSCRIBE, "")
    sock.connect(f"tcp://localhost:{port}")

    try:
        parts = sock.recv_multipart()
        if len(parts) >= 2:
            return json.loads(parts[1].decode())
        return json.loads(parts[0].decode())
    except zmq.Again:
        return None
    except Exception as e:
        return {"error": str(e)}
    finally:
        sock.close()
        ctx.term()

# Test CAN (port 5557)
print("Checking CAN ZMQ (port 5557)...")
can_data = capture_zmq_message(5557)
if can_data:
    if "error" in can_data:
        print(f"  ERROR: {can_data['error']}")
    else:
        data_valid = can_data.get("data_valid", "MISSING")
        is_simulated = can_data.get("is_simulated", "MISSING")
        rpm = can_data.get("rpm")
        print(f"  data_valid: {data_valid}")
        print(f"  is_simulated: {is_simulated}")
        print(f"  rpm: {rpm}")

        if data_valid == "MISSING":
            print("  FAIL: data_valid field missing - old service version?")
        elif data_valid is False and rpm is None:
            print("  PASS: No hardware - data_valid=False, rpm=null")
        elif data_valid is True and is_simulated is True:
            print("  INFO: Mock mode active (--mock flag)")
        elif data_valid is True and is_simulated is False:
            print("  PASS: Real CAN data detected")
        else:
            print(f"  INFO: Unexpected state - investigate")
else:
    print("  No CAN data received (service may not be running)")

print("")

# Test ANT+ (port 5556)
print("Checking ANT+ ZMQ (port 5556)...")
ant_data = capture_zmq_message(5556)
if ant_data:
    if "error" in ant_data:
        print(f"  ERROR: {ant_data['error']}")
    else:
        data_valid = ant_data.get("data_valid", "MISSING")
        is_simulated = ant_data.get("is_simulated", "MISSING")
        hr = ant_data.get("heart_rate")
        print(f"  data_valid: {data_valid}")
        print(f"  is_simulated: {is_simulated}")
        print(f"  heart_rate: {hr}")

        if data_valid == "MISSING":
            print("  FAIL: data_valid field missing - old service version?")
        elif data_valid is False and hr is None:
            print("  PASS: No hardware - data_valid=False, heart_rate=null")
        elif data_valid is True and is_simulated is True:
            print("  INFO: Simulation mode active (--simulate flag)")
        elif data_valid is True and is_simulated is False:
            print("  PASS: Real ANT+ data detected")
        else:
            print(f"  INFO: Unexpected state - investigate")
else:
    print("  No ANT+ data received (service may not be running)")

PYEOF

echo ""

# ========================================
# Test 4: Verify systemd service files don't have mock flags
# ========================================
echo "Test 4: Systemd Service Files"
echo "-----------------------------"

CAN_SERVICE="/etc/systemd/system/argus-can.service"
ANT_SERVICE="/etc/systemd/system/argus-ant.service"

if [ -f "$CAN_SERVICE" ]; then
    if grep -q "\-\-mock" "$CAN_SERVICE"; then
        fail "argus-can.service has --mock flag (will generate phantom data)"
        echo "     Remove --mock from: $CAN_SERVICE"
    else
        pass "argus-can.service does NOT have --mock flag"
    fi
else
    info "argus-can.service not found"
fi

if [ -f "$ANT_SERVICE" ]; then
    if grep -q "\-\-simulate" "$ANT_SERVICE"; then
        fail "argus-ant.service has --simulate flag (will generate phantom data)"
        echo "     Remove --simulate from: $ANT_SERVICE"
    else
        pass "argus-ant.service does NOT have --simulate flag"
    fi
else
    info "argus-ant.service not found"
fi

echo ""

# ========================================
# Summary
# ========================================
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "Expected behavior after fix:"
echo "  - NO CAN hardware: rpm=null, data_valid=false"
echo "  - NO ANT+ hardware: heart_rate=null, data_valid=false"
echo "  - With --mock/--simulate: data shows values but is_simulated=true"
echo ""
echo "To force simulation mode (testing only):"
echo "  CAN:  python can_telemetry.py --mock"
echo "  ANT+: python ant_heart_rate.py --simulate"
echo ""
echo "To restart services after deploying fix:"
echo "  sudo systemctl restart argus-can argus-ant"
echo ""
