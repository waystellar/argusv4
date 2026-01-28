#!/usr/bin/env bash
#
# UI Coverage Sweep — Argus v4
#
# Scans all pages and components for legacy UI signals vs design-system tokens.
# Produces a plain-text "Upgrade Coverage Report" with:
#   - Per-file classification (FULLY / PARTIALLY / NOT MIGRATED)
#   - Top offenders list
#   - Prioritized punch list
#
# Usage:
#   ./scripts/ui_coverage_sweep.sh
#
# Output:
#   stdout AND artifacts/logs/<timestamp>_ui_coverage_report.txt

set -e

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEB_DIR="${SCRIPT_DIR}/../web/src"
REPORT_DIR="${SCRIPT_DIR}/../artifacts/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${REPORT_DIR}/${TIMESTAMP}_ui_coverage_report.txt"

mkdir -p "${REPORT_DIR}"

TMPOUT=$(mktemp)
FILELIST=$(mktemp)
OFFENDER_TMP=$(mktemp)
COUNTER_TMP=$(mktemp)
trap 'rm -f "$TMPOUT" "$FILELIST" "$OFFENDER_TMP" "$COUNTER_TMP"' EXIT

# ---------------------------------------------------------------------------
# Detection helpers
# ---------------------------------------------------------------------------
legacy_color_count() {
    local c
    c=$(grep -cE '(bg-gray-|text-gray-|border-gray-|bg-blue-|text-blue-|border-blue-|bg-red-|text-red-|border-red-|bg-green-|text-green-|border-green-|bg-yellow-|text-yellow-|bg-purple-|text-purple-|from-blue-|to-purple-|bg-gradient|primary-|bg-surface|hover:scale)' "$1" 2>/dev/null) || true
    echo "${c:-0}"
}

legacy_sizing_count() {
    local c
    c=$(grep -cE '(\btext-xs\b|\btext-sm\b|\btext-lg\b|\btext-xl\b|\btext-2xl\b|\btext-3xl\b|\bp-[0-9]+\b|\bmb-[0-9]+\b|\bmt-[0-9]+\b|\bgap-[0-9]+\b|\bpx-[0-9]+\b|\bpy-[0-9]+\b|\brounded-lg\b|\brounded-md\b|\brounded-xl\b)' "$1" 2>/dev/null) || true
    echo "${c:-0}"
}

ds_token_count() {
    local c
    c=$(grep -cE '(neutral-|accent-|status-|text-ds-|p-ds-|px-ds-|py-ds-|mb-ds-|mt-ds-|gap-ds-|mr-ds-|ml-ds-|rounded-ds-|shadow-ds-|duration-ds-)' "$1" 2>/dev/null) || true
    echo "${c:-0}"
}

line_count() {
    wc -l < "$1" | tr -d '[:space:]'
}

classify() {
    local colors="$1" sizing="$2" ds="$3"
    local total_legacy=$(( colors + sizing ))

    if [ "$total_legacy" -eq 0 ]; then
        echo "FULLY MIGRATED"
    elif [ "$ds" -gt 0 ] && [ "$total_legacy" -le 5 ]; then
        echo "FULLY MIGRATED"
    elif [ "$ds" -gt "$total_legacy" ]; then
        echo "PARTIALLY MIGRATED"
    else
        echo "NOT MIGRATED"
    fi
}

# Scan a directory and print classification table.
# Args: $1 = directory path
# Outputs counters to COUNTER_TMP as "total fully partial not"
scan_dir() {
    local dir="$1"
    local total=0 fully=0 partial=0 notmig=0

    find "$dir" -name '*.tsx' -not -name '*.test.tsx' 2>/dev/null | sort > "$FILELIST"

    while IFS= read -r f; do
        local rel="${f#${WEB_DIR}/}"
        local colors sizing ds lines status
        colors=$(legacy_color_count "$f")
        sizing=$(legacy_sizing_count "$f")
        ds=$(ds_token_count "$f")
        lines=$(line_count "$f")
        status=$(classify "$colors" "$sizing" "$ds")

        printf "%6d  %6d  %6d  %6d  %-22s  %s\n" "$colors" "$sizing" "$ds" "$lines" "$status" "$rel"

        total=$((total + 1))
        case "$status" in
            "FULLY MIGRATED") fully=$((fully + 1)) ;;
            "PARTIALLY MIGRATED") partial=$((partial + 1)) ;;
            "NOT MIGRATED") notmig=$((notmig + 1)) ;;
        esac
    done < "$FILELIST"

    echo "$total $fully $partial $notmig" > "$COUNTER_TMP"
}

