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

Then open: http://localhost:5173/events

---

## Checklist (3 minutes)

### 1. Event Discovery (~30 seconds)

| Check | What to Click | Expected Result |
|-------|--------------|--------------------|
| Navigate to /events | Type URL or click "Watch Live" from landing | Event Discovery page loads at `/events` |
| Event list | N/A | Live, Upcoming, and Recent sections render |
| Select event | Click an event card | Race Center loads at `/events/:eventId` with skeleton |

**Source:** `App.tsx:140` → `EventDiscovery.tsx:188` → `RaceCenter.tsx:28`

### 2. Header Bar (~30 seconds)

| Element | What to See | Source |
|---------|-------------|--------|
| **Back Button** | Left chevron, navigates back via `useSafeBack('/events')` | `RaceCenter.tsx:189-197` |
| **Event Title** | Centered in `text-ds-heading`, truncated if long | `RaceCenter.tsx:201` |
| **StatusBadge** | LIVE (green, pulsing dot), Upcoming (blue), or Finished (neutral) | `RaceCenter.tsx:203`, `RaceCenter.tsx:246-269` |
| **Connection Badge** | "Live" (green dot) or "Connecting" (yellow, pulsing) | `RaceCenter.tsx:204-212` |
| **Home Button** | House icon, navigates to `/` | `RaceCenter.tsx:217-225` |
| **Header Background** | `bg-neutral-900` with `border-b border-neutral-800` | `RaceCenter.tsx:186` |

### 3. Tab Navigation (~15 seconds)

| Tab | Label | Source |
|-----|-------|--------|
| **Overview** | Map icon + "OVERVIEW" | `TabBar.tsx:28` |
| **Standings** | Bar chart icon + "STANDINGS" | `TabBar.tsx:38` |
| **Watch** | Camera icon + "WATCH" | `TabBar.tsx:48` |
| **Tracker** | Pin icon + "TRACKER" | `TabBar.tsx:59` |

Tab labels: `text-ds-caption font-medium uppercase tracking-wide` at `TabBar.tsx:96`
Active indicator: accent-500 bar at `TabBar.tsx:109`

### 4. Empty States (~60 seconds)

| Tab / Panel | Empty State Title | Empty State Description | Source |
|-------------|-------------------|------------------------|--------|
| **Overview — Top 10** | "Waiting for race data" | "Standings appear when vehicles cross checkpoints" | `OverviewTab.tsx:140-141` |
| **Standings — no data** | "Waiting for race data" | "Standings appear when vehicles cross checkpoints" | `StandingsTab.tsx:151-152` |
| **Standings — no matches** | "No matches found" | `No vehicles match "{query}"` + "Clear search" button | `StandingsTab.tsx:164-170` |
| **Watch — no feeds** | "No video feeds available" | "Camera feeds appear when teams enable streaming" | `WatchTab.tsx:201-202` |
| **Tracker — no vehicles** | "Waiting for vehicles" | "Vehicle locations appear when trucks start transmitting" | `TrackerTab.tsx:168-169` |
| **Tracker — no matches** | "No matches found" | `No vehicles match "{query}"` + "Clear search" button | `TrackerTab.tsx:181-187` |
| **Error state** | Dynamic error text | "The event you're looking for doesn't exist or isn't available." + "Browse Events" button | `RaceCenter.tsx:150-164` |

### 5. Key UI Elements (~45 seconds)

