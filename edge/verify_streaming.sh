#!/bin/bash
#
# Streaming System Verification Script
#
# Tests the video streaming functionality:
# - Streaming status API
# - FFmpeg availability
# - Camera device detection
# - YouTube configuration
#
# Usage: bash verify_streaming.sh [DASHBOARD_URL]
#
# Example:
#   bash verify_streaming.sh                          # Uses localhost:8080
#   bash verify_streaming.sh http://192.168.0.18:8080 # Uses edge IP
#

DASHBOARD_URL="${1:-http://localhost:8080}"

echo "========================================"
echo "  Streaming System Verification"
echo "========================================"
echo ""
echo "Dashboard URL: $DASHBOARD_URL"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Session cookie for authenticated requests
SESSION_COOKIE="pit_session=test_session"

# ========================================
# Test 1: Check FFmpeg installation
# ========================================
echo "Test 1: FFmpeg Installation"
echo "---------------------------"
if command -v ffmpeg &> /dev/null; then
    FFMPEG_VERSION=$(ffmpeg -version | head -1)
    pass "FFmpeg installed: $FFMPEG_VERSION"
else
    fail "FFmpeg not installed. Run: sudo apt install ffmpeg"
fi
echo ""

# ========================================
# Test 2: Check video devices
# ========================================
echo "Test 2: Video Devices"
echo "---------------------"
VIDEO_DEVICES=$(ls /dev/video* 2>/dev/null | wc -l)
if [[ "$VIDEO_DEVICES" -gt 0 ]]; then
    pass "Found $VIDEO_DEVICES video device(s)"
    ls /dev/video* 2>/dev/null | head -8 | while read dev; do
        info "  $dev"
    done
else
    info "No video devices found in /dev/video*"
fi
echo ""

