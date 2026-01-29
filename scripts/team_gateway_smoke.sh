#!/usr/bin/env bash
# team_gateway_smoke.sh — Smoke test for TEAM-1: Team Dashboard Gateway to Pit Crew
#
# CLOUD-MANAGE-0: Updated to reflect auto-discovery from heartbeat.
# Manual edge URL entry (localStorage, validation) has been replaced by
# automatic discovery via edge heartbeat → cloud Redis → diagnostics API.
#
# Validates (source-level):
#   1. No manual edge URL input form (auto-discovered)
#   2. Edge URL from diagnostics (not localStorage)
#   3. "Open Pit Crew Portal" link with edgeUrl
#   4. Preview Fan View button with target="_blank"
#   5. Proper fallback messaging when edge not detected
#   6. Diagnostics polling on Ops tab
#   7. TypeScript build check (if node available)
#
# Usage:
#   bash scripts/team_gateway_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TD="$REPO_ROOT/web/src/pages/TeamDashboard.tsx"
FAIL=0

log()  { echo "[team-gateway]  $*"; }
pass() { echo "[team-gateway]    PASS: $*"; }
fail() { echo "[team-gateway]    FAIL: $*"; FAIL=1; }
warn() { echo "[team-gateway]    WARN: $*"; }

if [ ! -f "$TD" ]; then
  fail "TeamDashboard.tsx not found"
  exit 1
fi

# ── 1. No manual edge URL input form ─────────────────────────────────
log "Step 1: No manual edge URL input form (auto-discovered)"
if grep -q "EDGE_URL_STORAGE_KEY\|edgeUrlInput\|handleSaveEdgeUrl" "$TD"; then
  fail "Manual edge URL entry still present (should be auto-discovered)"
else
  pass "No manual edge URL entry (auto-discovery only)"
fi

# ── 2. Edge URL from diagnostics ─────────────────────────────────────
log "Step 2: Edge URL sourced from diagnostics"
if grep -q 'diagnostics.*edge_url' "$TD"; then
  pass "Edge URL from diagnostics API"
else
  fail "Edge URL not from diagnostics"
fi

# ── 3. "Open Pit Crew Portal" link ───────────────────────────────────
log "Step 3: Open Pit Crew Portal link"
if grep -q "Open Pit Crew Portal" "$TD"; then
  pass "Open Pit Crew Portal button exists"
else
  fail "Open Pit Crew Portal button missing"
fi

if grep -q 'href={edgeUrl}' "$TD"; then
  pass "Link href bound to edgeUrl"
else
  fail "Link href not bound to edgeUrl"
fi

# ── 4. Preview Fan View ──────────────────────────────────────────────
log "Step 4: Preview Fan View button"
if grep -q "Preview Fan View" "$TD"; then
  pass "Preview Fan View button exists"
else
  fail "Preview Fan View button missing"
fi

if grep -q 'target="_blank"' "$TD"; then
  pass "Opens in new tab (target=_blank)"
else
  fail "Not opening in new tab"
fi

if grep -q 'rel="noopener noreferrer"' "$TD"; then
  pass "Has noopener noreferrer"
else
  fail "Missing noopener noreferrer"
fi

# ── 5. Fallback messaging when edge not detected ─────────────────────
log "Step 5: Fallback messaging"
if grep -q 'Waiting for edge device\|Edge device offline' "$TD"; then
  pass "Fallback messaging for missing edge exists"
else
  fail "Fallback messaging missing"
fi

# ── 6. Diagnostics polling ───────────────────────────────────────────
log "Step 6: Diagnostics polling on Ops tab"
if grep -q 'fetchDiagnostics' "$TD" && grep -q 'setInterval' "$TD"; then
  pass "Diagnostics polling exists"
else
  fail "Diagnostics polling missing"
fi

if grep -q "activeTab === 'ops'" "$TD"; then
  pass "Polling gated on Ops tab"
else
  fail "Polling not gated on Ops tab"
fi

# ── 7. TypeScript build check ────────────────────────────────────────
log "Step 7: TypeScript build check"
if command -v node >/dev/null 2>&1; then
  if [ -f "$REPO_ROOT/web/package.json" ]; then
    if (cd "$REPO_ROOT/web" && npx tsc --noEmit 2>&1); then
      pass "TypeScript build passes"
    else
      fail "TypeScript build errors"
    fi
  else
    warn "web/package.json not found"
  fi
else
  warn "Node.js not available — skipping tsc check"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