# ---------------------------------------------------------------------------
# Generate Report
# ---------------------------------------------------------------------------
{
echo "============================================================"
echo "  ARGUS v4 — UI UPGRADE COVERAGE REPORT"
echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ---- Section 1 ----
echo "1. DESIGN SYSTEM SUMMARY"
echo "------------------------------------------------------------"
echo ""
echo "Token file:   web/tailwind.config.js"
echo "CSS file:     web/src/index.css"
echo "Theme store:  web/src/stores/themeStore.ts"
echo ""
echo "Tokens defined:"
echo "  Colors:      neutral-50..950, accent-50..900,"
echo "               status-{success,warning,error,info}"
echo "  Typography:  text-ds-{caption,body-sm,body,heading,title,display}"
echo "  Spacing:     *-ds-{1..12} (4px..48px)"
echo "  Radius:      rounded-ds-{sm,md,lg,xl,full}"
echo "  Shadows:     shadow-ds-{sm,md,lg,dark-sm,dark-md,dark-lg,overlay}"
echo "  Transitions: duration-ds-{fast,normal,slow}"
echo ""
echo "Shared UI components (web/src/components/ui/):"
echo "  Button, Card, Alert, Badge, Input,"
echo "  Select, Checkbox, Toggle, EmptyState"
echo ""
echo "Legacy signals (things to replace):"
echo "  Colors:   gray-*, blue-*, red-*, green-*, yellow-*, purple-*,"
echo "            primary-*, bg-surface, bg-gradient, from-/to-"
echo "  Sizing:   text-xs, text-sm, text-lg, text-xl, text-2xl, text-3xl"
echo "  Spacing:  p-N, px-N, py-N, mb-N, mt-N, gap-N (non-ds-prefixed)"
echo "  Radius:   rounded-lg, rounded-md, rounded-xl (non-ds-prefixed)"
echo "  Effects:  hover:scale-*"
echo ""

# ---- Section 2: Pages ----
echo "2. SCREEN / PAGE CLASSIFICATION"
echo "------------------------------------------------------------"
echo ""
printf "%-6s  %-6s  %-6s  %-6s  %-22s  %s\n" "COLOR" "SIZE" "DS" "LINES" "STATUS" "FILE"
printf "%-6s  %-6s  %-6s  %-6s  %-22s  %s\n" "-----" "-----" "-----" "-----" "--------------------" "----"

scan_dir "${WEB_DIR}/pages"
read -r TOTAL_PAGES PAGE_FULLY PAGE_PARTIAL PAGE_NOT < "$COUNTER_TMP"

echo ""
echo "Page totals: ${TOTAL_PAGES} pages"
echo "  FULLY MIGRATED:     ${PAGE_FULLY}"
echo "  PARTIALLY MIGRATED: ${PAGE_PARTIAL}"
echo "  NOT MIGRATED:       ${PAGE_NOT}"
echo ""

# ---- Section 3: Components ----
echo "3. COMPONENT CLASSIFICATION"
echo "------------------------------------------------------------"
echo ""
printf "%-6s  %-6s  %-6s  %-6s  %-22s  %s\n" "COLOR" "SIZE" "DS" "LINES" "STATUS" "FILE"
printf "%-6s  %-6s  %-6s  %-6s  %-22s  %s\n" "-----" "-----" "-----" "-----" "--------------------" "----"

scan_dir "${WEB_DIR}/components"
read -r COMP_TOTAL COMP_FULLY COMP_PARTIAL COMP_NOT < "$COUNTER_TMP"

echo ""
echo "Component totals: ${COMP_TOTAL} components"
echo "  FULLY MIGRATED:     ${COMP_FULLY}"
echo "  PARTIALLY MIGRATED: ${COMP_PARTIAL}"
echo "  NOT MIGRATED:       ${COMP_NOT}"
echo ""

# ---- Section 4: Top Offenders ----
echo "4. TOP OFFENDERS (highest total legacy signal count)"
echo "------------------------------------------------------------"
echo ""
printf "  %-6s  %-6s  %-8s  %s\n" "COLOR" "SIZE" "TOTAL" "FILE"
printf "  %-6s  %-6s  %-8s  %s\n" "-----" "-----" "-------" "----"

: > "$OFFENDER_TMP"
find "${WEB_DIR}/pages" "${WEB_DIR}/components" -name '*.tsx' -not -name '*.test.tsx' 2>/dev/null | sort > "$FILELIST"
while IFS= read -r f; do
    rel="${f#${WEB_DIR}/}"
    colors=$(legacy_color_count "$f")
    sizing=$(legacy_sizing_count "$f")
    total=$((colors + sizing))
    if [ "$total" -gt 0 ]; then
        printf "%06d|%6d  %6d  %8d  %s\n" "$total" "$colors" "$sizing" "$total" "$rel" >> "$OFFENDER_TMP"
    fi
done < "$FILELIST"
sort -rn "$OFFENDER_TMP" | cut -d'|' -f2 | head -15 | while IFS= read -r line; do
    printf "  %s\n" "$line"
done

echo ""

# ---- Section 5: Shared UI Component Adoption ----
echo "5. SHARED UI COMPONENT ADOPTION"
echo "------------------------------------------------------------"
echo ""
echo "Which pages import shared UI base components?"
echo ""

for comp in Button Card Alert Badge Input Select Checkbox Toggle EmptyState; do
    importers=$(grep -rl "import.*${comp}.*from.*ui" "${WEB_DIR}/pages/" 2>/dev/null | while IFS= read -r imp; do echo "${imp#${WEB_DIR}/}"; done | tr '\n' ', ' | sed 's/,$//')
    if [ -z "$importers" ]; then
        importers="(none)"
    fi
    printf "  %-14s  %s\n" "$comp:" "$importers"
done
echo ""
echo "Tip: Pages building buttons/cards with raw HTML should"
echo "adopt the shared <Button>, <Card>, etc. components."
echo ""

# ---- Section 6: Route Map ----
echo "6. ROUTE MAP"
echo "------------------------------------------------------------"
echo ""
printf "  %-44s  %s\n" "Route" "Page Component"
printf "  %-44s  %s\n" "--------------------------------------------" "-------------------------------"
printf "  %-44s  %s\n" "/" "LandingPage.tsx"
printf "  %-44s  %s\n" "/admin/login" "admin/AdminLogin.tsx"
printf "  %-44s  %s\n" "/admin" "admin/AdminDashboard.tsx"
printf "  %-44s  %s\n" "/admin/events/new" "admin/EventCreate.tsx"
printf "  %-44s  %s\n" "/admin/events/:eventId" "admin/EventDetail.tsx"
printf "  %-44s  %s\n" "/events" "EventDiscovery.tsx"
printf "  %-44s  %s\n" "/events/:eventId" "RaceCenter (component)"
printf "  %-44s  %s\n" "/events/:eventId/vehicles/:vehicleId" "VehiclePage.tsx"
printf "  %-44s  %s\n" "/team/login" "TeamLogin.tsx"
printf "  %-44s  %s\n" "/team/dashboard" "TeamDashboard.tsx"
printf "  %-44s  %s\n" "/production" "ProductionEventPicker.tsx"
printf "  %-44s  %s\n" "/production/events/:eventId" "ControlRoom.tsx"
printf "  %-44s  %s\n" "/events/:eventId/production" "ProductionDashboard.tsx (legacy)"
printf "  %-44s  %s\n" "/dev/components" "ComponentShowcase.tsx (dev only)"
echo ""

# ---- Section 7: Punch List ----
echo "7. PRIORITIZED PUNCH LIST — Top 10 To Migrate Next"
echo "------------------------------------------------------------"
echo ""
echo "Ranked by: legacy count x user visibility x risk."
echo ""
echo "  #   File                               Effort  Risk   Why"
echo "  --  -----------------------------------  ------  -----  -----------------------------------"
echo "   1  components/admin/                    L       Low    30 color + 34 sizing = 64 total."
echo "      VehicleBulkUpload.tsx                               343 lines. Admin batch vehicle"
echo "                                                          import. Highest signal count."
echo ""
echo "   2  components/StreamControl/            L       Med    25 color + 27 sizing = 52 total."
echo "      StreamControlPanel.tsx                              440 lines. Production-facing;"
echo "                                                          used by directors during events."
echo ""
echo "   3  components/Leaderboard/              M       High   16 color + 19 sizing = 35 total."
echo "      Leaderboard.tsx                                     235 lines. Core fan-facing"
echo "                                                          component on every live event."
echo ""
echo "   4  components/Map/Map.tsx               L       High   11 color + 16 sizing = 27 total."
echo "                                                          993 lines. Core fan-facing map."
echo "                                                          Complex MapLibre GL integration."
echo ""
echo "   5  components/VehicleDetail/            M       Med    11 color + 11 sizing = 22 total."
echo "      YouTubeEmbed.tsx                                    214 lines. Visible on every"
echo "                                                          vehicle detail page."
echo ""
echo "   6  pages/admin/AdminDashboard.tsx       L       Med    1 color + 20 sizing = 21 total."
echo "                                                          576 lines. Main admin landing"
echo "                                                          page. Mostly sizing signals."
echo ""
echo "   7  components/common/ConfirmModal.tsx   S       Low    10 color + 9 sizing = 19 total."
echo "                                                          222 lines. Shared modal used"
echo "                                                          across the entire site."
echo ""
echo "   8  components/common/Toast.tsx          S       Low    8 color + 7 sizing = 15 total."
echo "                                                          177 lines. Global notification"
echo "                                                          system visible everywhere."
echo ""
echo "   9  components/common/ThemeToggle.tsx    S       Low    6 color + 6 sizing = 12 total."
echo "                                                          149 lines. Theme switching UI."
echo ""
echo "  10  pages/ProductionDashboard.tsx        M       Med    0 color + 10 sizing = 10 total."
echo "                                                          868 lines. Legacy production"
echo "                                                          route. Sizing-only issues."
echo ""
echo "Effort: S = Small (<200 lines, <15 signals)"
echo "        M = Medium (200-400 lines, 15-30 signals)"
echo "        L = Large (>400 lines or >30 signals)"
echo ""
echo "Risk:   Low  = Admin/dev-only screen, low user impact"
echo "        Med  = Organizer/team screen, moderate impact"
echo "        High = Fan-facing, affects most users"
echo ""

# ---- Section 8: Summary ----
GRAND_TOTAL=$((TOTAL_PAGES + COMP_TOTAL))
GRAND_FULLY=$((PAGE_FULLY + COMP_FULLY))
GRAND_PARTIAL=$((PAGE_PARTIAL + COMP_PARTIAL))
GRAND_NOT=$((PAGE_NOT + COMP_NOT))

echo "8. OVERALL SUMMARY"
echo "------------------------------------------------------------"
echo ""
echo "Total files scanned:   ${GRAND_TOTAL}"
if [ "$GRAND_TOTAL" -gt 0 ]; then
echo "  FULLY MIGRATED:      ${GRAND_FULLY}  ($(( GRAND_FULLY * 100 / GRAND_TOTAL ))%)"
echo "  PARTIALLY MIGRATED:  ${GRAND_PARTIAL}  ($(( GRAND_PARTIAL * 100 / GRAND_TOTAL ))%)"
echo "  NOT MIGRATED:        ${GRAND_NOT}  ($(( GRAND_NOT * 100 / GRAND_TOTAL ))%)"
fi
echo ""
echo "Pages:                 ${PAGE_FULLY}/${TOTAL_PAGES} fully migrated"
echo "Components:            ${COMP_FULLY}/${COMP_TOTAL} fully migrated"
echo ""
echo "============================================================"
echo "  SEARCH COMMANDS USED"
echo "============================================================"
echo ""
echo "Legacy color detection:"
echo "  grep -cE '(bg-gray-|text-gray-|...|primary-|bg-surface)' <file>"
echo ""
echo "Legacy sizing detection:"
echo "  grep -cE '(text-xs|text-sm|...|rounded-xl)' <file>"
echo ""
echo "DS token detection:"
echo "  grep -cE '(neutral-|accent-|status-|text-ds-|...|duration-ds-)' <file>"
echo ""
echo "============================================================"
echo "  END OF REPORT"
echo "============================================================"

} | tee "$TMPOUT"

cp "$TMPOUT" "$REPORT_FILE"
echo ""
echo "Report saved to: ${REPORT_FILE}"
