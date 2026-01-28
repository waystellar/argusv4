#!/usr/bin/env bash
# edge_provision_ui_smoke.sh — Smoke test for provision UI modernization
#
# Validates:
#   1. No linear-gradient in any provision template (HTML_TEMPLATE, SUCCESS_TEMPLATE, STATUS_TEMPLATE)
#   2. DS marker (data-theme="argus-ds") present in all three templates
#   3. DS neutral tokens present (#0a0a0a body bg, #171717 container bg, #fafafa text)
#   4. No legacy indigo (#4f46e5) or old slate colors (#1a1a2e, #16213e, #fff container)
#   5. STATUS_TEMPLATE has "Open Pit Crew Dashboard" link
#   6. STATUS_TEMPLATE preserves auto-refresh
#   7. Accent uses DS blue (#3b82f6 or #2563eb), not indigo
#   8. All three templates use DS font stack
#
# Usage:
#   bash scripts/edge_provision_ui_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/edge/install.sh"
FAIL=0

log()  { echo "[provision-ui] $*"; }
pass() { echo "[provision-ui]   PASS: $*"; }
fail() { echo "[provision-ui]   FAIL: $*"; FAIL=1; }
warn() { echo "[provision-ui]   WARN: $*"; }

if [ ! -f "$INSTALL_SH" ]; then
  fail "install.sh not found at $INSTALL_SH"
  echo ""
  log "SOME CHECKS FAILED"
  exit 1
fi

# Extract each template block for targeted checks
HTML_BLOCK=$(sed -n '/^HTML_TEMPLATE = """/,/^"""/p' "$INSTALL_SH")
SUCCESS_BLOCK=$(sed -n '/^SUCCESS_TEMPLATE = """/,/^"""/p' "$INSTALL_SH")
STATUS_BLOCK=$(sed -n '/^STATUS_TEMPLATE = """/,/^"""/p' "$INSTALL_SH")

# ── 1. No linear-gradient in any template ─────────────────────────
log "Step 1: No gradients"

for NAME in HTML_TEMPLATE SUCCESS_TEMPLATE STATUS_TEMPLATE; do
  case "$NAME" in
    HTML_TEMPLATE) BLOCK="$HTML_BLOCK" ;;
    SUCCESS_TEMPLATE) BLOCK="$SUCCESS_BLOCK" ;;
    STATUS_TEMPLATE) BLOCK="$STATUS_BLOCK" ;;
  esac

  if echo "$BLOCK" | grep -q "linear-gradient"; then
    fail "$NAME still has linear-gradient"
  else
    pass "$NAME has no gradients"
  fi
done

# ── 2. DS marker in all templates ─────────────────────────────────
log "Step 2: DS marker (data-theme=\"argus-ds\")"

for NAME in HTML_TEMPLATE SUCCESS_TEMPLATE STATUS_TEMPLATE; do
  case "$NAME" in
    HTML_TEMPLATE) BLOCK="$HTML_BLOCK" ;;
    SUCCESS_TEMPLATE) BLOCK="$SUCCESS_BLOCK" ;;
    STATUS_TEMPLATE) BLOCK="$STATUS_BLOCK" ;;
  esac

  if echo "$BLOCK" | grep -q 'data-theme="argus-ds"'; then
    pass "$NAME has data-theme=\"argus-ds\""
  else
    fail "$NAME missing DS marker"
  fi
done

# ── 3. DS neutral tokens present ──────────────────────────────────
log "Step 3: DS neutral tokens"

# Body background #0a0a0a (neutral-950)
for NAME in HTML_TEMPLATE SUCCESS_TEMPLATE STATUS_TEMPLATE; do
  case "$NAME" in
    HTML_TEMPLATE) BLOCK="$HTML_BLOCK" ;;
    SUCCESS_TEMPLATE) BLOCK="$SUCCESS_BLOCK" ;;
    STATUS_TEMPLATE) BLOCK="$STATUS_BLOCK" ;;
  esac

  if echo "$BLOCK" | grep -q "#0a0a0a"; then
    pass "$NAME uses neutral-950 (#0a0a0a)"
  else
    fail "$NAME missing neutral-950 body bg"
  fi
done

