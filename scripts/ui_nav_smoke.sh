#!/usr/bin/env bash
# ui_nav_smoke.sh — Smoke test for UI navigation foundations.
# Usage: bash scripts/ui_nav_smoke.sh fan|team|production|admin|all
#
# Checks:
#   1. Web project builds successfully (Docker-based tsc + vite build)
#   2. PageHeader component and useSafeBack hook exist and export correctly
#   3. Area-specific presence checks (grep for navigate targets per area)
#
# Exit non-zero on any failure.
set -euo pipefail

AREA="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"
FAIL=0

log()  { echo "[nav-smoke] $*"; }
pass() { echo "[nav-smoke]   PASS: $*"; }
fail() { echo "[nav-smoke]   FAIL: $*"; FAIL=1; }

# ── 1. Build check (tsc + vite build via Docker) ────────────────────
log "Step 1: Build check (Docker)"
if docker run --rm -v "$WEB_DIR":/app -w /app node:20-alpine \
    sh -c "npm ci --ignore-scripts 2>/dev/null && ./node_modules/.bin/tsc --noEmit && ./node_modules/.bin/vite build" \
    > /tmp/nav_smoke_build.log 2>&1; then
  pass "tsc --noEmit + vite build"
else
  fail "Build failed. Last 20 lines:"
  tail -20 /tmp/nav_smoke_build.log
fi

# ── 2. Foundation presence checks ───────────────────────────────────
log "Step 2: Foundation presence checks"

# useSafeBack hook exists and exports the function
HOOK_FILE="$WEB_DIR/src/hooks/useSafeBack.ts"
if [ -f "$HOOK_FILE" ]; then
  if grep -q "export function useSafeBack" "$HOOK_FILE"; then
    pass "useSafeBack hook exists and exports"
  else
    fail "useSafeBack.ts exists but missing export"
  fi
else
  fail "useSafeBack.ts not found"
fi

# PageHeader component exists and exports
PH_FILE="$WEB_DIR/src/components/common/PageHeader.tsx"
if [ -f "$PH_FILE" ]; then
  if grep -q "export default function PageHeader" "$PH_FILE"; then
    pass "PageHeader component exists and exports"
  else
    fail "PageHeader.tsx exists but missing default export"
  fi
else
  fail "PageHeader.tsx not found"
fi

# PageHeader re-exported from barrel
BARREL="$WEB_DIR/src/components/common/index.ts"
if grep -q "PageHeader" "$BARREL"; then
  pass "PageHeader re-exported from common/index.ts"
else
  fail "PageHeader not in common/index.ts barrel"
fi

# ── 3. Area-specific checks ─────────────────────────────────────────
log "Step 3: Area navigation checks (area=$AREA)"

check_fan() {
  # Fan routes: /events, /events/:id, /events/:id/vehicles/:vid

  # EventDiscovery uses PageHeader with backTo="/"
  if grep -q "PageHeader" "$WEB_DIR/src/pages/EventDiscovery.tsx" 2>/dev/null; then
    pass "Fan: EventDiscovery uses PageHeader"
  else
    fail "Fan: EventDiscovery missing PageHeader"
  fi
  if grep -q 'backTo="/"' "$WEB_DIR/src/pages/EventDiscovery.tsx" 2>/dev/null; then
    pass "Fan: EventDiscovery backTo=/ (Home fallback)"
  else
    fail "Fan: EventDiscovery missing backTo"
  fi

  # RaceCenter uses useSafeBack + Home button
  if grep -q "useSafeBack" "$WEB_DIR/src/components/RaceCenter/RaceCenter.tsx" 2>/dev/null; then
    pass "Fan: RaceCenter uses useSafeBack"
  else
    fail "Fan: RaceCenter missing useSafeBack"
  fi
  if grep -q 'aria-label="Home"' "$WEB_DIR/src/components/RaceCenter/RaceCenter.tsx" 2>/dev/null; then
    pass "Fan: RaceCenter has Home button"
  else
    fail "Fan: RaceCenter missing Home button"
  fi

  # VehiclePage uses PageHeader with backTo containing eventId
  if grep -q "PageHeader" "$WEB_DIR/src/pages/VehiclePage.tsx" 2>/dev/null; then
    pass "Fan: VehiclePage uses PageHeader"
  else
    fail "Fan: VehiclePage missing PageHeader"
  fi
  if grep -q 'backTo={.*eventId' "$WEB_DIR/src/pages/VehiclePage.tsx" 2>/dev/null; then
    pass "Fan: VehiclePage backTo includes eventId"
  else
    fail "Fan: VehiclePage missing backTo with eventId"
  fi
}

