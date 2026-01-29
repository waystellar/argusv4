#!/usr/bin/env bash
# edge_dashboard_theme_smoke.sh — Smoke test for pit crew dashboard DS theme
#
# Validates (source-level):
#   1. :root CSS variables use DS neutral palette
#   2. No linear-gradient in standalone templates (login/setup/settings)
#   3. Header uses solid bg (no gradient)
#   4. Standalone templates use DS neutral tokens (not legacy slate)
#   5. Dashboard functional gradients still use CSS variables (not removed)
#   6. CARTO dark_all tile source preserved for map
#
# Usage:
#   bash scripts/edge_dashboard_theme_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[dashboard-theme] $*"; }
pass() { echo "[dashboard-theme]   PASS: $*"; }
fail() { echo "[dashboard-theme]   FAIL: $*"; FAIL=1; }
warn() { echo "[dashboard-theme]   WARN: $*"; }

if [ ! -f "$DASHBOARD" ]; then
  fail "pit_crew_dashboard.py not found at $DASHBOARD"
  exit 1
fi

# ── 1. :root CSS variables use DS neutral palette ──────────────────
log "Step 1: :root CSS variables"

# Extract :root block
ROOT_BLOCK=$(sed -n '/:root/,/}/p' "$DASHBOARD" | head -30)

check_var() {
  local var_name="$1"
  local expected="$2"
  # Use -e to avoid grep treating --var-name as a flag
  if echo "$ROOT_BLOCK" | grep -q -e "${var_name}:.*${expected}"; then
    pass ":root ${var_name} = ${expected}"
  else
    fail ":root ${var_name} != ${expected}"
  fi
}

check_var "bg-primary" "#0a0a0a"
check_var "bg-secondary" "#171717"
check_var "bg-tertiary" "#262626"
check_var "text-primary" "#fafafa"
check_var "text-secondary" "#a3a3a3"
check_var "text-muted" "#737373"
check_var "accent-purple" "#2563eb"

# Verify --border exists
if echo "$ROOT_BLOCK" | grep -q -e "border:.*#404040"; then
  pass ":root --border = #404040"
else
  fail ":root --border missing or wrong value"
fi

# ── 2. No linear-gradient in standalone templates ──────────────────
log "Step 2: No gradients in standalone templates"

# Extract each standalone template (grep between VAR_HTML and next top-level assignment)
extract_template() {
  local marker="$1"
  local start_line end_line
  start_line=$(grep -n "^${marker}" "$DASHBOARD" | head -1 | cut -d: -f1)
  if [ -z "$start_line" ]; then echo ""; return; fi
  # Find the closing ''' after start_line
  end_line=$(tail -n +"$((start_line + 1))" "$DASHBOARD" | grep -n "^'''" | head -1 | cut -d: -f1)
  if [ -z "$end_line" ]; then echo ""; return; fi
  end_line=$((start_line + end_line))
  sed -n "${start_line},${end_line}p" "$DASHBOARD"
}

LOGIN_BLOCK=$(extract_template "LOGIN_HTML")
SETTINGS_BLOCK=$(extract_template "SETTINGS_HTML")
SETUP_BLOCK=$(extract_template "SETUP_HTML")

for TMPL_NAME in LOGIN SETUP SETTINGS; do
  case "$TMPL_NAME" in
    LOGIN) BLOCK="$LOGIN_BLOCK" ;;
    SETUP) BLOCK="$SETUP_BLOCK" ;;
    SETTINGS) BLOCK="$SETTINGS_BLOCK" ;;
  esac

  if [ -z "$BLOCK" ]; then
    fail "${TMPL_NAME}_HTML not found in file"
    continue
  fi

  if echo "$BLOCK" | grep -q "linear-gradient"; then
    fail "${TMPL_NAME}_HTML still has linear-gradient"
  else
    pass "${TMPL_NAME}_HTML has no linear-gradient"
  fi
done

# ── 3. Header uses solid bg (no gradient) ──────────────────────────
log "Step 3: Dashboard header"

# Extract DASHBOARD_HTML header block (first .header { in file, before standalone templates)
HEADER_BLOCK=$(sed -n '1,/^LOGIN_HTML/{ /\.header *{/,/}/p; }' "$DASHBOARD" | head -10)
if echo "$HEADER_BLOCK" | grep -q "linear-gradient"; then
  fail "Dashboard header still has linear-gradient"
else
  pass "Dashboard header uses solid background"
fi

