#!/usr/bin/env bash
# pit_stream_quality_smoke.sh — Smoke test for STREAM-2: Stream Quality Control UI
#
# Validates (source-level):
#   1. pit_crew_dashboard.py compiles
#   2. Stream Quality label in HTML
#   3. streamProfileSelect dropdown with 4 options (1080p/720p/480p/360p)
#   4. streamAutoToggle checkbox in HTML
#   5. streamQualityStatus status line in HTML
#   6. streamQualityLabel element for applied profile display
#   7. PROFILE_LABELS JS object with bitrate info
#   8. loadStreamProfile calls GET /api/stream/profile
#   9. handleProfileChange calls POST /api/stream/profile
#  10. handleAutoToggle calls POST /api/stream/auto
#  11. updateQualityStatusUI function exists
#  12. Error recovery: reverts select on failure
#  13. Auto toggle unchecks on manual profile change
#  14. Stream Quality section exists (streamQualitySection)
#
# Usage:
#   bash scripts/pit_stream_quality_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[stream-quality]  $*"; }
pass() { echo "[stream-quality]    PASS: $*"; }
fail() { echo "[stream-quality]    FAIL: $*"; FAIL=1; }

# ── 1. py_compile ─────────────────────────────────────────────────
log "Step 1: pit_crew_dashboard.py compiles"

if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "pit_crew_dashboard.py compiles"
else
  fail "pit_crew_dashboard.py syntax error"
fi

# ── 2. Stream Quality label ───────────────────────────────────────
log "Step 2: Stream Quality label"

if grep -q "Stream Quality" "$DASHBOARD"; then
  pass "Stream Quality label in HTML"
else
  fail "Stream Quality label missing"
fi

# ── 3. Profile dropdown with 4 options ────────────────────────────
log "Step 3: Profile dropdown options"

if grep -q "streamProfileSelect" "$DASHBOARD"; then
  pass "streamProfileSelect element exists"
else
  fail "streamProfileSelect missing"
fi

for opt in "1080p" "720p" "480p" "360p"; do
  if grep -q "$opt" "$DASHBOARD"; then
    pass "Option '$opt' in dropdown"
  else
    fail "Option '$opt' missing from dropdown"
  fi
done

# ── 4. Auto toggle checkbox ──────────────────────────────────────
log "Step 4: Auto toggle"

if grep -q "streamAutoToggle" "$DASHBOARD"; then
  pass "streamAutoToggle checkbox exists"
else
  fail "streamAutoToggle missing"
fi

if grep -q "handleAutoToggle" "$DASHBOARD"; then
  pass "handleAutoToggle function referenced"
else
  fail "handleAutoToggle not referenced"
fi

# ── 5. Quality status line ────────────────────────────────────────
log "Step 5: Quality status line"

if grep -q "streamQualityStatus" "$DASHBOARD"; then
  pass "streamQualityStatus element exists"
else
  fail "streamQualityStatus missing"
fi

# ── 6. Applied profile label element ──────────────────────────────
log "Step 6: Applied profile label"

if grep -q "streamQualityLabel" "$DASHBOARD"; then
  pass "streamQualityLabel element exists"
else
  fail "streamQualityLabel missing"
fi

if grep -q "streamQualityTime" "$DASHBOARD"; then
  pass "streamQualityTime element for timestamp"
else
  fail "streamQualityTime missing"
fi

# ── 7. PROFILE_LABELS JS object ──────────────────────────────────
log "Step 7: PROFILE_LABELS with bitrate info"

if grep -q "PROFILE_LABELS" "$DASHBOARD"; then
  pass "PROFILE_LABELS object defined"
else
  fail "PROFILE_LABELS missing"
fi

if grep -q "4500k" "$DASHBOARD" && grep -q "2500k" "$DASHBOARD" && grep -q "1200k" "$DASHBOARD" && grep -q "800k" "$DASHBOARD"; then
  pass "All four bitrate labels present"
else
  fail "Not all bitrate labels found"
fi

# ── 8. loadStreamProfile calls GET /api/stream/profile ────────────
log "Step 8: loadStreamProfile fetches profile"

if grep -q "async function loadStreamProfile" "$DASHBOARD"; then
  pass "loadStreamProfile function defined"
else
  fail "loadStreamProfile not defined"
fi

if grep -q "fetch('/api/stream/profile')" "$DASHBOARD"; then
  pass "GET /api/stream/profile called"
else
  fail "GET /api/stream/profile not called"
fi

# ── 9. handleProfileChange calls POST /api/stream/profile ────────
log "Step 9: handleProfileChange POSTs profile"

if grep -q "async function handleProfileChange" "$DASHBOARD"; then
  pass "handleProfileChange function defined"
else
  fail "handleProfileChange not defined"
fi

if grep -A 15 "async function handleProfileChange" "$DASHBOARD" | grep -q "method: 'POST'"; then
  pass "handleProfileChange uses POST"
else
  fail "handleProfileChange not POSTing"
fi

# ── 10. handleAutoToggle calls POST /api/stream/auto ──────────────
log "Step 10: handleAutoToggle POSTs auto"

if grep -q "async function handleAutoToggle" "$DASHBOARD"; then
  pass "handleAutoToggle function defined"
else
  fail "handleAutoToggle not defined"
fi

if grep -A 10 "async function handleAutoToggle" "$DASHBOARD" | grep -q "/api/stream/auto"; then
  pass "handleAutoToggle calls /api/stream/auto"
else
  fail "handleAutoToggle not calling /api/stream/auto"
fi

# ── 11. updateQualityStatusUI function ────────────────────────────
log "Step 11: updateQualityStatusUI function"

if grep -q "function updateQualityStatusUI" "$DASHBOARD"; then
  pass "updateQualityStatusUI function exists"
else
  fail "updateQualityStatusUI missing"
fi

# ── 12. Error recovery: reverts select on failure ─────────────────
log "Step 12: Error recovery on profile change failure"

if grep -A 25 "async function handleProfileChange" "$DASHBOARD" | grep -q "sel.value = prev"; then
  pass "Reverts dropdown on failure"
else
  fail "No revert on failure"
fi

# ── 13. Auto toggle unchecks on manual change ─────────────────────
log "Step 13: Auto toggle unchecks on manual profile change"

if grep -A 25 "async function handleProfileChange" "$DASHBOARD" | grep -q "autoTgl.checked = false"; then
  pass "Auto toggle unchecked on manual change"
else
  fail "Auto toggle not unchecked on manual change"
fi

# ── 14. streamQualitySection container ────────────────────────────
log "Step 14: Stream Quality section container"

if grep -q "streamQualitySection" "$DASHBOARD"; then
  pass "streamQualitySection container exists"
else
  fail "streamQualitySection missing"
fi

# ── Summary ──────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
