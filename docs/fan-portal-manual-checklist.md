# Fan Portal Event Page - 3-Minute Manual Verification Checklist

## Quick Start

```bash
# Start the stack
cd argus_v4
./scripts/run_all.sh

# Or start frontend only
cd argus_v4/web
npm run dev
```

Then open: http://localhost:5173/events/demo

---

## Checklist (3 minutes)

### 1. Page Load (~30 seconds)

| Check | What to Click | Expected Result |
|-------|--------------|-----------------|
| Navigate to Event | Click "Watch Live" from landing or go to /events | Event discovery page loads |
| Select Event | Click an event card | Race Center loads with skeleton then content |
| Verify Header | N/A | Event name, status badge (Live/Upcoming/Finished), connection indicator |

### 2. Header & Status (~30 seconds)

| Element | What to See |
|---------|-------------|
| **Back Button** | Left arrow, navigates to /events |
| **Event Title** | Event name (e.g., "Demo Event"), centered |
| **Status Badges** | Event status (LIVE/Upcoming/Finished) + connection status (Live/Connecting) |

### 3. Tab Navigation (~30 seconds)

| Tab | Expected Content |
|-----|------------------|
| **Overview** | Map, favorites row (if any), featured vehicle tile, top 10 mini leaderboard |
| **Standings** | Search input, class filter chips, full leaderboard with position badges |
| **Watch** | Video player area, camera feed grid with favorites section |
| **Tracker** | Vehicle list with GPS data (may show empty state) |

### 4. Standings Tab Deep Dive (~60 seconds)

| Action | Expected Behavior |
|--------|-------------------|
| Search by truck # | Type "12" → shows vehicles with "12" in number |
| Search by team | Type team name → filters to matching teams |
| Clear search | Click X button or clear input → shows all vehicles |
| Tap vehicle row | Highlights row, shows on map (if Overview) |
| Tap star icon | Adds/removes from favorites |
| Position badges | Gold for P1, silver for P2, bronze for P3 |

### 5. Empty States (~30 seconds)

| Panel | Empty State Message |
|-------|---------------------|
| Standings (no data) | "Waiting for race data" - "Standings appear when vehicles cross checkpoints" |
| Standings (no matches) | "No matches found" with clear search button |
| Watch (no feeds) | "No video feeds available" - "Camera feeds appear when teams enable streaming" |
| Video player | "Select a camera feed" or "Stream not available" |

---

## Visual Quality Gates

### Typography
- [ ] Event title uses `text-ds-heading` (18px, semibold)
- [ ] Body text is `text-ds-body-sm` (14px)
- [ ] Captions/labels are `text-ds-caption` (12px)
- [ ] Tab labels are uppercase, tracking-wide

### Spacing
- [ ] Consistent `gap-ds-4` (16px) between sections
- [ ] Card padding is `p-ds-4` (16px)
- [ ] Row padding is `px-ds-4 py-ds-3`

### Colors
- [ ] Background: `bg-neutral-950` (darkest)
- [ ] Cards/surfaces: `bg-neutral-900`
- [ ] Input backgrounds: `bg-neutral-800`
- [ ] Text: `text-neutral-50` (primary), `text-neutral-400` (secondary)
- [ ] Status: green=success/live, yellow=warning, red=error

### Badges
- [ ] Position badges: gold P1, silver P2, bronze P3, neutral P4+
- [ ] Status badges use design system Badge component
- [ ] Live badge shows pulsing dot

---

## Mobile Responsiveness

| Viewport | Layout |
|----------|--------|
| Desktop (≥1024px) | Full layout with all elements visible |
| Tablet (768-1023px) | Compact layout, team names may truncate |
| Mobile (<768px) | Single column, tabs at bottom, scrollable lists |

---

## Known Limitations

1. **No real video** - YouTube embed requires valid stream keys
2. **Mock data** - Without backend, shows empty states
3. **Map not tested** - Requires Mapbox token for full functionality

---

## Automated Test

Run the smoke test:
```bash
./scripts/ui_smoke_fan_portal.sh
```

Expected output: "All critical checks passed!"

---

## Before/After Summary

### Before (UI-3)
- Mixed gray-* colors (gray-400, gray-700, gray-800)
- Inconsistent typography (text-lg, text-sm, text-xs)
- Ad-hoc spacing (px-4, py-3, gap-2)
- Local EmptyState components in each file
- `bg-surface` and `bg-surface-light` colors

### After (UI-4)
- Consistent neutral-* palette (neutral-50 to neutral-950)
- Design system typography (text-ds-heading, text-ds-body-sm, text-ds-caption)
- Token-based spacing (p-ds-4, gap-ds-3, px-ds-4)
- Shared EmptyState component from ui/
- Proper status-* colors for indicators
- Badge component for all status displays
