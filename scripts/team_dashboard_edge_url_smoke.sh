#!/usr/bin/env bash
# team_dashboard_edge_url_smoke.sh - Smoke test for EDGE-URL-1: Auto-Discover Edge URL
#
# Validates:
#   1. EdgeHeartbeatRequest schema includes edge_url field
#   2. Edge heartbeat sender includes edge_url in payload
#   3. Cloud diagnostics endpoint returns edge_url
#   4. TeamDashboard no longer renders an <input> for edge URL
#   5. TeamDashboard shows auto-discovered "Open Pit Crew Portal" button
#   6. _detect_lan_ip function exists in edge code
#   7. Python syntax compiles
#
# Usage:
#   bash scripts/team_dashboard_edge_url_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[edge-url]  $*"; }
pass() { echo "[edge-url]    PASS: $*"; }
fail() { echo "[edge-url]    FAIL: $*"; FAIL=1; }
skip() { echo "[edge-url]    SKIP: $*"; }

log "EDGE-URL-1: Auto-Discover Edge URL Smoke Test"
echo ""

PRODUCTION_PY="$REPO_ROOT/cloud/app/routes/production.py"
TEAM_PY="$REPO_ROOT/cloud/app/routes/team.py"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"
TEAM_TSX="$REPO_ROOT/web/src/pages/TeamDashboard.tsx"

# ── 1. EdgeHeartbeatRequest includes edge_url ─────────────────
log "Step 1: EdgeHeartbeatRequest includes edge_url"

if [ -f "$PRODUCTION_PY" ]; then
  if grep -q 'edge_url.*Optional\[str\]' "$PRODUCTION_PY"; then
    pass "EdgeHeartbeatRequest has edge_url field"
  else
    fail "EdgeHeartbeatRequest missing edge_url field"
  fi

  # Check edge_url is stored in heartbeat status dict
  if grep -q '"edge_url".*data\.edge_url' "$PRODUCTION_PY"; then
    pass "Heartbeat handler stores edge_url in status dict"
  else
    fail "Heartbeat handler not storing edge_url"
  fi
else
  fail "production.py not found"
fi

# ── 2. Edge heartbeat sender includes edge_url ────────────────
log "Step 2: Edge sends edge_url in heartbeat payload"

if [ -f "$PIT_DASH" ]; then
  if grep -q '"edge_url".*edge_url' "$PIT_DASH"; then
    pass "Edge heartbeat payload includes edge_url"
  else
    fail "Edge heartbeat payload missing edge_url"
  fi

  # Check _detect_lan_ip function exists
  if grep -q 'def _detect_lan_ip' "$PIT_DASH"; then
    pass "_detect_lan_ip function exists"
  else
    fail "_detect_lan_ip function missing"
  fi

  # Check socket import
  if grep -q 'import socket' "$PIT_DASH"; then
    pass "socket module imported"
  else
    fail "socket module not imported"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 3. Cloud diagnostics returns edge_url ─────────────────────
log "Step 3: Cloud diagnostics returns edge_url"

if [ -f "$TEAM_PY" ]; then
  # Check edge_url is read from edge_detail
  if grep -q 'edge_url.*edge_detail' "$TEAM_PY" || grep -q 'edge_detail.*edge_url' "$TEAM_PY"; then
    pass "Diagnostics reads edge_url from edge_detail"
  else
    fail "Diagnostics not reading edge_url from edge_detail"
  fi

  # Check edge_url is in the return dict
  if grep -q '"edge_url".*edge_url' "$TEAM_PY"; then
    pass "Diagnostics returns edge_url in response"
  else
    fail "Diagnostics missing edge_url in response"
  fi
else
  fail "team.py not found"
fi

# ── 4. TeamDashboard no longer has manual URL input ───────────
log "Step 4: TeamDashboard has no manual edge URL input"

