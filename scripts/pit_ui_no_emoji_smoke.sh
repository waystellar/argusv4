#!/usr/bin/env bash
# pit_ui_no_emoji_smoke.sh - Smoke test for PIT-SHARING-UI-1: No Emojis + Sharing UI
#
# Validates:
#   1. No emoji characters in pit_crew_dashboard.py
#   2. Sharing section HTML elements exist
#   3. CSS classes for buttons/badges are defined
#   4. Python syntax compiles
#
# Usage:
#   bash scripts/pit_ui_no_emoji_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[pit-ui-emoji]  $*"; }
pass() { echo "[pit-ui-emoji]    PASS: $*"; }
fail() { echo "[pit-ui-emoji]    FAIL: $*"; FAIL=1; }
skip() { echo "[pit-ui-emoji]    SKIP: $*"; }

log "PIT-SHARING-UI-1: No Emojis + Sharing UI Smoke Test"
echo ""

# ── 1. No emoji characters ────────────────────────────────────
log "Step 1: No emoji characters in pit_crew_dashboard.py"

if [ -f "$PIT_DASH" ]; then
  # Common racing/tool emojis that might have been used
  EMOJI_PATTERN='🏁|🔧|🚗|🏎|⚙|🛠|📡|📍|🔴|🟢|🟡|⚠️|✓|✗|❌|✅|🎥|📷|🔥|⛽|🏆|🚨|💨|🔋|⏱|🛞'

  if grep -qE "$EMOJI_PATTERN" "$PIT_DASH"; then
    fail "Emoji characters found in pit_crew_dashboard.py"
    echo "      Found emojis:"
    grep -nE "$EMOJI_PATTERN" "$PIT_DASH" | head -5
  else
    pass "No emoji characters found"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. Sharing section HTML elements exist ────────────────────
log "Step 2: Sharing section HTML elements exist"

if [ -f "$PIT_DASH" ]; then
  # Check visibility badge
  if grep -q 'id="visibilityBadge"' "$PIT_DASH"; then
    pass "visibilityBadge element exists"
  else
    fail "visibilityBadge element missing"
  fi

  # Check visibility buttons
  if grep -q 'id="btnVisibilityOn"' "$PIT_DASH"; then
    pass "btnVisibilityOn element exists"
  else
    fail "btnVisibilityOn element missing"
  fi

  if grep -q 'id="btnVisibilityOff"' "$PIT_DASH"; then
    pass "btnVisibilityOff element exists"
  else
    fail "btnVisibilityOff element missing"
  fi

  # Check sharing field groups container
  if grep -q 'id="sharingFieldGroups"' "$PIT_DASH"; then
    pass "sharingFieldGroups container exists"
  else
    fail "sharingFieldGroups container missing"
  fi

  # Check individual sharing group containers
  for group in gps engine_basic engine_advanced biometrics; do
    if grep -q "id=\"sharing-$group\"" "$PIT_DASH"; then
      pass "sharing-$group container exists"
    else
      fail "sharing-$group container missing"
    fi
  done

  # Check sync status element
  if grep -q 'id="sharingSyncStatus"' "$PIT_DASH"; then
    pass "sharingSyncStatus element exists"
  else
    fail "sharingSyncStatus element missing"
  fi
fi

# ── 3. CSS classes for buttons/badges are defined ─────────────
log "Step 3: CSS classes for buttons and badges are defined"

if [ -f "$PIT_DASH" ]; then
  # Check .btn class is defined (not just used)
  if grep -q '\.btn {' "$PIT_DASH" || grep -q '\.btn{' "$PIT_DASH"; then
    pass ".btn CSS class is defined"
  else
    fail ".btn CSS class is NOT defined"
  fi

  # Check .btn-secondary class is defined
  if grep -q '\.btn-secondary {' "$PIT_DASH" || grep -q '\.btn-secondary{' "$PIT_DASH"; then
    pass ".btn-secondary CSS class is defined"
  else
    fail ".btn-secondary CSS class is NOT defined"
  fi

  # Check .badge class is defined
  if grep -q '\.badge {' "$PIT_DASH" || grep -q '\.badge{' "$PIT_DASH"; then
    pass ".badge CSS class is defined"
  else
    fail ".badge CSS class is NOT defined"
  fi

  # Check PIT-SHARING-UI-1 marker
  if grep -q 'PIT-SHARING-UI-1' "$PIT_DASH"; then
    pass "PIT-SHARING-UI-1 marker present"
  else
    fail "PIT-SHARING-UI-1 marker missing"
  fi
fi

# ── 4. Sharing JavaScript functions exist ─────────────────────
log "Step 4: Sharing JavaScript functions exist"

if [ -f "$PIT_DASH" ]; then
  if grep -q 'function renderSharingFields' "$PIT_DASH"; then
    pass "renderSharingFields function exists"
  else
    fail "renderSharingFields function missing"
  fi

  if grep -q 'function toggleField' "$PIT_DASH"; then
    pass "toggleField function exists"
  else
    fail "toggleField function missing"
  fi

  if grep -q 'function applyPreset' "$PIT_DASH"; then
    pass "applyPreset function exists"
  else
    fail "applyPreset function missing"
  fi

  if grep -q 'function saveSharingPolicy' "$PIT_DASH"; then
    pass "saveSharingPolicy function exists"
  else
    fail "saveSharingPolicy function missing"
  fi
fi

# ── 5. Python syntax check ────────────────────────────────────
log "Step 5: Python syntax compiles"

if python3 -m py_compile "$PIT_DASH" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles without syntax errors"
else
  fail "pit_crew_dashboard.py has syntax errors"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
