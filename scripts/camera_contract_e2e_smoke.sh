#!/usr/bin/env bash
# camera_contract_e2e_smoke.sh - E2E Smoke test for CAM-CONTRACT-1B: Camera Contract
#
# Validates:
#   1. Edge and Cloud have consistent canonical camera slots (main, cockpit, chase, suspension)
#   2. Web UI components use canonical camera slots
#   3. Backward compatibility aliases are consistent across Edge and Cloud
#   4. All components have CAM-CONTRACT-1B marker
#   5. npm run build passes (if npm available)
#
# Usage:
#   bash scripts/camera_contract_e2e_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[cam-e2e]  $*"; }
pass() { echo "[cam-e2e]    PASS: $*"; }
fail() { echo "[cam-e2e]    FAIL: $*"; FAIL=1; }
skip() { echo "[cam-e2e]    SKIP: $*"; }

log "CAM-CONTRACT-1B: End-to-End Camera Contract Smoke Test"
echo ""

# CAM-CONTRACT-1B: Canonical 4-camera slots
CANONICAL_CAMERAS=("main" "cockpit" "chase" "suspension")
# Legacy aliases map to canonical names
LEGACY_ALIASES=("pov:cockpit" "roof:chase" "front:suspension" "rear:suspension")

# ── 1. Edge canonical cameras match contract ─────────────────
log "Step 1: Edge canonical cameras match contract"

EDGE_STREAM="$REPO_ROOT/edge/stream_profiles.py"
if [ -f "$EDGE_STREAM" ]; then
  all_found=true
  for cam in "${CANONICAL_CAMERAS[@]}"; do
    if grep -q "\"$cam\"" "$EDGE_STREAM"; then
      pass "Edge: '$cam' in VALID_CAMERAS"
    else
      fail "Edge: '$cam' missing from VALID_CAMERAS"
      all_found=false
    fi
  done
else
  fail "edge/stream_profiles.py not found"
fi

# ── 2. Cloud canonical cameras match contract ────────────────
log "Step 2: Cloud canonical cameras match contract"

CLOUD_PROD="$REPO_ROOT/cloud/app/routes/production.py"
if [ -f "$CLOUD_PROD" ]; then
  for cam in "${CANONICAL_CAMERAS[@]}"; do
    if grep -q "\"$cam\"" "$CLOUD_PROD"; then
      pass "Cloud: '$cam' in CANONICAL_CAMERAS"
    else
      fail "Cloud: '$cam' missing from CANONICAL_CAMERAS"
    fi
  done
else
  fail "cloud/app/routes/production.py not found"
fi

# ── 3. Web UI components use canonical cameras ───────────────
log "Step 3: Web UI components use canonical cameras"

WEB_FILES=(
  "web/src/components/StreamControl/StreamControlPanel.tsx"
  "web/src/components/Team/VideoFeedManager.tsx"
  "web/src/pages/VehiclePage.tsx"
  "web/src/pages/ControlRoom.tsx"
  "web/src/pages/ProductionDashboard.tsx"
)

for webfile in "${WEB_FILES[@]}"; do
  filepath="$REPO_ROOT/$webfile"
  if [ -f "$filepath" ]; then
    # Check that suspension camera is present (CAM-CONTRACT-1B)
    if grep -qE "(suspension:|'suspension'|\"suspension\")" "$filepath"; then
      pass "Web: $(basename "$webfile") uses canonical cameras (has suspension)"
    else
      fail "Web: $(basename "$webfile") missing canonical camera 'suspension'"
    fi
  else
    skip "Web: $webfile not found"
  fi
done

# ── 4. Backward compatibility aliases consistent ─────────────
log "Step 4: Backward compatibility aliases consistent"

for alias_pair in "${LEGACY_ALIASES[@]}"; do
  IFS=':' read -r legacy canonical <<< "$alias_pair"

  # Check Edge
  if [ -f "$EDGE_STREAM" ]; then
    if grep -q "\"$legacy\".*\"$canonical\"" "$EDGE_STREAM"; then
      pass "Edge: $legacy->$canonical alias"
    else
      fail "Edge: $legacy->$canonical alias missing"
    fi
  fi

  # Check Cloud
  if [ -f "$CLOUD_PROD" ]; then
    if grep -q "\"$legacy\".*\"$canonical\"" "$CLOUD_PROD"; then
      pass "Cloud: $legacy->$canonical alias"
    else
      fail "Cloud: $legacy->$canonical alias missing"
    fi
  fi
done

# ── 5. CAM-CONTRACT-1B marker in key files ────────────────────
log "Step 5: CAM-CONTRACT-1B marker in key files"

KEY_FILES=(
  "edge/stream_profiles.py"
  "edge/video_director.py"
  "edge/pit_crew_dashboard.py"
  "cloud/app/routes/production.py"
  "web/src/components/StreamControl/StreamControlPanel.tsx"
)

for keyfile in "${KEY_FILES[@]}"; do
  filepath="$REPO_ROOT/$keyfile"
  if [ -f "$filepath" ]; then
    if grep -q 'CAM-CONTRACT-1B' "$filepath"; then
      pass "$(basename "$keyfile") has CAM-CONTRACT-1B marker"
    else
      fail "$(basename "$keyfile") missing CAM-CONTRACT-1B marker"
    fi
  else
    skip "$keyfile not found"
  fi
done

# ── 6. Pit crew dashboard screenshot grid ────────────────────
log "Step 6: Pit crew dashboard screenshot grid"

PIT_DASH="$REPO_ROOT/edge/pit_crew_dashboard.py"
if [ -f "$PIT_DASH" ]; then
  for cam in "${CANONICAL_CAMERAS[@]}"; do
    if grep -q "screenshot-$cam" "$PIT_DASH"; then
      pass "Pit dashboard: screenshot-$cam card exists"
    else
      fail "Pit dashboard: screenshot-$cam card missing"
    fi
  done

  # Verify old camera names removed from grid (pov, roof, front - but NOT rear since it's an alias)
  for old_cam in "pov" "roof" "front"; do
    if grep -q "screenshot-$old_cam" "$PIT_DASH"; then
      fail "Pit dashboard: legacy screenshot-$old_cam should be removed"
    else
      pass "Pit dashboard: legacy screenshot-$old_cam removed"
    fi
  done
fi

# ── 7. TypeScript compiles (npm run build) ───────────────────
log "Step 7: npm run build passes"

cd "$REPO_ROOT/web"
if command -v npm &> /dev/null; then
  if npm run build > /tmp/cam_contract_build.log 2>&1; then
    pass "npm run build succeeded"
  else
    fail "npm run build failed"
    echo "      Build log (last 20 lines):"
    tail -20 /tmp/cam_contract_build.log | sed 's/^/      /'
  fi
else
  skip "npm not available - run 'npm run build' manually to verify"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED - Camera contract is consistent across Edge, Cloud, and Web"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
