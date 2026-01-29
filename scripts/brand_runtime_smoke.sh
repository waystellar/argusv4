#!/usr/bin/env bash
# brand_runtime_smoke.sh — Smoke test for BRAND-1: Verify no "Argus" in public UI
#
# Scans source code and built assets for the word "Argus" in user-facing
# outputs: HTML pages, page titles, rendered JSX text, share messages, and
# error pages. Internal-only references (comments, variable names, config
# keys, log messages, file paths, device names) are excluded.
#
# Validates:
#   Web Source (user-facing text):
#     1.  No "Argus" in index.html <title> or <meta>
#     2.  No "Argus" in LandingPage.tsx rendered text
#     3.  No "Argus" in EventLive.tsx rendered text
#     4.  No "Argus" in VehiclePage.tsx rendered text
#     5.  No "Argus" in AdminLogin.tsx rendered text
#     6.  No "Argus" in ComponentShowcase.tsx rendered text
#   Cloud Source (user-facing HTML):
#     7.  No "Argus" in setup.py <title> tags
#     8.  No "Argus" in setup.py <h1> tags
#     9.  No "Argus" in setup.py <p> body text
#   Edge Source (user-facing HTML):
#    10.  No "Argus" in pit_crew_dashboard.py <title> tags
#    11.  No "Argus" in pit_crew_dashboard.py <h1> tags
#    12.  No "Argus" in install.sh <title> tags
#    13.  No "Argus" in install.sh <h1> tags
#   Built Assets (if web/dist exists):
#    14.  No "Argus" in built HTML files
#    15.  No "Argus" in built JS bundles
#   Full Source Scan:
#    16.  No user-facing "Argus" in web/src/ (excluding internal patterns)
#    17.  No user-facing "Argus" in cloud/ (excluding internal patterns)
#    18.  No user-facing "Argus" in edge/ (excluding internal patterns)
#   Syntax:
#    19.  Python syntax compiles (setup.py)
#    20.  Python syntax compiles (pit_crew_dashboard.py)
#    21.  install.sh syntax OK
#
# Usage:
#   bash scripts/brand_runtime_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[brand]  $*"; }
pass() { echo "[brand]    PASS: $*"; }
fail() { echo "[brand]    FAIL: $*"; FAIL=1; }
warn() { echo "[brand]    WARN: $*"; }

INDEX_HTML="$REPO_ROOT/web/index.html"
LANDING="$REPO_ROOT/web/src/pages/LandingPage.tsx"
EVENT_LIVE="$REPO_ROOT/web/src/pages/EventLive.tsx"
VEHICLE="$REPO_ROOT/web/src/pages/VehiclePage.tsx"
ADMIN_LOGIN="$REPO_ROOT/web/src/pages/admin/AdminLogin.tsx"
SHOWCASE="$REPO_ROOT/web/src/pages/ComponentShowcase.tsx"
SETUP_PY="$REPO_ROOT/cloud/app/routes/setup.py"
PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"
INSTALL_SH="$REPO_ROOT/edge/install.sh"

log "BRAND-1: Runtime Brand Verification Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# WEB SOURCE (USER-FACING TEXT)
# ═══════════════════════════════════════════════════════════════════

# ── 1. index.html ──────────────────────────────────────────────────
log "Step 1: No Argus in index.html title/meta"
if [ -f "$INDEX_HTML" ]; then
  if grep -i 'Argus' "$INDEX_HTML" | grep -qE '<title>|<meta.*description'; then
    fail "index.html still contains Argus in title or meta"
    grep -in 'Argus' "$INDEX_HTML" | head -3
  else
    pass "index.html clean"
  fi
else
  warn "index.html not found"
fi

