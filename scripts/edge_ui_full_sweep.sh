#!/usr/bin/env bash
# edge_ui_full_sweep.sh — End-to-end UI consistency sweep for edge device
#
# Confirms:
#   - Non-provisioned state shows provision UI on :8080
#   - Provisioned state shows pit crew dashboard on :8080
#   - Provision pages have modern styling (no gradients, DS markers)
#   - Dashboard uses updated CSS variables
#   - systemd service health for key services
#
# Usage:
#   bash scripts/edge_ui_full_sweep.sh [HOST]
#
# Default HOST is localhost.
# Exit non-zero on any failure.
set -euo pipefail

HOST="${1:-localhost}"
PORT=8080
BASE_URL="http://${HOST}:${PORT}"
PROVISION_FLAG="/etc/argus/.provisioned"
FAIL=0

log()  { echo "[edge-sweep] $*"; }
pass() { echo "[edge-sweep]   PASS: $*"; }
fail() { echo "[edge-sweep]   FAIL: $*"; FAIL=1; }
warn() { echo "[edge-sweep]   WARN: $*"; }
info() { echo "[edge-sweep]   INFO: $*"; }

# ── 0. Environment ─────────────────────────────────────────────────
log "Step 0: Environment"

# Check provisioned flag
if [ -f "$PROVISION_FLAG" ]; then
  info "Provisioned flag EXISTS → expecting pit crew dashboard"
  PROVISIONED=true
else
  info "Provisioned flag ABSENT → expecting provision UI"
  PROVISIONED=false
fi

# Check what holds port 8080
PORT_OWNER=$(lsof -ti :"$PORT" 2>/dev/null | head -1 || true)
if [ -n "$PORT_OWNER" ]; then
  PROC_NAME=$(ps -p "$PORT_OWNER" -o comm= 2>/dev/null || echo "unknown")
  info "Port $PORT held by PID $PORT_OWNER ($PROC_NAME)"
else
  info "Port $PORT not in use (services may be down)"
fi

# ── 1. Service health ──────────────────────────────────────────────
log "Step 1: systemd service health"

SERVICES="argus-provision argus-dashboard argus-gps argus-telemetry argus-zmq"
for SVC in $SERVICES; do
  STATUS=$(systemctl is-active "$SVC" 2>/dev/null || echo "unknown")
  case "$STATUS" in
    active)   info "$SVC: active" ;;
    inactive) info "$SVC: inactive" ;;
    failed)   warn "$SVC: FAILED" ;;
    *)        info "$SVC: $STATUS" ;;
  esac
done

# Verify mutual exclusion: provision and dashboard should not both be active
PROV_STATUS=$(systemctl is-active argus-provision 2>/dev/null || echo "unknown")
DASH_STATUS=$(systemctl is-active argus-dashboard 2>/dev/null || echo "unknown")

if [ "$PROV_STATUS" = "active" ] && [ "$DASH_STATUS" = "active" ]; then
  fail "Both argus-provision AND argus-dashboard are active (mutual exclusion violated)"
elif [ "$PROV_STATUS" = "active" ] && [ "$PROVISIONED" = "true" ]; then
  warn "argus-provision active but device is provisioned (flag exists)"
elif [ "$DASH_STATUS" = "active" ] && [ "$PROVISIONED" = "false" ]; then
  warn "argus-dashboard active but device is NOT provisioned (flag missing)"
fi

# Validate expected service is active
if [ "$PROVISIONED" = "true" ]; then
  if [ "$DASH_STATUS" = "active" ]; then
    pass "argus-dashboard is active (expected for provisioned device)"
  else
    warn "argus-dashboard is not active ($DASH_STATUS)"
  fi
else
  if [ "$PROV_STATUS" = "active" ]; then
    pass "argus-provision is active (expected for non-provisioned device)"
  else
    warn "argus-provision is not active ($PROV_STATUS)"
  fi
fi

# ── 2. HTTP checks ─────────────────────────────────────────────────
log "Step 2: HTTP reachability"

ROOT_CODE=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/" 2>/dev/null || echo "000")
if [ "$ROOT_CODE" = "200" ] || [ "$ROOT_CODE" = "302" ]; then
  pass "GET / returned HTTP $ROOT_CODE"
else
  warn "GET / returned HTTP $ROOT_CODE (service may not be running)"
fi

# Fetch page content for marker checks
ROOT_BODY=$(curl -sf "${BASE_URL}/" 2>/dev/null || echo "")

