#!/usr/bin/env bash
# cloud_watch_live_map_overlay_smoke.sh — Smoke test for CLOUD-UI-OVERLAY-1
#
# Validates that Watch Live map controls render inside the map container
# and do not leak into the page flow as raw text.
#
# Validates:
#   Map.tsx (shared map component):
#     1.  Map wrapper has overflow-hidden (clips overlays when container is zero-height)
#     2.  Map wrapper has position relative (positioning context for absolutes)
#     3.  Lock button uses absolute positioning (map-lock-button class)
#     4.  Lock button label ("Click to Pan") exists
#     5.  MapLegend uses absolute positioning
#     6.  Tile error banner uses absolute positioning
#     7.  No "Topo" toggle button (removed in MAP-STYLE-1)
#     8.  No "Streets" toggle button (removed in MAP-STYLE-1)
#   OverviewTab.tsx (Watch Live overview):
#     9.  Map section wrapper has overflow-hidden
#    10.  Map section wrapper has position relative
#    11.  "Center" button uses absolute positioning
#    12.  "No vehicles transmitting" banner uses absolute positioning
#    13.  Banner is conditional on positions.length === 0
#   CSS (index.css):
#    14.  map-lock-button class uses absolute positioning
#    15.  map-lock-button has z-index (z-20)
#
# Usage:
#   bash scripts/cloud_watch_live_map_overlay_smoke.sh
#
# Exit non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

log()  { echo "[map-overlay]  $*"; }
pass() { echo "[map-overlay]    PASS: $*"; }
fail() { echo "[map-overlay]    FAIL: $*"; FAIL=1; }

MAP_TSX="$REPO_ROOT/web/src/components/Map/Map.tsx"
OVERVIEW_TSX="$REPO_ROOT/web/src/components/RaceCenter/OverviewTab.tsx"
INDEX_CSS="$REPO_ROOT/web/src/index.css"

log "CLOUD-UI-OVERLAY-1: Map Overlay Containment Smoke Test"
echo ""

# ═══════════════════════════════════════════════════════════════════
# MAP.TSX — Shared Map Component
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$MAP_TSX" ]; then
  fail "Map.tsx not found"
  exit 1
fi

# ── 1. Map wrapper has overflow-hidden ─────────────────────────────
log "Step 1: Map wrapper has overflow-hidden"
if grep -q 'className="relative w-full h-full overflow-hidden"' "$MAP_TSX"; then
  pass "Map wrapper has overflow-hidden"
else
  fail "Map wrapper missing overflow-hidden (overlays can leak into page flow)"
fi

# ── 2. Map wrapper has position relative ───────────────────────────
log "Step 2: Map wrapper has position relative"
if grep -q 'className="relative' "$MAP_TSX"; then
  pass "Map wrapper has position relative"
else
  fail "Map wrapper missing position relative"
fi

# ── 3. Lock button uses absolute positioning ───────────────────────
log "Step 3: Lock button uses absolute positioning (map-lock-button)"
if grep -q 'map-lock-button' "$MAP_TSX"; then
  pass "Lock button uses map-lock-button class"
else
  fail "Lock button missing map-lock-button class"
fi

# ── 4. Lock button label exists ────────────────────────────────────
log "Step 4: Lock button label exists"
if grep -q 'Click to Pan' "$MAP_TSX"; then
  pass "Lock button has 'Click to Pan' label"
else
  fail "Lock button missing 'Click to Pan' label"
fi

# ── 5. MapLegend uses absolute positioning ─────────────────────────
log "Step 5: MapLegend uses absolute positioning"
if grep -q 'className="absolute bottom-2 left-2' "$MAP_TSX"; then
  pass "MapLegend uses absolute positioning"
else
  fail "MapLegend missing absolute positioning"
fi

# ── 6. Tile error banner uses absolute positioning ─────────────────
log "Step 6: Tile error banner uses absolute positioning"
# CLOUD-MAP-2: Banner text changed from "Basemap unavailable" to "Topo layer unavailable"
if grep -q 'Topo layer unavailable' "$MAP_TSX" && grep -B5 'Topo layer unavailable' "$MAP_TSX" | grep -q 'absolute'; then
  pass "Tile error banner uses absolute positioning"