# ── 2. LandingPage.tsx ─────────────────────────────────────────────
log "Step 2: No Argus in LandingPage.tsx rendered text"
if [ -f "$LANDING" ]; then
  # Exclude comments (lines with // or * at start)
  if grep -v '^\s*[/*]' "$LANDING" | grep -v '^\s*//' | grep -qi 'Argus'; then
    fail "LandingPage.tsx still contains Argus in rendered text"
    grep -in 'Argus' "$LANDING" | grep -v '^\s*[/*]' | head -3
  else
    pass "LandingPage.tsx clean"
  fi
else
  warn "LandingPage.tsx not found"
fi

# ── 3. EventLive.tsx ───────────────────────────────────────────────
log "Step 3: No Argus in EventLive.tsx rendered text"
if [ -f "$EVENT_LIVE" ]; then
  if grep -v '^\s*[/*]' "$EVENT_LIVE" | grep -v '^\s*//' | grep -qi 'Argus'; then
    fail "EventLive.tsx still contains Argus"
    grep -in 'Argus' "$EVENT_LIVE" | head -3
  else
    pass "EventLive.tsx clean"
  fi
else
  warn "EventLive.tsx not found"
fi

# ── 4. VehiclePage.tsx ─────────────────────────────────────────────
log "Step 4: No Argus in VehiclePage.tsx rendered text"
if [ -f "$VEHICLE" ]; then
  if grep -v '^\s*[/*]' "$VEHICLE" | grep -v '^\s*//' | grep -qi 'Argus'; then
    fail "VehiclePage.tsx still contains Argus"
    grep -in 'Argus' "$VEHICLE" | head -3
  else
    pass "VehiclePage.tsx clean"
  fi
else
  warn "VehiclePage.tsx not found"
fi

# ── 5. AdminLogin.tsx ──────────────────────────────────────────────
log "Step 5: No Argus in AdminLogin.tsx rendered text"
if [ -f "$ADMIN_LOGIN" ]; then
  if grep -v '^\s*[/*]' "$ADMIN_LOGIN" | grep -v '^\s*//' | grep -qi 'Argus'; then
    fail "AdminLogin.tsx still contains Argus"
    grep -in 'Argus' "$ADMIN_LOGIN" | head -3
  else
    pass "AdminLogin.tsx clean"
  fi
else
  warn "AdminLogin.tsx not found"
fi

# ── 6. ComponentShowcase.tsx ───────────────────────────────────────
log "Step 6: No Argus in ComponentShowcase.tsx rendered text"
if [ -f "$SHOWCASE" ]; then
  if grep -v '^\s*[/*]' "$SHOWCASE" | grep -v '^\s*//' | grep -qi 'Argus'; then
    fail "ComponentShowcase.tsx still contains Argus"
    grep -in 'Argus' "$SHOWCASE" | head -3
  else
    pass "ComponentShowcase.tsx clean"
  fi
else
  warn "ComponentShowcase.tsx not found"
fi

# ═══════════════════════════════════════════════════════════════════
# CLOUD SOURCE (USER-FACING HTML)
# ═══════════════════════════════════════════════════════════════════

# ── 7. setup.py <title> tags ──────────────────────────────────────
log "Step 7: No Argus in setup.py title tags"
if [ -f "$SETUP_PY" ]; then
  if grep '<title>' "$SETUP_PY" | grep -qi 'Argus'; then
    fail "setup.py <title> still contains Argus"
    grep -n '<title>.*[Aa]rgus' "$SETUP_PY" | head -3
  else
    pass "setup.py titles clean"
  fi
else
  warn "setup.py not found"
fi

# ── 8. setup.py <h1> tags ────────────────────────────────────────
log "Step 8: No Argus in setup.py h1 tags"
if [ -f "$SETUP_PY" ]; then
  if grep '<h1>' "$SETUP_PY" | grep -qi 'Argus'; then
    fail "setup.py <h1> still contains Argus"
    grep -n '<h1>.*[Aa]rgus' "$SETUP_PY" | head -3
  else
    pass "setup.py headings clean"
  fi
else
  warn "setup.py not found"
fi