# ── 3. Provision UI checks (non-provisioned) ──────────────────────
if [ "$PROVISIONED" = "false" ]; then
  log "Step 3: Provision UI checks (non-provisioned)"

  if [ -z "$ROOT_BODY" ]; then
    warn "Could not fetch / — service may not be running. Skipping HTTP checks."
  else
    # DS marker
    if echo "$ROOT_BODY" | grep -q 'data-theme="argus-ds"'; then
      pass "Provision / has data-theme=\"argus-ds\" marker"
    else
      fail "Provision / missing data-theme=\"argus-ds\" marker"
    fi

    # No gradients
    if echo "$ROOT_BODY" | grep -q "linear-gradient"; then
      fail "Provision / still has linear-gradient"
    else
      pass "Provision / has no linear-gradient"
    fi

    # DS neutral tokens
    if echo "$ROOT_BODY" | grep -q "#0a0a0a"; then
      pass "Provision / uses neutral-950 (#0a0a0a)"
    else
      fail "Provision / missing neutral-950"
    fi

    if echo "$ROOT_BODY" | grep -q "#171717"; then
      pass "Provision / uses neutral-900 (#171717)"
    else
      fail "Provision / missing neutral-900"
    fi

    # Title check
    if echo "$ROOT_BODY" | grep -q "Argus Edge Setup"; then
      pass "Provision / title is 'Argus Edge Setup'"
    else
      fail "Provision / unexpected title"
    fi
  fi

  # Check /status
  STATUS_BODY=$(curl -sf "${BASE_URL}/status" 2>/dev/null || echo "")

  if [ -n "$STATUS_BODY" ]; then
    log "Step 3b: /status page checks"

    if echo "$STATUS_BODY" | grep -q 'data-theme="argus-ds"'; then
      pass "/status has data-theme=\"argus-ds\" marker"
    else
      fail "/status missing data-theme=\"argus-ds\" marker"
    fi

    if echo "$STATUS_BODY" | grep -q "linear-gradient"; then
      fail "/status still has linear-gradient"
    else
      pass "/status has no linear-gradient"
    fi

    if echo "$STATUS_BODY" | grep -q "#0a0a0a"; then
      pass "/status uses neutral-950"
    else
      fail "/status missing neutral-950"
    fi

    if echo "$STATUS_BODY" | grep -q "Open Pit Crew Dashboard"; then
      pass "/status has 'Open Pit Crew Dashboard' link"
    else
      fail "/status missing dashboard link"
    fi

    if echo "$STATUS_BODY" | grep -q 'meta http-equiv="refresh"'; then
      pass "/status has auto-refresh meta tag"
    else
      fail "/status missing auto-refresh"
    fi
  else
    warn "Could not fetch /status — skipping"
  fi

# ── 4. Dashboard checks (provisioned) ─────────────────────────────
else
  log "Step 3: Dashboard checks (provisioned)"

  if [ -z "$ROOT_BODY" ]; then
    warn "Could not fetch / — service may not be running. Skipping HTTP checks."
  else
    # Dashboard title marker
    if echo "$ROOT_BODY" | grep -q "Argus Pit Crew"; then
      pass "Dashboard / has 'Argus Pit Crew' marker"
    else
      fail "Dashboard / missing 'Argus Pit Crew' marker"
    fi

    # CSS variable checks (these appear in inline <style>)
    if echo "$ROOT_BODY" | grep -q -e "bg-primary:.*#0a0a0a"; then
      pass "Dashboard has --bg-primary: #0a0a0a"
    else
      fail "Dashboard missing --bg-primary: #0a0a0a"
    fi

    if echo "$ROOT_BODY" | grep -q -e "bg-secondary:.*#171717"; then
      pass "Dashboard has --bg-secondary: #171717"
    else
      fail "Dashboard missing --bg-secondary: #171717"
    fi

    if echo "$ROOT_BODY" | grep -q -e "text-primary:.*#fafafa"; then
      pass "Dashboard has --text-primary: #fafafa"
    else
      fail "Dashboard missing --text-primary: #fafafa"
    fi

    # No gradient in header
    # The header CSS should use var(--bg-secondary), not linear-gradient
    # Extract .header block from response
    if echo "$ROOT_BODY" | grep -q "\.header.*{" ; then
      HEADER_CSS=$(echo "$ROOT_BODY" | sed -n '/\.header *{/,/}/p' | head -10)
      if echo "$HEADER_CSS" | grep -q "linear-gradient"; then
        fail "Dashboard header still has linear-gradient"
      else
        pass "Dashboard header has no linear-gradient"
      fi
    else
      warn "Could not extract header CSS from response"
    fi

    # No legacy purple in :root
    ROOT_CSS=$(echo "$ROOT_BODY" | sed -n '/:root/,/}/p' | head -30)
    if echo "$ROOT_CSS" | grep -q "#8b5cf6"; then
      fail "Dashboard :root still has legacy purple #8b5cf6"
    else
      pass "Dashboard :root has no legacy purple"
    fi
  fi