if [ -f "$TEAM_TSX" ]; then
  # Check NO <input> element for edge URL entry
  if grep -q 'placeholder="e.g. 192.168' "$TEAM_TSX"; then
    fail "Manual edge URL input still present (placeholder found)"
  else
    pass "Manual edge URL input removed"
  fi

  # Check no handleSaveEdgeUrl function
  if grep -q 'handleSaveEdgeUrl' "$TEAM_TSX"; then
    fail "handleSaveEdgeUrl still present"
  else
    pass "handleSaveEdgeUrl removed"
  fi

  # Check no EDGE_URL_STORAGE_KEY
  if grep -q 'EDGE_URL_STORAGE_KEY' "$TEAM_TSX"; then
    fail "EDGE_URL_STORAGE_KEY still present (localStorage-based)"
  else
    pass "EDGE_URL_STORAGE_KEY removed (no localStorage)"
  fi

  # Check no isValidEdgeUrl function
  if grep -q 'function isValidEdgeUrl' "$TEAM_TSX"; then
    fail "isValidEdgeUrl function still present"
  else
    pass "isValidEdgeUrl removed (validation no longer needed client-side)"
  fi
else
  fail "TeamDashboard.tsx not found"
fi

# ── 5. TeamDashboard shows auto-discovered portal ────────────
log "Step 5: TeamDashboard shows auto-discovered Pit Crew Portal"

if [ -f "$TEAM_TSX" ]; then
  # Check for "Open Pit Crew Portal" button
  if grep -q 'Open Pit Crew Portal' "$TEAM_TSX"; then
    pass "'Open Pit Crew Portal' button exists"
  else
    fail "'Open Pit Crew Portal' button missing"
  fi

  # CLOUD-MANAGE-0: Check for fallback message when edge_url is null
  if grep -q 'not detected\|Waiting for edge\|Edge device offline' "$TEAM_TSX"; then
    pass "Missing edge URL fallback message exists"
  else
    fail "Missing edge URL fallback message not found"
  fi

  # Check edge_url is sourced from diagnostics
  if grep -q 'diagnostics.*edge_url' "$TEAM_TSX"; then
    pass "edge_url sourced from diagnostics"
  else
    fail "edge_url not sourced from diagnostics"
  fi

  # Check DiagnosticsData interface includes edge_url
  if grep -q 'edge_url.*string.*null' "$TEAM_TSX"; then
    pass "DiagnosticsData interface includes edge_url"
  else
    fail "DiagnosticsData interface missing edge_url"
  fi
fi

# ── 6. EDGE-URL-1 markers present ────────────────────────────
log "Step 6: EDGE-URL-1 markers"

for file in "$PRODUCTION_PY" "$TEAM_PY" "$PIT_DASH" "$TEAM_TSX"; do
  if [ -f "$file" ]; then
    basename=$(basename "$file")
    if grep -q 'EDGE-URL-1' "$file"; then
      pass "$basename has EDGE-URL-1 marker"
    else
      fail "$basename missing EDGE-URL-1 marker"
    fi
  fi
done

# ── 7. Python syntax check ───────────────────────────────────
log "Step 7: Python syntax compiles"

for pyfile in "$PRODUCTION_PY" "$TEAM_PY" "$PIT_DASH"; do
  if [ -f "$pyfile" ]; then
    basename=$(basename "$pyfile")
    if python3 -m py_compile "$pyfile" 2>/dev/null; then
      pass "$basename compiles"
    else
      fail "$basename has syntax errors"
    fi
  fi
done

# ── 8. Simulated heartbeat curl command ───────────────────────
log "Step 8: Simulated heartbeat documentation"

echo ""
echo "  To simulate an edge heartbeat with edge_url, run:"
echo ""
echo '  curl -X POST http://192.168.0.19/api/v1/production/events/<EVENT_ID>/edge/heartbeat \'
echo '    -H "Content-Type: application/json" \'
echo '    -H "X-Truck-Token: <TRUCK_TOKEN>" \'
echo '    -d '"'"'{'
echo '      "streaming_status": "idle",'
echo '      "cameras": [],'
echo '      "last_can_ts": null,'
echo '      "last_gps_ts": null,'
echo '      "youtube_configured": false,'
echo '      "youtube_url": null,'
echo '      "edge_url": "http://192.168.0.18:8080"'
echo '    }'"'"''
echo ""
pass "Simulated heartbeat command documented"

# ── Summary ──────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