# ── 9. setup.py <p> body text ────────────────────────────────────
log "Step 9: No Argus in setup.py paragraph text"
if [ -f "$SETUP_PY" ]; then
  if grep '<p' "$SETUP_PY" | grep -qi 'Argus'; then
    fail "setup.py <p> still contains Argus"
    grep -n '<p.*[Aa]rgus' "$SETUP_PY" | head -3
  else
    pass "setup.py body text clean"
  fi
else
  warn "setup.py not found"
fi

# ═══════════════════════════════════════════════════════════════════
# EDGE SOURCE (USER-FACING HTML)
# ═══════════════════════════════════════════════════════════════════

# ── 10. pit_crew_dashboard.py <title> tags ────────────────────────
log "Step 10: No Argus in pit_crew_dashboard.py title tags"
if [ -f "$PIT_DASH" ]; then
  if grep '<title>' "$PIT_DASH" | grep -qi 'Argus'; then
    fail "pit_crew_dashboard.py <title> still contains Argus"
    grep -n '<title>.*[Aa]rgus' "$PIT_DASH" | head -3
  else
    pass "pit_crew_dashboard.py titles clean"
  fi
else
  warn "pit_crew_dashboard.py not found"
fi

# ── 11. pit_crew_dashboard.py <h1> tags ──────────────────────────
log "Step 11: No Argus in pit_crew_dashboard.py h1 tags"
if [ -f "$PIT_DASH" ]; then
  if grep '<h1>' "$PIT_DASH" | grep -qi 'Argus'; then
    fail "pit_crew_dashboard.py <h1> still contains Argus"
    grep -n '<h1>.*[Aa]rgus' "$PIT_DASH" | head -3
  else
    pass "pit_crew_dashboard.py headings clean"
  fi
else
  warn "pit_crew_dashboard.py not found"
fi

# ── 12. install.sh <title> tags ──────────────────────────────────
log "Step 12: No Argus in install.sh title tags"
if [ -f "$INSTALL_SH" ]; then
  if grep '<title>' "$INSTALL_SH" | grep -qi 'Argus'; then
    fail "install.sh <title> still contains Argus"
    grep -n '<title>.*[Aa]rgus' "$INSTALL_SH" | head -3
  else
    pass "install.sh titles clean"
  fi
else
  warn "install.sh not found"
fi

# ── 13. install.sh <h1> tags ────────────────────────────────────
log "Step 13: No Argus in install.sh h1 tags"
if [ -f "$INSTALL_SH" ]; then
  if grep '<h1>' "$INSTALL_SH" | grep -qi 'Argus'; then
    fail "install.sh <h1> still contains Argus"
    grep -n '<h1>.*[Aa]rgus' "$INSTALL_SH" | head -3
  else
    pass "install.sh headings clean"
  fi
else
  warn "install.sh not found"
fi

# ═══════════════════════════════════════════════════════════════════
# BUILT ASSETS (if web/dist exists)
# ═══════════════════════════════════════════════════════════════════

DIST_DIR="$REPO_ROOT/web/dist"

# ── 14. Built HTML files ─────────────────────────────────────────
log "Step 14: No Argus in built HTML files"
if [ -d "$DIST_DIR" ]; then
  # Check if dist is stale (older than source changes)
  DIST_AGE=$(stat -f %m "$DIST_DIR/index.html" 2>/dev/null || echo 0)
  SRC_AGE=$(stat -f %m "$INDEX_HTML" 2>/dev/null || echo 0)
  if [ "$DIST_AGE" -lt "$SRC_AGE" ]; then
    warn "web/dist is stale (older than source) — run 'npm run build' to rebuild"
  else
    HTML_HITS=$(find "$DIST_DIR" -name '*.html' -print0 | xargs -0 grep -li 'Argus' 2>/dev/null || true)
    if [ -n "$HTML_HITS" ]; then
      fail "Built HTML contains Argus:"
      echo "$HTML_HITS"
    else
      pass "Built HTML clean"
    fi
  fi
