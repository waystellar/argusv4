#!/usr/bin/env bash
# camera_slot_strings_guard.sh - Guard script for CAM-CONTRACT-1B: Camera Slot Strings
#
# Ensures no unauthorized camera slot strings are introduced in the codebase.
# Canonical slots: main, cockpit, chase, suspension
# Allowed legacy aliases: pov, roof, front, rear (must map to canonical)
#
# This script should be run in CI/CD to prevent regression.
#
# Usage:
#   bash scripts/camera_slot_strings_guard.sh
#
# Exit non-zero if unauthorized camera strings found.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[cam-guard]  $*"; }
pass() { echo "[cam-guard]    PASS: $*"; }
fail() { echo "[cam-guard]    FAIL: $*"; FAIL=1; }
warn() { echo "[cam-guard]    WARN: $*"; }

log "CAM-CONTRACT-1B: Camera Slot Strings Guard"
echo ""

# Canonical camera slots (the ONLY valid canonical names)
CANONICAL_CAMERAS=("main" "cockpit" "chase" "suspension")

# Legacy aliases (allowed in alias maps, not as canonical definitions)
LEGACY_ALIASES=("pov" "roof" "front" "rear" "cam0" "camera" "default")

# Old/retired camera names that should NEVER appear except in migration comments
RETIRED_NAMES=("cam1" "cam2" "cam3" "cam4" "onboard" "external" "helmet" "bumper" "side")

# Files to check
EDGE_FILES=(
  "edge/stream_profiles.py"
  "edge/video_director.py"
  "edge/pit_crew_dashboard.py"
)

CLOUD_FILES=(
  "cloud/app/routes/production.py"
)

WEB_FILES=(
  "web/src/components/StreamControl/StreamControlPanel.tsx"
  "web/src/components/Team/VideoFeedManager.tsx"
  "web/src/pages/VehiclePage.tsx"
  "web/src/pages/ControlRoom.tsx"
  "web/src/pages/ProductionDashboard.tsx"
)

# ── 1. Check for retired camera names ────────────────────────
log "Step 1: Check for retired camera names"

for retired in "${RETIRED_NAMES[@]}"; do
  # Search in Edge files
  for file in "${EDGE_FILES[@]}"; do
    filepath="$REPO_ROOT/$file"
    if [ -f "$filepath" ]; then
      # Look for retired name in camera-related contexts (quotes, variables)
      if grep -n "\"$retired\"" "$filepath" 2>/dev/null | grep -v "# retired\|# legacy\|# migration" > /dev/null; then
        fail "Retired camera name '$retired' found in $(basename "$filepath")"
        grep -n "\"$retired\"" "$filepath" | head -3 | sed 's/^/         /'
      fi
    fi
  done

  # Search in Cloud files
  for file in "${CLOUD_FILES[@]}"; do
    filepath="$REPO_ROOT/$file"
    if [ -f "$filepath" ]; then
      if grep -n "\"$retired\"" "$filepath" 2>/dev/null | grep -v "# retired\|# legacy\|# migration" > /dev/null; then
        fail "Retired camera name '$retired' found in $(basename "$filepath")"
        grep -n "\"$retired\"" "$filepath" | head -3 | sed 's/^/         /'
      fi
    fi
  done

  # Search in Web files
  for file in "${WEB_FILES[@]}"; do
    filepath="$REPO_ROOT/$file"
    if [ -f "$filepath" ]; then
      if grep -n "'$retired'\|\"$retired\"" "$filepath" 2>/dev/null | grep -v "// retired\|// legacy\|// migration" > /dev/null; then
        fail "Retired camera name '$retired' found in $(basename "$filepath")"
        grep -n "'$retired'\|\"$retired\"" "$filepath" | head -3 | sed 's/^/         /'
      fi
    fi
  done
done

if [ "$FAIL" -eq 0 ]; then
  pass "No retired camera names found"
fi

# ── 2. Verify canonical cameras are primary in definitions ───
log "Step 2: Verify canonical cameras are primary definitions"

# Check Edge stream_profiles.py has VALID_CAMERAS with exactly the 4 canonical
EDGE_STREAM="$REPO_ROOT/edge/stream_profiles.py"
if [ -f "$EDGE_STREAM" ]; then
  # Count canonical cameras in VALID_CAMERAS tuple/set definition
  canonical_count=0
  for cam in "${CANONICAL_CAMERAS[@]}"; do
    if grep 'VALID_CAMERAS\s*=' "$EDGE_STREAM" | grep -q "\"$cam\""; then
      ((canonical_count++)) || true
    fi
  done

  if [ "$canonical_count" -eq 4 ]; then
    pass "Edge VALID_CAMERAS has all 4 canonical cameras"
  else
    fail "Edge VALID_CAMERAS missing canonical cameras (found $canonical_count/4)"
  fi
fi

# Check Cloud production.py has CANONICAL_CAMERAS with exactly the 4 canonical
CLOUD_PROD="$REPO_ROOT/cloud/app/routes/production.py"
if [ -f "$CLOUD_PROD" ]; then
  canonical_count=0
  for cam in "${CANONICAL_CAMERAS[@]}"; do
    if grep 'CANONICAL_CAMERAS\s*=' "$CLOUD_PROD" | grep -q "\"$cam\""; then
      ((canonical_count++)) || true
    fi
  done

  if [ "$canonical_count" -eq 4 ]; then
    pass "Cloud CANONICAL_CAMERAS has all 4 canonical cameras"
  else
    fail "Cloud CANONICAL_CAMERAS missing canonical cameras (found $canonical_count/4)"
  fi
fi