else
  fail "Tile error banner missing absolute positioning"
fi

# ── 7. No "Topo" toggle button ─────────────────────────────────────
log "Step 7: No 'Topo' toggle button (removed in MAP-STYLE-1)"
if grep -qE ">'Topo'<|>Topo<" "$MAP_TSX"; then
  fail "'Topo' toggle button still present"
else
  pass "No 'Topo' toggle button"
fi

# ── 8. No "Streets" toggle button ──────────────────────────────────
log "Step 8: No 'Streets' toggle button (removed in MAP-STYLE-1)"
if grep -qE ">'Streets'<|>Streets<|'streets'" "$MAP_TSX"; then
  fail "'Streets' toggle button still present"
else
  pass "No 'Streets' toggle button"
fi

# ═══════════════════════════════════════════════════════════════════
# OVERVIEWTAB.TSX — Watch Live Overview
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$OVERVIEW_TSX" ]; then
  fail "OverviewTab.tsx not found"
  exit 1
fi

# ── 9. Map section wrapper has overflow-hidden ─────────────────────
log "Step 9: OverviewTab map section has overflow-hidden"
if grep -q 'overflow-hidden' "$OVERVIEW_TSX"; then
  pass "OverviewTab map section has overflow-hidden"
else
  fail "OverviewTab map section missing overflow-hidden"
fi

# ── 10. Map section wrapper has position relative ──────────────────
log "Step 10: OverviewTab map section has position relative"
# The map section should have "relative" in its className
if grep -B1 '<RaceMap' "$OVERVIEW_TSX" | grep -q 'relative'; then
  pass "OverviewTab map section has position relative"
else
  # Also check the parent div of RaceMap
  if grep -q 'className="relative flex-1' "$OVERVIEW_TSX"; then
    pass "OverviewTab map section has position relative"
  else
    fail "OverviewTab map section missing position relative"
  fi
fi

# ── 11. "Center" button uses absolute positioning ──────────────────
log "Step 11: 'Center' button uses absolute positioning"
# CenterOnRaceButton's className has "absolute" — check the function's button element
if grep -A20 'function CenterOnRaceButton' "$OVERVIEW_TSX" | grep -q 'className="absolute'; then
  pass "'Center' button uses absolute positioning"
else
  fail "'Center' button missing absolute positioning"
fi

# ── 12. "No vehicles transmitting" banner uses absolute positioning ─
log "Step 12: 'No vehicles transmitting' banner uses absolute positioning"
if grep -B3 'No vehicles transmitting' "$OVERVIEW_TSX" | grep -q 'absolute'; then
  pass "'No vehicles transmitting' banner uses absolute positioning"
else
  fail "'No vehicles transmitting' banner missing absolute positioning"
fi

# ── 13. Banner conditional on positions.length === 0 ───────────────
log "Step 13: Banner conditional on empty positions"
if grep -q 'positions.length === 0' "$OVERVIEW_TSX"; then
  pass "Banner conditional on positions.length === 0"
else
  fail "Banner not conditional on positions.length === 0"
fi

# ═══════════════════════════════════════════════════════════════════
# CSS — index.css
# ═══════════════════════════════════════════════════════════════════

if [ ! -f "$INDEX_CSS" ]; then
  fail "index.css not found"
  exit 1
fi

# ── 14. map-lock-button uses absolute positioning ──────────────────
log "Step 14: map-lock-button CSS uses absolute positioning"
if grep -A5 '\.map-lock-button' "$INDEX_CSS" | grep -q 'absolute'; then
  pass "map-lock-button uses absolute positioning"
else
  fail "map-lock-button missing absolute positioning in CSS"
fi

# ── 15. map-lock-button has z-index ────────────────────────────────
log "Step 15: map-lock-button has z-index"
if grep -A5 '\.map-lock-button' "$INDEX_CSS" | grep -q 'z-'; then
  pass "map-lock-button has z-index"
else
  fail "map-lock-button missing z-index in CSS"
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