else
  warn "web/dist not found — skipping built asset scan (run npm run build first)"
fi

# ── 15. Built JS bundles ─────────────────────────────────────────
log "Step 15: No Argus in built JS bundles"
if [ -d "$DIST_DIR" ]; then
  DIST_AGE=$(stat -f %m "$DIST_DIR/index.html" 2>/dev/null || echo 0)
  SRC_AGE=$(stat -f %m "$INDEX_HTML" 2>/dev/null || echo 0)
  if [ "$DIST_AGE" -lt "$SRC_AGE" ]; then
    warn "web/dist is stale — skipping JS bundle scan"
  else
    JS_HITS=$(find "$DIST_DIR" -name '*.js' -print0 | xargs -0 grep -l 'Argus' 2>/dev/null || true)
    if [ -n "$JS_HITS" ]; then
      fail "Built JS bundles contain Argus:"
      echo "$JS_HITS" | while IFS= read -r f; do
        echo "  $(basename "$f"): $(grep -o 'Argus[^"]*' "$f" | head -3)"
      done
    else
      pass "Built JS bundles clean"
    fi
  fi
else
  warn "web/dist not found — skipping JS bundle scan"
fi

# ═══════════════════════════════════════════════════════════════════
# FULL SOURCE SCAN (user-facing only)
# ═══════════════════════════════════════════════════════════════════

# These scans look for "Argus" in user-facing contexts across entire
# directories, excluding known internal-only patterns:
#   - Code comments (lines starting with *, //, #, """)
#   - Import/require statements
#   - Variable names, localStorage keys, cookie names
#   - File paths (/opt/argus, /etc/argus, /dev/argus)
#   - Config constants, database URLs
#   - Log messages (logger.info, logger.error, etc.)
#   - Systemd unit descriptions
#   - Python docstrings (triple-quoted)
#   - CLI argparse descriptions
#   - Custom event names ('argus:')
#   - CSS comments

# Helper: scan a directory for user-facing Argus references
scan_user_facing() {
  local DIR="$1"
  local LABEL="$2"

  if [ ! -d "$DIR" ]; then
    warn "$LABEL directory not found"
    return
  fi

  # Find all Argus references, then exclude internal patterns
  local HITS
  HITS=$(grep -rn '\bArgus\b' "$DIR" \
    --include='*.tsx' --include='*.ts' --include='*.py' --include='*.html' --include='*.sh' \
    2>/dev/null \
    | grep -v 'node_modules' \
    | grep -v '__pycache__' \
    | grep -v '\.pyc' \
    | grep -vi '^\s*#' \
    | grep -v '^\s*\*' \
    | grep -v '^\s*//' \
    | grep -v '^\s*"""' \
    | grep -v 'logger\.' \
    | grep -v 'logging\.' \
    | grep -v 'argparse\.' \
    | grep -v 'description=' \
    | grep -v '/opt/argus' \
    | grep -v '/etc/argus' \
    | grep -v '/dev/argus' \
    | grep -v 'argus_admin_token' \
    | grep -v 'argus_telemetry' \
    | grep -v 'argus_favorites' \
    | grep -v 'argus-theme' \
    | grep -v 'argus-ds' \
    | grep -v 'argus:center' \
    | grep -v 'argus:argus@' \
    | grep -v 'ARGUS_REPO' \
    | grep -v 'ARGUS_HOME' \
    | grep -v 'argus_gps\|argus_ant\|argus_can\|argus_cam' \
    | grep -v 'argus-dashboard\|argus-uplink\|argus-gps\|argus-can\|argus-ant\|argus-video\|argus-provision\|argus-readiness\|argus-edge' \
    | grep -v 'useradd.*argus\|User.*argus\|chown.*argus\|argus:argus' \
    | grep -v 'Description=Argus' \
    | grep -v "Argus Cloud Configuration" \
    | grep -v "Argus Edge Configuration" \
    | grep -v "Argus Timing System - Allow" \
    | grep -v "Argus Timing System - USB" \
    | grep -v "Argus EDGE-5" \
    | grep -v "Argus - Fix Sudoers" \
    | grep -v "Argus - Manual Telemetry" \
    | grep -v "Argus Manual Activation" \
    | grep -v "Argus - System Diagnostic" \
    | grep -v "Argus Edge Diagnostic" \
    | grep -v "Argus - Full System Repair" \
    | grep -v "Argus System Repair" \
    | grep -v "auto-generated by the Argus" \
    | grep -v "Starting Argus" \
    | grep -v "Shutting down Argus" \
    | grep -v "Argus.*Starting" \
    | grep -v 'app_name.*=.*"Argus' \
    | grep -v "Argus Edge Provisioning Server" \
    | grep -v "Argus Pit Crew Dashboard -" \
    | grep -v "Argus Timing System v4" \
    | grep -v "Argus GPS Service" \
    | grep -v "Argus Uplink Service" \
    | grep -v "Argus CAN" \
    | grep -v "Argus Video Director" \
    | grep -v "Argus Edge Simulator" \
    | grep -v "Argus v4" \
    | grep -v "the Argus design system" \
    | grep -v "the Argus telemetry" \
    | grep -v "API client for Argus" \
    | grep -v "Admin.*Routes.*for Argus" \
    | grep -v "ORM models for Argus" \
    | grep -v "integrates with the Argus" \
    | grep -v "print.*Argus" \
    || true)

  if [ -n "$HITS" ]; then
    fail "$LABEL still has user-facing Argus references:"
    echo "$HITS" | head -10
  else
    pass "$LABEL clean (no user-facing Argus)"
  fi
}

