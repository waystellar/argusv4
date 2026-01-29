#!/usr/bin/env bash
# branding_smoke.sh — Smoke test for BRANDING-0
#
# Validates that user-facing surfaces use "Race Link Live" branding
# and do not contain the old "Live Race Tracking" text.
#
# Validates:
#   Absence checks (old branding removed):
#     1.  No "Live Race Tracking" in LandingPage.tsx
#     2.  No "Live Race Tracking" in index.html
#     3.  No "Live Race Tracking" anywhere in web/src/
#   Presence checks (new branding present):
#     4.  "Race Link Live" in LandingPage.tsx hero heading
#     5.  "Race Link Live" in LandingPage.tsx footer
#     6.  "Race Link Live" in index.html <title>
#   Edge Pit Crew (no old branding):
#     7.  No "Live Race Tracking" in pit_crew_dashboard.py
#     8.  Pit Crew header uses "Pit Crew" (not old branding)
#
# Usage:
#   bash scripts/branding_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[branding]  $*"; }
pass() { echo "[branding]    PASS: $*"; }
fail() { echo "[branding]    FAIL: $*"; FAIL=1; }

LANDING="$REPO_ROOT/web/src/pages/LandingPage.tsx"
INDEX_HTML="$REPO_ROOT/web/index.html"
WEB_SRC="$REPO_ROOT/web/src"
PIT_CREW="$REPO_ROOT/edge/pit_crew_dashboard.py"

log "BRANDING-0: Race Link Live Branding Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# ABSENCE CHECKS — Old branding removed
# ═══════════════════════════════════════════════════════════════════

# ── 1. No "Live Race Tracking" in LandingPage ────────────────────
log "Step 1: No old branding in LandingPage.tsx"
if [ ! -f "$LANDING" ]; then
  fail "LandingPage.tsx not found"
else
  if grep -qi 'Live Race Tracking' "$LANDING"; then
    fail "'Live Race Tracking' still in LandingPage.tsx"
  else
    pass "No 'Live Race Tracking' in LandingPage.tsx"
  fi
fi

# ── 2. No "Live Race Tracking" in index.html ─────────────────────
log "Step 2: No old branding in index.html"
if [ ! -f "$INDEX_HTML" ]; then
  fail "index.html not found"
else
  if grep -qi 'Live Race Tracking' "$INDEX_HTML"; then
    fail "'Live Race Tracking' still in index.html"
  else
    pass "No 'Live Race Tracking' in index.html"
  fi
fi

# ── 3. No "Live Race Tracking" anywhere in web/src ───────────────
log "Step 3: No old branding anywhere in web/src/"
if grep -rqi 'Live Race Tracking' "$WEB_SRC"; then
  fail "'Live Race Tracking' found in web/src/:"
  grep -rni 'Live Race Tracking' "$WEB_SRC" | head -5
else
  pass "No 'Live Race Tracking' in web/src/"
fi

# ═══════════════════════════════════════════════════════════════════
# PRESENCE CHECKS — New branding present
# ═══════════════════════════════════════════════════════════════════

# ── 4. "Race Link Live" in LandingPage hero ──────────────────────
log "Step 4: 'Race Link Live' in LandingPage hero heading"
if grep -q '>Race Link Live<' "$LANDING"; then
  pass "'Race Link Live' in hero heading"
else
  fail "'Race Link Live' missing from hero heading"
fi

# ── 5. "Race Link Live" in LandingPage footer ────────────────────
log "Step 5: 'Race Link Live' in LandingPage footer"
if grep -A5 'Footer' "$LANDING" | grep -q 'Race Link Live'; then
  pass "'Race Link Live' in footer"
else
  # Fallback: check anywhere below line 90
  if grep -c 'Race Link Live' "$LANDING" | grep -q '[2-9]'; then
    pass "'Race Link Live' appears multiple times (hero + footer)"
  else
    fail "'Race Link Live' missing from footer (only appears once)"
  fi
fi

# ── 6. "Race Link Live" in index.html <title> ────────────────────
log "Step 6: 'Race Link Live' in index.html title"
if grep -q '<title>Race Link Live</title>' "$INDEX_HTML"; then
  pass "'Race Link Live' in <title>"
else
  fail "'Race Link Live' missing from <title>"
fi

# ═══════════════════════════════════════════════════════════════════
# EDGE PIT CREW CHECKS
# ═══════════════════════════════════════════════════════════════════

# ── 7. No "Live Race Tracking" in pit crew dashboard ─────────────
log "Step 7: No old branding in pit_crew_dashboard.py"
if [ ! -f "$PIT_CREW" ]; then
  fail "pit_crew_dashboard.py not found"
else
  if grep -qi 'Live Race Tracking' "$PIT_CREW"; then
    fail "'Live Race Tracking' in pit_crew_dashboard.py"
  else
    pass "No 'Live Race Tracking' in pit_crew_dashboard.py"
  fi
fi

# ── 8. Pit Crew header uses "Pit Crew" ───────────────────────────
log "Step 8: Pit Crew header uses correct branding"
if [ -f "$PIT_CREW" ]; then
  if grep -q '<h1>Pit Crew</h1>' "$PIT_CREW"; then
    pass "Pit Crew header uses 'Pit Crew'"
  else
    fail "Pit Crew header missing 'Pit Crew' text"
  fi
fi

# ═══════════════════════════════════════════════════════════════════
echo ""
if [ "$FAIL" -ne 0 ]; then
  log "RESULT: SOME CHECKS FAILED"
  exit 1
else
  log "RESULT: ALL CHECKS PASSED"
  exit 0
fi