# ========================================
# Test 3: Check streaming status API
# ========================================
echo "Test 3: GET /api/streaming/status"
echo "----------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Cookie: $SESSION_COOKIE" \
    "$DASHBOARD_URL/api/streaming/status" 2>&1)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    pass "Streaming status API returns 200"

    if echo "$BODY" | grep -q '"status"'; then
        STATUS=$(echo "$BODY" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        pass "Status field present: $STATUS"
    else
        fail "Status field missing"
    fi

    if echo "$BODY" | grep -q '"camera"'; then
        CAMERA=$(echo "$BODY" | grep -o '"camera":"[^"]*"' | cut -d'"' -f4)
        pass "Camera field present: $CAMERA"
    else
        fail "Camera field missing"
    fi

    if echo "$BODY" | grep -q '"youtube_configured"'; then
        CONFIGURED=$(echo "$BODY" | grep -o '"youtube_configured":[^,}]*' | cut -d':' -f2)
        if [[ "$CONFIGURED" == "true" ]]; then
            pass "YouTube stream key is configured"
        else
            info "YouTube stream key NOT configured (set in Settings)"
        fi
    fi
elif [[ "$HTTP_CODE" == "401" ]]; then
    info "Requires authentication (401) - test with valid session"
else
    fail "Streaming status returned HTTP $HTTP_CODE"
    echo "     Response: $BODY"
fi
echo ""

# ========================================
# Test 3b: Check switch-camera endpoint
# ========================================
echo "Test 3b: POST /api/streaming/switch-camera"
echo "-------------------------------------------"

# Test missing camera field returns 400
SWITCH_RESP=$(curl -s -w "\n%{http_code}" \
    -H "Cookie: $SESSION_COOKIE" \
    -H "Content-Type: application/json" \
    -X POST -d '{}' \
    "$DASHBOARD_URL/api/streaming/switch-camera" 2>&1)
SWITCH_HTTP=$(echo "$SWITCH_RESP" | tail -1)
SWITCH_BODY=$(echo "$SWITCH_RESP" | head -n -1)

if [[ "$SWITCH_HTTP" == "400" ]]; then
    pass "switch-camera rejects missing camera field (400)"
    if echo "$SWITCH_BODY" | grep -q '"error"'; then
        pass "Error response includes 'error' field"
    else
        fail "Error response missing 'error' field"
    fi
elif [[ "$SWITCH_HTTP" == "401" ]]; then
    info "switch-camera requires authentication (401) — test with valid session"
else
    info "switch-camera empty body returned HTTP $SWITCH_HTTP"
fi

# Test valid camera field returns structured response
SWITCH_RESP2=$(curl -s -w "\n%{http_code}" \
    -H "Cookie: $SESSION_COOKIE" \
    -H "Content-Type: application/json" \
    -X POST -d '{"camera":"main"}' \
    "$DASHBOARD_URL/api/streaming/switch-camera" 2>&1)
SWITCH_HTTP2=$(echo "$SWITCH_RESP2" | tail -1)
SWITCH_BODY2=$(echo "$SWITCH_RESP2" | head -n -1)

if [[ "$SWITCH_HTTP2" == "200" ]] || [[ "$SWITCH_HTTP2" == "400" ]]; then
    pass "switch-camera returns $SWITCH_HTTP2 with structured response"
    if echo "$SWITCH_BODY2" | grep -q '"success"'; then
        pass "Response includes 'success' field"
    elif echo "$SWITCH_BODY2" | grep -q '"error"'; then
        pass "Response includes 'error' field"
    else
        fail "Response missing 'success' or 'error' field"
    fi
elif [[ "$SWITCH_HTTP2" == "401" ]]; then
    info "switch-camera requires authentication (401)"
else
    info "switch-camera returned HTTP $SWITCH_HTTP2"
fi
echo ""

# ========================================
# Test 4: Check dashboard config
# ========================================
echo "Test 4: Dashboard Configuration"
echo "--------------------------------"
CONFIG_FILE="/opt/argus/config/pit_dashboard.json"
if [[ -f "$CONFIG_FILE" ]]; then
    pass "Config file exists: $CONFIG_FILE"

    if grep -q '"youtube_stream_key"' "$CONFIG_FILE" 2>/dev/null; then
        KEY_VALUE=$(grep '"youtube_stream_key"' "$CONFIG_FILE" | cut -d'"' -f4)
        if [[ -n "$KEY_VALUE" ]]; then
            pass "YouTube stream key is set (length: ${#KEY_VALUE})"
        else
            info "YouTube stream key is empty"
        fi
    else
        info "youtube_stream_key not in config"
    fi

    if grep -q '"youtube_live_url"' "$CONFIG_FILE" 2>/dev/null; then
        URL_VALUE=$(grep '"youtube_live_url"' "$CONFIG_FILE" | cut -d'"' -f4)
        if [[ -n "$URL_VALUE" ]]; then
            pass "YouTube live URL is set: $URL_VALUE"
        else
            info "YouTube live URL is empty"
        fi
    fi
else
    info "Config file not found (may be using dev config)"
fi
echo ""

# ========================================
# Test 5: Check argus-video service
# ========================================
echo "Test 5: Service Status"
echo "----------------------"
if command -v systemctl &> /dev/null; then
    if systemctl is-active --quiet argus-dashboard 2>/dev/null; then
        pass "argus-dashboard service is running"
    else
        info "argus-dashboard service not running (or not installed)"
    fi

    if systemctl is-active --quiet argus-video 2>/dev/null; then
        pass "argus-video service is running"
    else
        info "argus-video service not running"
    fi
else
    info "systemctl not available (not systemd system)"
fi
echo ""

# ========================================
# Test 6: Check for running FFmpeg processes
# ========================================
echo "Test 6: FFmpeg Processes"
echo "------------------------"
FFMPEG_PROCS=$(pgrep -c ffmpeg 2>/dev/null || echo "0")
if [[ "$FFMPEG_PROCS" -gt 0 ]]; then
    pass "FFmpeg process(es) running: $FFMPEG_PROCS"
    pgrep -a ffmpeg | head -3 | while read proc; do
        info "  $proc"
    done
else
    info "No FFmpeg processes currently running"
fi
echo ""

# ========================================
# Summary
# ========================================
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "Streaming Architecture:"
echo "  1. Pit Crew configures YouTube stream key in Settings"
echo "  2. Click 'Start Stream' in Cameras tab -> Stream Control"
echo "  3. Dashboard starts FFmpeg: camera -> YouTube RTMP"
echo "  4. Stream status updates in real-time"
echo ""
echo "API Endpoints:"
echo "  GET  /api/streaming/status         - Get streaming status"
echo "  POST /api/streaming/start          - Start streaming"
echo "       Body: {\"camera\": \"chase\"}    (chase/pov/roof/front)"
echo "  POST /api/streaming/stop           - Stop streaming"
echo "  POST /api/streaming/switch-camera  - Switch active camera"
echo "       Body: {\"camera\": \"pov\"}"
echo ""
echo "Status Values:"
echo "  idle     - Not streaming"
echo "  starting - FFmpeg starting up"
echo "  live     - Actively streaming"
echo "  error    - Stream failed (check error message)"
echo ""
echo "Troubleshooting:"
echo "  - If 'YouTube stream key NOT configured':"
echo "      Go to Settings in dashboard and enter your stream key"
echo "  - If 'FFmpeg not installed':"
echo "      Run: sudo apt install ffmpeg"
echo "  - If 'No video devices found':"
echo "      Check camera connections with: ls -la /dev/video*"
echo "  - If stream starts but doesn't appear on YouTube:"
echo "      Check YouTube Studio -> Go Live for stream health"
echo ""
echo "Manual Verification Checklist:"
echo "  [ ] Open dashboard in browser"
echo "  [ ] Go to Cameras tab"
echo "  [ ] Verify Stream Control section shows 'IDLE' status"
echo "  [ ] If YouTube configured: Start Stream button should be enabled"
echo "  [ ] Select camera from dropdown"
echo "  [ ] Click 'Start Stream'"
echo "  [ ] Verify status changes to STARTING then LIVE"
echo "  [ ] Check YouTube Studio for incoming stream"
echo "  [ ] Click 'Stop Stream' to end"
echo ""
