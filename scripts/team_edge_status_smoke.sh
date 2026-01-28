#!/usr/bin/env bash
# team_edge_status_smoke.sh — Smoke test for Team Dashboard edge status feature
#
# Validates (source-level):
#   1. Backend has GET /team/diagnostics endpoint
#   2. Endpoint reads from Redis last-seen tracking
#   3. Endpoint returns edge_status and is_online fields
#   4. Frontend TeamDashboard calls /team/diagnostics
#   5. Frontend removed mock fallback data
#   6. Frontend displays edge_status in diagnostics
#   7. Frontend shows helpful offline message with causes
#   8. Frontend displays edge_ip and edge_version when available
#   9. Web build passes (tsc --noEmit)
#
# Usage:
#   bash scripts/team_edge_status_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
TEAM_PY="$REPO_ROOT/cloud/app/routes/team.py"
TEAM_DASH="$WEB_DIR/src/pages/TeamDashboard.tsx"
REDIS_CLIENT="$REPO_ROOT/cloud/app/redis_client.py"
FAIL=0

log()  { echo "[edge-status] $*"; }
pass() { echo "[edge-status]   PASS: $*"; }
fail() { echo "[edge-status]   FAIL: $*"; FAIL=1; }
warn() { echo "[edge-status]   WARN: $*"; }

# ── 1. Backend endpoint exists ──────────────────────────────────
log "Step 1: Backend diagnostics endpoint"

if [ -f "$TEAM_PY" ]; then
  if grep -q 'def get_diagnostics' "$TEAM_PY"; then
    pass "team.py has get_diagnostics function"
  else
    fail "team.py missing get_diagnostics function"
  fi

  if grep -q '"/diagnostics"' "$TEAM_PY"; then
    pass "team.py has /diagnostics route"
  else
    fail "team.py missing /diagnostics route"
  fi

  if grep -q 'get_current_team' "$TEAM_PY" && grep -q 'get_diagnostics' "$TEAM_PY"; then
    pass "diagnostics endpoint uses auth dependency"
  else
    fail "diagnostics endpoint missing auth"
  fi
else
  fail "team.py not found"
fi

# ── 2. Endpoint uses Redis last-seen ────────────────────────────
log "Step 2: Redis last-seen integration"

if [ -f "$TEAM_PY" ]; then
  if grep -q 'get_vehicle_last_seen' "$TEAM_PY"; then
    pass "diagnostics reads vehicle last-seen from Redis"
  else
    fail "diagnostics missing get_vehicle_last_seen call"
  fi

  if grep -q 'get_edge_status' "$TEAM_PY"; then
    pass "diagnostics reads edge status from Redis"
  else
    fail "diagnostics missing get_edge_status call"
  fi

  if grep -q 'get_latest_position' "$TEAM_PY"; then
    pass "diagnostics reads latest position from Redis"
  else
    fail "diagnostics missing get_latest_position call"
  fi
fi

# ── 3. Endpoint returns required fields ─────────────────────────
log "Step 3: Response fields"

if [ -f "$TEAM_PY" ]; then
  if grep -q '"edge_status"' "$TEAM_PY"; then
    pass "response includes edge_status"
  else
    fail "response missing edge_status"
  fi

  if grep -q '"is_online"' "$TEAM_PY"; then
    pass "response includes is_online"
  else
    fail "response missing is_online"
  fi

  if grep -q '"edge_last_seen_ms"' "$TEAM_PY"; then
    pass "response includes edge_last_seen_ms"
  else
    fail "response missing edge_last_seen_ms"
  fi

  if grep -q '"edge_ip"' "$TEAM_PY"; then
    pass "response includes edge_ip"
  else
    fail "response missing edge_ip"
  fi

  if grep -q '"edge_version"' "$TEAM_PY"; then
    pass "response includes edge_version"
  else
    fail "response missing edge_version"
  fi

  # Check staleness thresholds
  if grep -q 'age_s <= 30' "$TEAM_PY"; then
    pass "online threshold is 30 seconds"
  else
    fail "missing 30-second online threshold"
  fi

  if grep -q 'age_s <= 60' "$TEAM_PY"; then
    pass "stale threshold is 60 seconds"
  else
    fail "missing 60-second stale threshold"
  fi