# ── 16. web/src/ scan ────────────────────────────────────────────
log "Step 16: Full scan web/src/ for user-facing Argus"
scan_user_facing "$REPO_ROOT/web/src" "web/src"

# ── 17. cloud/ scan ──────────────────────────────────────────────
log "Step 17: Full scan cloud/ for user-facing Argus"
scan_user_facing "$REPO_ROOT/cloud" "cloud"

# ── 18. edge/ scan ───────────────────────────────────────────────
log "Step 18: Full scan edge/ for user-facing Argus"
scan_user_facing "$REPO_ROOT/edge" "edge"

# ═══════════════════════════════════════════════════════════════════
# SYNTAX
# ═══════════════════════════════════════════════════════════════════

# ── 19. Python syntax (setup.py) ─────────────────────────────────
log "Step 19: Python syntax compiles (setup.py)"
if [ -f "$SETUP_PY" ]; then
  if python3 -c "import ast; ast.parse(open('$SETUP_PY').read())" 2>/dev/null; then
    pass "Python syntax OK (setup.py)"
  else
    fail "Python syntax error (setup.py)"
  fi
else
  warn "setup.py not found"
fi

# ── 20. Python syntax (pit_crew_dashboard.py) ────────────────────
log "Step 20: Python syntax compiles (pit_crew_dashboard.py)"
if [ -f "$PIT_DASH" ]; then
  if python3 -c "import ast; ast.parse(open('$PIT_DASH').read())" 2>/dev/null; then
    pass "Python syntax OK (pit_crew_dashboard.py)"
  else
    fail "Python syntax error (pit_crew_dashboard.py)"
  fi
else
  warn "pit_crew_dashboard.py not found"
fi

# ── 21. install.sh syntax ────────────────────────────────────────
log "Step 21: install.sh syntax OK"
if [ -f "$INSTALL_SH" ]; then
  if bash -n "$INSTALL_SH" 2>/dev/null; then
    pass "install.sh syntax OK"
  else
    fail "install.sh syntax error"
  fi
else
  warn "install.sh not found"
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
