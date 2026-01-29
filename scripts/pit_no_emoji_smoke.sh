#!/usr/bin/env bash
# pit_no_emoji_smoke.sh — Smoke test for PIT-UI-CLEAN-1: No Emojis in Pit Crew Dashboard
#
# Validates:
#   1. No emoji Unicode ranges present in pit_crew_dashboard.py
#   2. Specific known emojis (from original file) are absent
#   3. Python syntax is valid
#   4. Key UI text labels still exist (no accidental deletion)
#
# Usage:
#   bash scripts/pit_no_emoji_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$REPO_ROOT/edge/pit_crew_dashboard.py"
FAIL=0

log()  { echo "[no-emoji]  $*"; }
pass() { echo "[no-emoji]    PASS: $*"; }
fail() { echo "[no-emoji]    FAIL: $*"; FAIL=1; }

# ── 1. No emoji Unicode ranges ─────────────────────────────────
log "Step 1: No emoji Unicode ranges in file"

if [ -f "$DASHBOARD" ]; then
  # Check for common emoji Unicode ranges using Python (most reliable)
  EMOJI_COUNT=$(python3 -c "
import re
with open('$DASHBOARD', 'r') as f:
    content = f.read()
emoji_pattern = re.compile(
    '['
    '\U0001F600-\U0001F64F'
    '\U0001F300-\U0001F5FF'
    '\U0001F680-\U0001F6FF'
    '\U0001F900-\U0001F9FF'
    '\U00002702-\U000027B0'
    '\U00002600-\U000026FF'
    '\U0001F1E0-\U0001F1FF'
    ']+', re.UNICODE
)
matches = emoji_pattern.findall(content)
print(len(matches))
" 2>/dev/null || echo "999")

  if [ "$EMOJI_COUNT" -eq 0 ]; then
    pass "No emoji Unicode ranges found"
  else
    fail "Found $EMOJI_COUNT emoji matches in file"
  fi
else
  fail "pit_crew_dashboard.py not found"
fi

# ── 2. Specific known emojis absent ────────────────────────────
log "Step 2: Specific known emojis are absent"

if [ -f "$DASHBOARD" ]; then
  KNOWN_EMOJIS="🏁 🚗 🔧 ⚙️ ⛽ 🔄 🛠️ 🌤️ ⏱️ 🏎️ 🗺️ 📍 📌 🧪 ⚠️ 🛰️ 🧭 📶 👁️ ✅ 🚫 📊 🔒 🔓 💾 🔍 📹 ❤️ 🔌 📡 🔋 💓 🏔️ 🛣️ ⏹️ ▶️ 📤 📷 ⏳ 🔊 🔇 🔥 🛢️ 🌡️ 🏆 ☁️"

  ALL_ABSENT=true
  for emoji in $KNOWN_EMOJIS; do
    if grep -q "$emoji" "$DASHBOARD" 2>/dev/null; then
      fail "Found emoji $emoji still in file"
      ALL_ABSENT=false
    fi
  done

  if [ "$ALL_ABSENT" = true ]; then
    pass "All 45 known emojis are absent"
  fi
fi

# ── 3. Python syntax valid ──────────────────────────────────────
log "Step 3: Python syntax check"

if python3 -c "import py_compile; py_compile.compile('$DASHBOARD', doraise=True)" 2>/dev/null; then
  pass "Python syntax valid"
else
  fail "Python syntax error"
fi

# ── 4. Key UI labels still present ──────────────────────────────
log "Step 4: Key UI text labels still exist"

if [ -f "$DASHBOARD" ]; then
  for label in 'Engine Vitals' 'Heart Rate History' 'Lap Progress' 'Fuel Strategy' 'Tire Tracking' 'Weather Conditions' 'Pit Stop Timer' 'Course Map' 'Fan Visibility' 'Telemetry Sharing' 'Device Scanner' 'USB Cameras' 'GPS Device' 'ANT+ USB Stick' 'CAN Bus Interface' 'Service Status' 'Send Note to Race Control' 'Pit Readiness Checklist'; do
    if grep -q "$label" "$DASHBOARD"; then
      pass "Label exists: $label"
    else
      fail "Label missing: $label"
    fi
  done
fi

# ── 5. No decorative glyphs in section headers ─────────────────
log "Step 5: Section headers are clean text"

if [ -f "$DASHBOARD" ]; then
  # Check that <h2> tags contain only plain text (no emoji before text)
  BAD_HEADERS=$(python3 -c "
import re
with open('$DASHBOARD', 'r') as f:
    content = f.read()
emoji_re = re.compile('[\U0001F300-\U0001F9FF\U00002600-\U000026FF\U00002702-\U000027B0]')
h2_re = re.compile(r'<h2>(.*?)</h2>')
bad = [m.group(1) for m in h2_re.finditer(content) if emoji_re.search(m.group(1))]
print(len(bad))
" 2>/dev/null || echo "0")

  if [ "$BAD_HEADERS" -eq 0 ]; then
    pass "All h2 headers are clean (no emoji)"
  else
    fail "Found $BAD_HEADERS h2 headers with emoji characters"
  fi
fi

# ── 6. Alert messages are clean ─────────────────────────────────
log "Step 6: Alert messages have no emoji prefixes"

if [ -f "$DASHBOARD" ]; then
  if grep -q "alertMsg = 'CRITICAL:" "$DASHBOARD"; then
    pass "CRITICAL alerts start with plain text"
  else
    fail "CRITICAL alerts may have emoji prefixes"
  fi

  if grep -q "alertMsg = 'WARNING:" "$DASHBOARD"; then
    pass "WARNING alerts start with plain text"
  else
    fail "WARNING alerts may have emoji prefixes"
  fi

  if grep -q "alertMsg = 'ALERT:" "$DASHBOARD"; then
    pass "ALERT alerts start with plain text"
  else
    fail "ALERT alerts may have emoji prefixes"
  fi
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