# Container bg #171717 (neutral-900)
for NAME in HTML_TEMPLATE SUCCESS_TEMPLATE STATUS_TEMPLATE; do
  case "$NAME" in
    HTML_TEMPLATE) BLOCK="$HTML_BLOCK" ;;
    SUCCESS_TEMPLATE) BLOCK="$SUCCESS_BLOCK" ;;
    STATUS_TEMPLATE) BLOCK="$STATUS_BLOCK" ;;
  esac

  if echo "$BLOCK" | grep -q "#171717"; then
    pass "$NAME uses neutral-900 (#171717)"
  else
    fail "$NAME missing neutral-900 container bg"
  fi
done

# Text color #fafafa (neutral-50)
for NAME in HTML_TEMPLATE SUCCESS_TEMPLATE STATUS_TEMPLATE; do
  case "$NAME" in
    HTML_TEMPLATE) BLOCK="$HTML_BLOCK" ;;
    SUCCESS_TEMPLATE) BLOCK="$SUCCESS_BLOCK" ;;
    STATUS_TEMPLATE) BLOCK="$STATUS_BLOCK" ;;
  esac

  if echo "$BLOCK" | grep -q "#fafafa"; then
    pass "$NAME uses neutral-50 (#fafafa)"
  else
    fail "$NAME missing neutral-50 text"
  fi
done

# ── 4. No legacy colors ───────────────────────────────────────────
log "Step 4: No legacy colors"

# No indigo #4f46e5
if grep -q "#4f46e5" "$INSTALL_SH" 2>/dev/null; then
  # Check it's in templates, not comments
  ALL_TEMPLATES="${HTML_BLOCK}${SUCCESS_BLOCK}${STATUS_BLOCK}"
  if echo "$ALL_TEMPLATES" | grep -q "#4f46e5"; then
    fail "Legacy indigo (#4f46e5) still in templates"
  else
    pass "No legacy indigo in templates"
  fi
else
  pass "No legacy indigo (#4f46e5) anywhere"
fi

# No old slate gradient colors #1a1a2e, #16213e
ALL_TEMPLATES="${HTML_BLOCK}${SUCCESS_BLOCK}${STATUS_BLOCK}"
if echo "$ALL_TEMPLATES" | grep -q "#1a1a2e\|#16213e"; then
  fail "Legacy slate gradient colors (#1a1a2e/#16213e) still in templates"
else
  pass "No legacy slate gradient colors"
fi

# No white container background (background: #fff)
if echo "$ALL_TEMPLATES" | grep -q "background:.*#fff\b"; then
  fail "Legacy white container background still in templates"
else
  pass "No legacy white container background"
fi

# ── 5. STATUS_TEMPLATE has dashboard link ──────────────────────────
log "Step 5: Dashboard navigation"

if echo "$STATUS_BLOCK" | grep -q "Open Pit Crew Dashboard"; then
  pass "STATUS_TEMPLATE has 'Open Pit Crew Dashboard' link"
else
  fail "STATUS_TEMPLATE missing dashboard link"
fi

# ── 6. STATUS_TEMPLATE preserves auto-refresh ─────────────────────
log "Step 6: Status auto-refresh preserved"

if echo "$STATUS_BLOCK" | grep -q 'http-equiv="refresh"'; then
  pass "STATUS_TEMPLATE has auto-refresh meta tag"
else
  fail "STATUS_TEMPLATE missing auto-refresh"
fi

# ── 7. Accent uses DS blue ────────────────────────────────────────
log "Step 7: DS accent color"

if echo "$ALL_TEMPLATES" | grep -q "#3b82f6\|#2563eb"; then
  pass "Templates use DS accent blue (#3b82f6/#2563eb)"
else
  fail "Templates missing DS accent blue"
fi

# ── 8. DS font stack ──────────────────────────────────────────────
log "Step 8: Font stack"

for NAME in HTML_TEMPLATE SUCCESS_TEMPLATE STATUS_TEMPLATE; do
  case "$NAME" in
    HTML_TEMPLATE) BLOCK="$HTML_BLOCK" ;;
    SUCCESS_TEMPLATE) BLOCK="$SUCCESS_BLOCK" ;;
    STATUS_TEMPLATE) BLOCK="$STATUS_BLOCK" ;;
  esac

  if echo "$BLOCK" | grep -q "apple-system.*BlinkMacSystemFont"; then
    pass "$NAME uses DS font stack"
  else
    fail "$NAME missing DS font stack"
  fi
done

# ── 9. Border tokens ──────────────────────────────────────────────
log "Step 9: Border tokens"

if echo "$ALL_TEMPLATES" | grep -q "#404040\|#525252"; then
  pass "Templates use neutral-700/600 border tokens"
else
  fail "Templates missing neutral border tokens"
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