# ── 3. Verify legacy aliases map to canonical names ──────────
log "Step 3: Verify legacy aliases map to canonical names"

# Check Edge CAMERA_SLOT_ALIASES - search for dict entry pattern
if [ -f "$EDGE_STREAM" ]; then
  # Each legacy alias should map to a canonical name
  for legacy in "${LEGACY_ALIASES[@]}"; do
    # Look for dict entry pattern: starts with whitespace, "legacy": "canonical", ends with comma
    alias_line=$(grep -E "^[[:space:]]+\"$legacy\"[[:space:]]*:[[:space:]]*\"[a-z]+\"," "$EDGE_STREAM" 2>/dev/null | head -1 || true)
    if [ -n "$alias_line" ]; then
      maps_to_canonical=false
      for canonical in "${CANONICAL_CAMERAS[@]}"; do
        if echo "$alias_line" | grep -q "\"$canonical\""; then
          maps_to_canonical=true
          break
        fi
      done
      if [ "$maps_to_canonical" = true ]; then
        pass "Edge: '$legacy' alias maps to canonical"
      else
        fail "Edge: '$legacy' alias does NOT map to canonical camera"
      fi
    fi
  done
fi

# Check Cloud CAMERA_SLOT_ALIASES - search for dict entry pattern
if [ -f "$CLOUD_PROD" ]; then
  for legacy in "${LEGACY_ALIASES[@]}"; do
    # Look for dict entry pattern: starts with whitespace, "legacy": "canonical", ends with comma
    # This matches lines like:     "camera": "main",
    alias_line=$(grep -E "^[[:space:]]+\"$legacy\"[[:space:]]*:[[:space:]]*\"[a-z]+\"," "$CLOUD_PROD" 2>/dev/null | head -1 || true)
    if [ -n "$alias_line" ]; then
      maps_to_canonical=false
      for canonical in "${CANONICAL_CAMERAS[@]}"; do
        if echo "$alias_line" | grep -q "\"$canonical\""; then
          maps_to_canonical=true
          break
        fi
      done
      if [ "$maps_to_canonical" = true ]; then
        pass "Cloud: '$legacy' alias maps to canonical"
      else
        fail "Cloud: '$legacy' alias does NOT map to canonical camera"
      fi
    fi
  done
fi

# ── 4. Check Web components use canonical cameras ────────────
log "Step 4: Web components use canonical cameras in labels"

for file in "${WEB_FILES[@]}"; do
  filepath="$REPO_ROOT/$file"
  if [ -f "$filepath" ]; then
    basename=$(basename "$filepath")

    # Check that 'suspension' appears (CAM-CONTRACT-1B key indicator)
    if grep -q "suspension" "$filepath"; then
      pass "$basename: uses 'suspension' (CAM-CONTRACT-1B compliant)"
    else
      fail "$basename: missing 'suspension' - may be using old 'rear' canonical name"
    fi

    # Warn if 'rear' appears in CAMERA_LABELS (should only be in alias mappings)
    if grep 'CAMERA_LABELS' "$filepath" | grep -q "'rear'\|\"rear\""; then
      fail "$basename: 'rear' in CAMERA_LABELS (should be 'suspension')"
    fi
  fi
done

# ── 5. Check for typos/variations ────────────────────────────
log "Step 5: Check for common typos and variations"

TYPOS=("cockpit_cam" "chase_cam" "main_cam" "suspension_cam" "maincam" "chasecam" "cockpitcam" "suspensioncam")

for typo in "${TYPOS[@]}"; do
  # Search all source files
  found=$(grep -r "$typo" "$REPO_ROOT/edge" "$REPO_ROOT/cloud" "$REPO_ROOT/web/src" 2>/dev/null | grep -v ".pyc\|node_modules\|dist" | head -3 || true)
  if [ -n "$found" ]; then
    warn "Possible typo/variation '$typo' found:"
    echo "$found" | sed 's/^/         /'
  fi
done
pass "Typo check complete"

# ── 6. Verify CAM-CONTRACT-1B markers ────────────────────────
log "Step 6: Verify CAM-CONTRACT-1B markers in key files"

KEY_FILES=(
  "edge/stream_profiles.py"
  "edge/video_director.py"
  "edge/pit_crew_dashboard.py"
  "cloud/app/routes/production.py"
)

for keyfile in "${KEY_FILES[@]}"; do
  filepath="$REPO_ROOT/$keyfile"
  if [ -f "$filepath" ]; then
    if grep -q 'CAM-CONTRACT-1B' "$filepath"; then
      pass "$(basename "$keyfile") has CAM-CONTRACT-1B marker"
    else
      fail "$(basename "$keyfile") missing CAM-CONTRACT-1B marker"
    fi
  fi
done

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  CAM-CONTRACT-1B Camera Slot Strings Summary"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Canonical Cameras: ${CANONICAL_CAMERAS[*]}"
echo "  Legacy Aliases:    ${LEGACY_ALIASES[*]}"
echo "  Retired Names:     ${RETIRED_NAMES[*]}"
echo ""

if [ "$FAIL" -eq 0 ]; then
  log "ALL GUARD CHECKS PASSED"
  echo ""
  echo "  The codebase is compliant with CAM-CONTRACT-1B."
  echo "  All camera slot strings use canonical names or valid aliases."
  echo ""
  exit 0
else
  log "GUARD CHECKS FAILED"
  echo ""
  echo "  Please fix the above issues before merging."
  echo "  Canonical cameras: main, cockpit, chase, suspension"
  echo "  Legacy names (pov, roof, front, rear) should only appear in alias maps."
  echo ""
  exit 1
fi