check_team() {
  # TeamLogin uses PageHeader with backTo="/"
  if grep -q "PageHeader" "$WEB_DIR/src/pages/TeamLogin.tsx" 2>/dev/null; then
    pass "Team: TeamLogin uses PageHeader"
  else
    fail "Team: TeamLogin missing PageHeader"
  fi
  if grep -q 'backTo="/"' "$WEB_DIR/src/pages/TeamLogin.tsx" 2>/dev/null; then
    pass "Team: TeamLogin backTo=/ (Home fallback)"
  else
    fail "Team: TeamLogin missing backTo"
  fi

  # TeamDashboard uses PageHeader with backTo="/team/login"
  if grep -q "PageHeader" "$WEB_DIR/src/pages/TeamDashboard.tsx" 2>/dev/null; then
    pass "Team: TeamDashboard uses PageHeader"
  else
    fail "Team: TeamDashboard missing PageHeader"
  fi
  if grep -q 'backTo="/team/login"' "$WEB_DIR/src/pages/TeamDashboard.tsx" 2>/dev/null; then
    pass "Team: TeamDashboard backTo=/team/login"
  else
    fail "Team: TeamDashboard missing backTo"
  fi

  # No role leakage: no /admin or /production links
  if grep -q 'to="/admin\|navigate.*"/admin\|to="/production\|navigate.*"/production' "$WEB_DIR/src/pages/TeamLogin.tsx" 2>/dev/null; then
    fail "Team: TeamLogin has cross-role link (admin/production)"
  else
    pass "Team: TeamLogin no role leakage"
  fi
  if grep -q 'to="/admin\|navigate.*"/admin\|to="/production\|navigate.*"/production' "$WEB_DIR/src/pages/TeamDashboard.tsx" 2>/dev/null; then
    fail "Team: TeamDashboard has cross-role link (admin/production)"
  else
    pass "Team: TeamDashboard no role leakage"
  fi
}

check_production() {
  # ProductionEventPicker uses PageHeader with backTo="/"
  if grep -q "PageHeader" "$WEB_DIR/src/pages/ProductionEventPicker.tsx" 2>/dev/null; then
    pass "Production: ProductionEventPicker uses PageHeader"
  else
    fail "Production: ProductionEventPicker missing PageHeader"
  fi
  if grep -q 'backTo="/"' "$WEB_DIR/src/pages/ProductionEventPicker.tsx" 2>/dev/null; then
    pass "Production: ProductionEventPicker backTo=/ (Home fallback)"
  else
    fail "Production: ProductionEventPicker missing backTo"
  fi

  # ControlRoom uses useSafeBack + Home button
  if grep -q "useSafeBack" "$WEB_DIR/src/pages/ControlRoom.tsx" 2>/dev/null; then
    pass "Production: ControlRoom uses useSafeBack"
  else
    fail "Production: ControlRoom missing useSafeBack"
  fi
  if grep -q 'aria-label="Home"' "$WEB_DIR/src/pages/ControlRoom.tsx" 2>/dev/null; then
    pass "Production: ControlRoom has Home button"
  else
    fail "Production: ControlRoom missing Home button"
  fi

  # ProductionDashboard uses PageHeader with backTo containing eventId
  if grep -q "PageHeader" "$WEB_DIR/src/pages/ProductionDashboard.tsx" 2>/dev/null; then
    pass "Production: ProductionDashboard uses PageHeader"
  else
    fail "Production: ProductionDashboard missing PageHeader"
  fi
  if grep -q 'backTo={.*eventId' "$WEB_DIR/src/pages/ProductionDashboard.tsx" 2>/dev/null; then
    pass "Production: ProductionDashboard backTo includes eventId"
  else
    fail "Production: ProductionDashboard missing backTo with eventId"
  fi

  # No role leakage: no /team links in production pages
  if grep -q 'to="/team\|navigate.*"/team' "$WEB_DIR/src/pages/ProductionEventPicker.tsx" 2>/dev/null; then
    fail "Production: ProductionEventPicker has cross-role link (team)"
  else
    pass "Production: ProductionEventPicker no role leakage"
  fi
}