| Element | Where | Source |
|---------|-------|--------|
| **Loading skeleton** | Initial load — header + content skeletons with "Loading race..." | `RaceCenter.tsx:109-143` |
| **Map area** | Overview tab — `RaceMap` component with course overlay | `OverviewTab.tsx:67-72` |
| **Center on Race button** | Map overlay — top-right button | `OverviewTab.tsx:75-78`, `OverviewTab.tsx:166-192` |
| **Favorites quick row** | Overview tab — horizontal scroll of starred vehicles | `OverviewTab.tsx:101-107`, `OverviewTab.tsx:197-233` |
| **Top 10 mini leaderboard** | Overview tab — compact rows with position badges | `OverviewTab.tsx:119-157`, `OverviewTab.tsx:311-369` |
| **Search input** | Standings + Tracker — with X clear button | `StandingsTab.tsx:74-99`, `TrackerTab.tsx:87-112` |
| **Class filter chips** | Standings — "All Classes" active, others disabled placeholder | `StandingsTab.tsx:19-24`, `StandingsTab.tsx:103-119` |
| **Position badges** | Standings — Gold P1, Silver P2, Bronze P3 | `StandingsTab.tsx:287-298` |
| **Camera grid** | Watch tab — responsive grid with YouTube thumbnails | `WatchTab.tsx:206-222` |
| **Truck tiles** | Watch tab — 16:9 aspect, LIVE badge, favorite star overlay | `WatchTab.tsx:234-327` |
| **Vehicle rows** | Tracker tab — speed, checkpoint, stale indicators | `TrackerTab.tsx:212-318` |

---

## Visual Quality Gates

### Typography
- [x] Event title uses `text-ds-heading` (18px, semibold) — `RaceCenter.tsx:201`
- [x] Section headings use `text-ds-body-sm font-semibold uppercase tracking-wide` — `OverviewTab.tsx:122`
- [x] Body text is `text-ds-body-sm` (14px) — throughout
- [x] Captions/labels are `text-ds-caption` (12px) — `TabBar.tsx:96`, `OverviewTab.tsx:126`

### Spacing
- [x] `gap-ds-*` spacing throughout — `RaceCenter.tsx:202`, `TabBar.tsx:82`
- [x] Panel padding `px-ds-4 py-ds-3` — `RaceCenter.tsx:186`, `StandingsTab.tsx:72`
- [x] Row padding `px-ds-4 py-ds-3` — `StandingsTab.tsx:219`, `TrackerTab.tsx:232`
- [x] Grid gap `gap-ds-3` — `WatchTab.tsx:208`

### Colors
- [x] Background: `bg-neutral-950` (darkest) — `RaceCenter.tsx:184`, `StandingsTab.tsx:70`
- [x] Header: `bg-neutral-900` — `RaceCenter.tsx:186`
- [x] Primary text: `text-neutral-50` — throughout
- [x] Secondary text: `text-neutral-400` — `StandingsTab.tsx:247`, `OverviewTab.tsx:276`
- [x] Muted text: `text-neutral-500` — `TrackerTab.tsx:134`, `TabBar.tsx:85`
- [x] Status: `status-success`, `status-warning`, `status-error` — `StandingsTab.tsx:130-131`, `WatchTab.tsx:181-186`

### Badges
- [x] StatusBadge: success/info/neutral variants — `RaceCenter.tsx:247-251`
- [x] Connection badge: success (Live) / warning+pulse (Connecting) — `RaceCenter.tsx:204-212`
- [x] LIVE badge on truck tiles: `variant="error"` with pulse — `WatchTab.tsx:296`
- [x] Position badge colors: Gold/Silver/Bronze/Neutral — `StandingsTab.tsx:288-297`

### Border Radius
- [x] Panels: `rounded-ds-lg` (12px) — `OverviewTab.tsx:182`, `TrackerTab.tsx:99`
- [x] Small elements: `rounded-ds-md`, `rounded-ds-sm` — `RaceCenter.tsx:115-117`
- [x] Truck tiles: `rounded-ds-lg` — `WatchTab.tsx:264`
- [x] Filter chips: `rounded-ds-full` — `StandingsTab.tsx:109`, `TrackerTab.tsx:121`

---

## Loading States

- [x] Full skeleton on initial load (header + content + overlay spinner) — `RaceCenter.tsx:109-143`
- [x] "Loading race..." text with accent-500 spinner — `RaceCenter.tsx:138-139`
- [x] Error state with "Browse Events" CTA — `RaceCenter.tsx:147-166`