fi

# ── 4. Frontend calls /team/diagnostics ─────────────────────────
log "Step 4: Frontend API integration"

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'team/diagnostics' "$TEAM_DASH"; then
    pass "TeamDashboard fetches /team/diagnostics"
  else
    fail "TeamDashboard missing /team/diagnostics fetch"
  fi

  if grep -q 'is_online' "$TEAM_DASH"; then
    pass "TeamDashboard uses is_online field"
  else
    fail "TeamDashboard missing is_online field"
  fi
fi

# ── 5. Mock fallback removed ────────────────────────────────────
log "Step 5: Mock data removed"

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'Mock:' "$TEAM_DASH"; then
    fail "TeamDashboard still has mock data comments"
  else
    pass "No mock data comments in TeamDashboard"
  fi

  if grep -q 'Date.now() - 3000' "$TEAM_DASH"; then
    fail "TeamDashboard still has hardcoded mock timestamp"
  else
    pass "No hardcoded mock timestamps"
  fi
fi

# ── 6. Frontend displays edge status ────────────────────────────
log "Step 6: Edge status display"

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'Edge Status' "$TEAM_DASH"; then
    pass "TeamDashboard shows Edge Status label"
  else
    fail "TeamDashboard missing Edge Status label"
  fi

  if grep -q 'Edge Last Seen' "$TEAM_DASH"; then
    pass "TeamDashboard shows Edge Last Seen"
  else
    fail "TeamDashboard missing Edge Last Seen"
  fi
fi

# ── 7. Offline message with causes ──────────────────────────────
log "Step 7: Offline help message"

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'Likely causes' "$TEAM_DASH"; then
    pass "Offline alert includes likely causes"
  else
    fail "Offline alert missing likely causes"
  fi

  if grep -q 'truck token' "$TEAM_DASH"; then
    pass "Offline causes mention truck token"
  else
    fail "Offline causes missing truck token mention"
  fi

  if grep -q 'cloud URL' "$TEAM_DASH"; then
    pass "Offline causes mention cloud URL"
  else
    fail "Offline causes missing cloud URL mention"
  fi
fi

# ── 8. Edge IP and version display ──────────────────────────────
log "Step 8: Edge device info"

if [ -f "$TEAM_DASH" ]; then
  if grep -q 'edge_ip' "$TEAM_DASH"; then
    pass "TeamDashboard references edge_ip"
  else
    fail "TeamDashboard missing edge_ip"
  fi

  if grep -q 'edge_version' "$TEAM_DASH"; then
    pass "TeamDashboard references edge_version"
  else
    fail "TeamDashboard missing edge_version"
  fi

  if grep -q 'Edge IP' "$TEAM_DASH"; then
    pass "TeamDashboard shows Edge IP label"
  else
    fail "TeamDashboard missing Edge IP label"
  fi
fi

# ── 9. Redis client has required functions ──────────────────────
log "Step 9: Redis client functions"

if [ -f "$REDIS_CLIENT" ]; then
  if grep -q 'def get_vehicle_last_seen' "$REDIS_CLIENT"; then
    pass "Redis client has get_vehicle_last_seen"
  else
    fail "Redis client missing get_vehicle_last_seen"
  fi

  if grep -q 'def get_edge_status' "$REDIS_CLIENT"; then
    pass "Redis client has get_edge_status"
  else
    fail "Redis client missing get_edge_status"
  fi

  if grep -q 'def set_vehicle_last_seen' "$REDIS_CLIENT"; then
    pass "Redis client has set_vehicle_last_seen"
  else
    fail "Redis client missing set_vehicle_last_seen"
  fi
fi

# ── 10. Build check ─────────────────────────────────────────────
log "Step 10: Web build"

if command -v docker >/dev/null 2>&1; then
  if docker run --rm -v "$WEB_DIR":/app -w /app node:20-alpine \
      sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit" \
      > /tmp/team_edge_status_build.log 2>&1; then
    pass "tsc --noEmit"
  else
    fail "TypeScript check failed. Last 20 lines:"
    tail -20 /tmp/team_edge_status_build.log
  fi
else
  warn "Docker not available — skipping build check"
fi

# ── Summary ────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