check_admin() {
  # AdminLogin uses PageHeader with backTo="/"
  if grep -q "PageHeader" "$WEB_DIR/src/pages/admin/AdminLogin.tsx" 2>/dev/null; then
    pass "Admin: AdminLogin uses PageHeader"
  else
    fail "Admin: AdminLogin missing PageHeader"
  fi
  if grep -q 'backTo="/"' "$WEB_DIR/src/pages/admin/AdminLogin.tsx" 2>/dev/null; then
    pass "Admin: AdminLogin backTo=/ (Home fallback)"
  else
    fail "Admin: AdminLogin missing backTo"
  fi

  # AdminDashboard uses PageHeader with backTo="/"
  if grep -q "PageHeader" "$WEB_DIR/src/pages/admin/AdminDashboard.tsx" 2>/dev/null; then
    pass "Admin: AdminDashboard uses PageHeader"
  else
    fail "Admin: AdminDashboard missing PageHeader"
  fi
  if grep -q 'backTo="/"' "$WEB_DIR/src/pages/admin/AdminDashboard.tsx" 2>/dev/null; then
    pass "Admin: AdminDashboard backTo=/ (Home fallback)"
  else
    fail "Admin: AdminDashboard missing backTo"
  fi

  # EventCreate uses PageHeader with backTo="/admin"
  if grep -q "PageHeader" "$WEB_DIR/src/pages/admin/EventCreate.tsx" 2>/dev/null; then
    pass "Admin: EventCreate uses PageHeader"
  else
    fail "Admin: EventCreate missing PageHeader"
  fi
  if grep -q 'backTo="/admin"' "$WEB_DIR/src/pages/admin/EventCreate.tsx" 2>/dev/null; then
    pass "Admin: EventCreate backTo=/admin"
  else
    fail "Admin: EventCreate missing backTo=/admin"
  fi

  # EventDetail uses PageHeader with backTo="/admin"
  if grep -q "PageHeader" "$WEB_DIR/src/pages/admin/EventDetail.tsx" 2>/dev/null; then
    pass "Admin: EventDetail uses PageHeader"
  else
    fail "Admin: EventDetail missing PageHeader"
  fi
  if grep -q 'backTo="/admin"' "$WEB_DIR/src/pages/admin/EventDetail.tsx" 2>/dev/null; then
    pass "Admin: EventDetail backTo=/admin"
  else
    fail "Admin: EventDetail missing backTo=/admin"
  fi

  # Bug fix: EventDetail error state points to /admin (not /)
  if grep -q 'to="/admin"' "$WEB_DIR/src/pages/admin/EventDetail.tsx" 2>/dev/null; then
    pass "Admin: EventDetail error state links to /admin"
  else
    fail "Admin: EventDetail error state still links to /"
  fi

  # Bug fix: EventDetail delete handler navigates to /admin
  if grep -q "navigate('/admin')" "$WEB_DIR/src/pages/admin/EventDetail.tsx" 2>/dev/null; then
    pass "Admin: EventDetail delete navigates to /admin"
  else
    fail "Admin: EventDetail delete still navigates to /"
  fi

  # No stale to="/" back links in admin pages (except AdminLogin/AdminDashboard which correctly go to /)
  if grep -q 'to="/"' "$WEB_DIR/src/pages/admin/EventCreate.tsx" 2>/dev/null; then
    fail "Admin: EventCreate still has to=/ link (should be /admin)"
  else
    pass "Admin: EventCreate no stale to=/ links"
  fi
  if grep -q 'to="/"' "$WEB_DIR/src/pages/admin/EventDetail.tsx" 2>/dev/null; then
    fail "Admin: EventDetail still has to=/ link (should be /admin)"
  else
    pass "Admin: EventDetail no stale to=/ links"
  fi
}

case "$AREA" in
  fan)        check_fan ;;
  team)       check_team ;;
  production) check_production ;;
  admin)      check_admin ;;
  all)        check_fan; check_team; check_production; check_admin ;;
  *)          echo "Usage: $0 fan|team|production|admin|all"; exit 1 ;;
esac

# ── Summary ─────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED"
  exit 1
fi