---

## Mobile Responsiveness

| Viewport | Layout | Source |
|----------|--------|--------|
| Mobile (default) | Full-height flex column, bottom tab bar | `RaceCenter.tsx:184`, `TabBar.tsx:74` |
| Tab bar | 4-tab bottom nav with 52px min height, safe-bottom | `TabBar.tsx:74,82` |
| Map section | 50vh max height, min 200px | `OverviewTab.tsx:66` |
| Watch grid | Auto-fit responsive: `minmax(160px, 1fr)` | `WatchTab.tsx:210` |
| Standings rows | 44px min touch targets | `StandingsTab.tsx:230` |
| Tracker rows | 44px min touch targets | `TrackerTab.tsx:239` |

---

## Reconciliation Notes

### Checklist items NOT in code (by design)
- `/events/demo` route: No demo route exists. The `:eventId` parameter treats any value as a real event ID. If "demo" is passed, the API returns a 404 and the error state renders with a "Browse Events" button.
- "Select a camera feed" / "Stream not available" empty states: The Watch tab is a grid-only view (no embedded video player). Truck tiles navigate to a vehicle detail page on click.

### Code diffs applied during reconciliation
1. `StandingsTab.tsx:151-152` — Empty state changed from "No entrants registered" to "Waiting for race data"
2. `WatchTab.tsx:201-202` — Empty state changed from "No trucks registered" to "No video feeds available"

---

## Known Limitations

1. **No video player** — Watch tab shows thumbnail grid only; no embedded YouTube player
2. **Mock data** — Without edge devices running, all tabs show empty states
3. **Class filters disabled** — Only "All Classes" is enabled; others are placeholder
4. **No push notifications** — PWA install hint shown but no service worker
5. **No /events/demo** — No special demo route; requires real event ID from API

---

## Automated Test

Run the smoke test:
```bash
bash scripts/ui_smoke_fan_portal.sh
```

Expected output: `All critical checks passed!`

The smoke test validates ~54 checks across 7 sections:
- A: Source files exist (7 checks)
- B: RaceCenter design system tokens (10 checks)
- C: Tab navigation (5 checks)
- D: Routing configuration (4 checks)
- E: Key UI elements and empty states (20 checks)
- F: Design token config (5 checks)
- G: Frontend server runtime (3 checks, skipped if not running)

**Limitation:** The smoke test validates source code via `grep`. It cannot validate rendered UI. Manual verification is required for visual layout, hover states, and responsive behavior.

---

## Files

| File | Purpose |
|------|---------|
| `web/src/components/RaceCenter/RaceCenter.tsx` | Main fan event page — header, tabs, loading/error states (270 lines) |
| `web/src/components/RaceCenter/TabBar.tsx` | Bottom tab navigation (118 lines) |
| `web/src/components/RaceCenter/OverviewTab.tsx` | Overview — map, favorites, top 10 (387 lines) |
| `web/src/components/RaceCenter/StandingsTab.tsx` | Full leaderboard with search and filters (299 lines) |
| `web/src/components/RaceCenter/WatchTab.tsx` | Camera feed grid with YouTube thumbnails (333 lines) |
| `web/src/components/RaceCenter/TrackerTab.tsx` | Vehicle tracker with GPS data (329 lines) |
| `web/src/pages/EventDiscovery.tsx` | Event discovery / browse page (429 lines) |
| `web/src/App.tsx` | Route definitions (`/events`, `/events/:eventId`) |
| `web/src/components/ui/Badge.tsx` | Status badge component |
| `web/src/components/ui/EmptyState.tsx` | Empty state placeholder component |
| `web/tailwind.config.js` | Design system token definitions |
| `scripts/ui_smoke_fan_portal.sh` | Automated smoke test (~54 checks) |
| `docs/fan-portal-manual-checklist.md` | This file |