# Header should use --bg-secondary or #171717
if echo "$HEADER_BLOCK" | grep -q "bg-secondary\|#171717"; then
  pass "Dashboard header uses --bg-secondary"
else
  fail "Dashboard header missing --bg-secondary"
fi

# Header should have border-bottom
if echo "$HEADER_BLOCK" | grep -q "border-bottom"; then
  pass "Dashboard header has border-bottom separator"
else
  fail "Dashboard header missing border-bottom"
fi

# ── 4. Standalone templates use DS neutral tokens ──────────────────
log "Step 4: DS neutral tokens in standalone templates"

for TMPL_NAME in LOGIN SETUP SETTINGS; do
  case "$TMPL_NAME" in
    LOGIN) BLOCK="$LOGIN_BLOCK" ;;
    SETUP) BLOCK="$SETUP_BLOCK" ;;
    SETTINGS) BLOCK="$SETTINGS_BLOCK" ;;
  esac

  [ -z "$BLOCK" ] && continue

  # Body background should be #0a0a0a (neutral-950)
  if echo "$BLOCK" | grep -q "#0a0a0a"; then
    pass "${TMPL_NAME}_HTML has #0a0a0a (neutral-950)"
  else
    fail "${TMPL_NAME}_HTML missing #0a0a0a"
  fi

  # Container bg should be #171717 (neutral-900)
  if echo "$BLOCK" | grep -q "#171717"; then
    pass "${TMPL_NAME}_HTML has #171717 (neutral-900)"
  else
    fail "${TMPL_NAME}_HTML missing #171717"
  fi

  # Borders should be #404040 (neutral-700)
  if echo "$BLOCK" | grep -q "#404040"; then
    pass "${TMPL_NAME}_HTML has #404040 borders"
  else
    fail "${TMPL_NAME}_HTML missing #404040 borders"
  fi

  # No legacy slate colors
  if echo "$BLOCK" | grep -q "#0f172a\|#1e293b\|#334155"; then
    fail "${TMPL_NAME}_HTML still has legacy slate colors"
  else
    pass "${TMPL_NAME}_HTML has no legacy slate colors"
  fi

  # Button should be solid #2563eb (not gradient)
  if echo "$BLOCK" | grep -q "#2563eb"; then
    pass "${TMPL_NAME}_HTML has #2563eb accent"
  else
    fail "${TMPL_NAME}_HTML missing #2563eb accent"
  fi
done

# ── 5. Functional gradients preserved ─────────────────────────────
log "Step 5: Functional gradients preserved"

# Fuel bar gradient
if grep -q "linear-gradient.*--success.*--warning.*--danger" "$DASHBOARD"; then
  pass "Fuel/tire bar gradient preserved"
else
  fail "Fuel/tire bar gradient missing"
fi

# Signal strength gradient
if grep -qe "linear-gradient.*--accent-blue.*--success" "$DASHBOARD"; then
  pass "Signal strength gradient preserved"
else
  fail "Signal strength gradient missing"
fi

# ── 6. Map tile sources ────────────────────────────────────────────
log "Step 6: Map tile source"

if grep -q "opentopomap.org" "$DASHBOARD"; then
  pass "OpenTopoMap tiles configured in dashboard"
else
  fail "OpenTopoMap tiles missing from dashboard"
fi

if grep -q "basemaps.cartocdn.com" "$DASHBOARD"; then
  pass "CARTO tiles configured in dashboard"
else
  fail "CARTO tiles missing from dashboard"
fi

# ── 7. No legacy purple accent ────────────────────────────────────
log "Step 7: No legacy purple accent"

if echo "$ROOT_BLOCK" | grep -q "#8b5cf6"; then
  fail ":root still has legacy purple #8b5cf6"
else
  pass ":root has no legacy purple #8b5cf6"
fi

# Standalone templates should not have #8b5cf6
for TMPL_NAME in LOGIN SETUP SETTINGS; do
  case "$TMPL_NAME" in
    LOGIN) BLOCK="$LOGIN_BLOCK" ;;
    SETUP) BLOCK="$SETUP_BLOCK" ;;
    SETTINGS) BLOCK="$SETTINGS_BLOCK" ;;
  esac

  [ -z "$BLOCK" ] && continue

  if echo "$BLOCK" | grep -q "#8b5cf6"; then
    fail "${TMPL_NAME}_HTML still has legacy purple #8b5cf6"
  else
    pass "${TMPL_NAME}_HTML has no legacy purple"
  fi
done

# ── Summary ────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