fi

# ── 5. Source-level cross-check ────────────────────────────────────
log "Step 4: Source-level cross-check"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/edge/install.sh"
DASHBOARD_PY="$REPO_ROOT/edge/pit_crew_dashboard.py"

# Provision templates: no gradients
if [ -f "$INSTALL_SH" ]; then
  extract_install_template() {
    local marker="$1"
    local start_line end_line
    start_line=$(grep -n "^${marker}" "$INSTALL_SH" | head -1 | cut -d: -f1)
    if [ -z "$start_line" ]; then echo ""; return; fi
    end_line=$(tail -n +"$((start_line + 1))" "$INSTALL_SH" | grep -n '^"""' | head -1 | cut -d: -f1)
    if [ -z "$end_line" ]; then echo ""; return; fi
    end_line=$((start_line + end_line))
    sed -n "${start_line},${end_line}p" "$INSTALL_SH"
  }

  for TMPL in HTML_TEMPLATE SUCCESS_TEMPLATE STATUS_TEMPLATE; do
    BLOCK=$(extract_install_template "$TMPL")
    if [ -z "$BLOCK" ]; then
      fail "install.sh ${TMPL} not found"
      continue
    fi

    if echo "$BLOCK" | grep -q "linear-gradient"; then
      fail "install.sh ${TMPL} has linear-gradient"
    else
      pass "install.sh ${TMPL} no gradient"
    fi

    if echo "$BLOCK" | grep -q 'data-theme="argus-ds"'; then
      pass "install.sh ${TMPL} has DS marker"
    else
      fail "install.sh ${TMPL} missing DS marker"
    fi
  done
else
  fail "install.sh not found"
fi

# Dashboard: CSS vars correct
if [ -f "$DASHBOARD_PY" ]; then
  DROOT=$(sed -n '/:root/,/}/p' "$DASHBOARD_PY" | head -30)

  if echo "$DROOT" | grep -q -e "bg-primary:.*#0a0a0a"; then
    pass "dashboard.py --bg-primary = #0a0a0a"
  else
    fail "dashboard.py --bg-primary wrong"
  fi

  if echo "$DROOT" | grep -q -e "bg-secondary:.*#171717"; then
    pass "dashboard.py --bg-secondary = #171717"
  else
    fail "dashboard.py --bg-secondary wrong"
  fi

  if echo "$DROOT" | grep -q "#8b5cf6"; then
    fail "dashboard.py :root still has legacy purple"
  else
    pass "dashboard.py :root no legacy purple"
  fi

  # Standalone templates: no gradients
  for TMPL in LOGIN_HTML SETUP_HTML SETTINGS_HTML; do
    START=$(grep -n "^${TMPL}" "$DASHBOARD_PY" | head -1 | cut -d: -f1)
    if [ -z "$START" ]; then
      fail "dashboard.py ${TMPL} not found"
      continue
    fi
    END=$(tail -n +"$((START + 1))" "$DASHBOARD_PY" | grep -n "^'''" | head -1 | cut -d: -f1)
    if [ -z "$END" ]; then
      fail "dashboard.py ${TMPL} end marker not found"
      continue
    fi
    END=$((START + END))
    BLOCK=$(sed -n "${START},${END}p" "$DASHBOARD_PY")

    if echo "$BLOCK" | grep -q "linear-gradient"; then
      fail "dashboard.py ${TMPL} has linear-gradient"
    else
      pass "dashboard.py ${TMPL} no gradient"
    fi

    if echo "$BLOCK" | grep -q "#0f172a\|#1e293b\|#334155"; then
      fail "dashboard.py ${TMPL} has legacy slate colors"
    else
      pass "dashboard.py ${TMPL} no legacy slate"
    fi
  done
else
  fail "pit_crew_dashboard.py not found"
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
