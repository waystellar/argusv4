# Control Room - 3-Minute Manual Verification Checklist

## Quick Start

```bash
# Start the stack
cd argus_v4
./scripts/run_all.sh

# Or start frontend only
cd argus_v4/web
npm run dev
```

Then open: http://localhost:5173/production

---

## Checklist (3 minutes)

### 1. Page Load & Auth (~30 seconds)

| Check | What to Click | Expected Result |
|-------|--------------|-----------------|
| Navigate to Production | Click "Control Room" from landing | Event picker page loads at `/production` |
| Auth Check | N/A | `ProductionEventPicker` checks `/admin/auth/status`; shows login if unauthenticated |
| Login | Enter admin password | JWT stored in `localStorage` as `admin_token`, picker shows events |
| Select Event | Click an event card | Control Room loads at `/production/events/:eventId` with skeleton |

**Source:** `LandingPage.tsx:68` → `ProductionEventPicker.tsx:20` → `ControlRoom.tsx:171`

### 2. Header Bar (~30 seconds)

| Element | What to See | Source |
|---------|-------------|--------|
| **Back Button** | Left chevron, navigates back via `useSafeBack('/production')` | `ControlRoom.tsx:805-813` |
| **Title** | "Control Room" in `text-ds-heading` with pulsing red dot (`bg-status-error animate-pulse`) | `ControlRoom.tsx:815-817` |
| **Event Name** | Subtitle showing event name + copyable event ID | `ControlRoom.tsx:819-844` |
| **Online Badge** | `X/Y online` with green/yellow/red variant based on ratio | `ControlRoom.tsx:852-866` |
| **Streaming Badge** | `N streaming` with pulsing red dot (if any streaming) | `ControlRoom.tsx:861-865` |
| **Keyboard Hint** | "Press `1-9` to switch" | `ControlRoom.tsx:881-883` |
| **Logout Button** | `Button` secondary, clears `admin_token`, navigates to `/production` | `ControlRoom.tsx:885-894` |
| **Home Button** | House icon, navigates to `/` | `ControlRoom.tsx:896-904` |
| **Header Background** | `bg-neutral-900` with `border-b border-neutral-800` | `ControlRoom.tsx:803` |

### 3. Three-Column Layout (~30 seconds)

| Column | Width | Content | Source |
|--------|-------|---------|--------|
| **Left** | `lg:col-span-4` | ON AIR panel — video preview or Auto Mode empty state | `ControlRoom.tsx:924-998` |
| **Center** | `lg:col-span-5` | Camera Grid — vehicle cards with Feature/camera buttons | `ControlRoom.tsx:1001-1169` |
| **Right** | `lg:col-span-3` | Leaderboard, Edge Devices, Alerts, Pit Notes, Keyboard Shortcuts | `ControlRoom.tsx:1172-1297` |

**Layout:** `grid grid-cols-1 lg:grid-cols-12 gap-ds-4` at `ControlRoom.tsx:922`

### 4. Empty States (~30 seconds)

| Panel | Empty State Title | Empty State Description | Source |
|-------|------------------|------------------------|--------|
| **On Air** | "Auto Mode" | "No featured camera selected" | `ControlRoom.tsx:992-993` |
| **Camera Grid** | "No feeds yet" | "Teams need to configure video feeds" | `ControlRoom.tsx:1018-1019` |
| **Leaderboard** | "No timing data yet" | "Leaderboard updates after checkpoint crossings." | `ControlRoom.tsx:1184-1185` |
| **Edge Devices** | "No edge devices connected" | "No edge devices are connected to this event." | `ControlRoom.tsx:1215-1216` |
| **Alerts** | "No active alerts" | "Alert events will appear here when they occur." | `ControlRoom.tsx:1249-1250` |
| **Pit Notes** | "No pit notes" | "Notes from pit crews will appear here." | `ControlRoom.tsx:1267-1268` |

### 5. Interactive Elements (~60 seconds)

| Action | Expected Behavior | Source |
|--------|-------------------|--------|
| Press `1-9` | Switches to corresponding vehicle camera (if available) | `ControlRoom.tsx:648-664` |
| Press `Esc` | Clears featured camera, returns to Auto Mode | `ControlRoom.tsx:667-669` |
| Click "Feature" button | Sets featured vehicle, button text changes to "LIVE" (red variant) | `ControlRoom.tsx:1045-1051` |
| Click camera button | Sets featured camera for that vehicle via per-vehicle API | `ControlRoom.tsx:1064-1069` |
| Click edge device row | Opens `VehicleDrillDownModal` with stream controls | `ControlRoom.tsx:1222-1224` |
| Click "Logout" | Removes `admin_token` from localStorage, navigates to `/production` | `ControlRoom.tsx:888-891` |

---

## Visual Quality Gates

### Typography
- [x] Page title uses `text-ds-heading` (18px, semibold) — `ControlRoom.tsx:815`
- [x] Section headings use `text-ds-heading` — `ControlRoom.tsx:927,1005,1176,1206,1245,1258`
- [x] Body text is `text-ds-body-sm` (14px) — throughout
- [x] Captions/labels are `text-ds-caption` (12px) — `ControlRoom.tsx:830,881,1006`

### Spacing
- [x] `gap-ds-4` (16px) between panels — `ControlRoom.tsx:922,1172`
- [x] Panel header padding `px-ds-4 py-ds-3` — `ControlRoom.tsx:926,1004,1175,1205,1244`
- [x] Panel content padding `p-ds-4` — `ControlRoom.tsx:942,1009,1182,1213,1247`
- [x] Vehicle card padding `p-ds-3` — `ControlRoom.tsx:1037`

### Colors
- [x] Background: `bg-neutral-950` (darkest) — `ControlRoom.tsx:789`
- [x] Panels: `bg-neutral-900` (via Card component) — `ControlRoom.tsx:925,1003,1174,1204,1243`
- [x] Vehicle cards: `bg-neutral-800` — `ControlRoom.tsx:1030`
- [x] Primary text: `text-neutral-50` — throughout
- [x] Secondary text: `text-neutral-400` — `ControlRoom.tsx:820,982`
- [x] Muted text: `text-neutral-500` — `ControlRoom.tsx:881,1006`
- [x] Status: `status-success`, `status-warning`, `status-error` — throughout

### Badges
- [x] Online count: green/yellow/red based on ratio — `ControlRoom.tsx:853-856`
- [x] Streaming badge: pulsing red dot — `ControlRoom.tsx:862-864`
- [x] LIVE badge on featured: `variant="error"` — `ControlRoom.tsx:969-971`
- [x] Status badges use consistent sizing via Badge `size="sm"` — `ControlRoom.tsx:1177,1207`

### Border Radius
- [x] Panels: `rounded-ds-lg` (12px via Card) — `ControlRoom.tsx:925`
- [x] Vehicle cards: `rounded-ds-md` (8px) — `ControlRoom.tsx:1030`
- [x] Small elements: `rounded-ds-sm` (4px) — `ControlRoom.tsx:833,1039`

---

## Loading States

- [x] Full skeleton on initial load with 3-column layout — `ControlRoom.tsx:708-781`
- [x] "Loading Control Room..." overlay with spinner — `ControlRoom.tsx:772-778`
- [x] Switch confirmation toast: "LIVE: Truck #X - Camera" — `ControlRoom.tsx:791-800`
- [x] Pending camera switch animation (`animate-pulse`) — `ControlRoom.tsx:1072-1073`

---

## Mobile Responsiveness

| Viewport | Layout | Source |
|----------|--------|--------|
| Desktop (≥1024px) | 3-column grid: 4 + 5 + 3 (12-col) | `ControlRoom.tsx:922` `lg:grid-cols-12` |
| Tablet / Mobile (<1024px) | Single column, all panels stacked | Grid collapses to `grid-cols-1` |
| Camera grid cards | 1-col on mobile, 2-col on md+ | `ControlRoom.tsx:1022` `grid-cols-1 md:grid-cols-2` |

---

## Known Limitations

1. **No real video** — YouTube embed requires valid stream keys from teams
2. **Mock data** — Without edge devices running, all panels show empty states
3. **No alerts backend** — Alerts panel always shows empty state
4. **Auth shared with Admin** — Uses same `admin_token` in localStorage

---

## Automated Test

Run the smoke test:
```bash
bash scripts/ui_smoke_control_room.sh
```

Expected output: `All critical checks passed!`

The smoke test validates ~54 checks across 7 sections:
- A: Source files exist (4 checks)
- B: ControlRoom design system tokens (12 checks)
- C: ProductionEventPicker (4 checks)
- D: Routing configuration (5 checks)
- E: Key UI elements and empty states (21 checks)
- F: Design token config (5 checks)
- G: Frontend server runtime (3 checks, skipped if not running)

**Limitation:** The smoke test validates source code via `grep`. It cannot validate rendered UI. Manual verification is required for visual layout, hover states, and responsive behavior.

---

## Files

| File | Purpose |
|------|---------|
| `web/src/pages/ControlRoom.tsx` | Main Control Room — 3-column broadcast interface (1885 lines) |
| `web/src/pages/ProductionEventPicker.tsx` | Event picker with auth gate (328 lines) |
| `web/src/pages/LandingPage.tsx` | Landing page with "Control Room" CTA |
| `web/src/App.tsx` | Route definitions (`/production`, `/production/events/:eventId`) |
| `web/src/components/ui/Badge.tsx` | Status badge component |
| `web/src/components/ui/EmptyState.tsx` | Empty state placeholder component |
| `web/src/components/ui/Card.tsx` | Panel card component |
| `web/src/components/ui/Button.tsx` | Button component |
| `web/src/components/StreamControl/` | Stream control panel + diagnostics modal |
| `web/tailwind.config.js` | Design system token definitions |
| `scripts/ui_smoke_control_room.sh` | Automated smoke test (~54 checks) |
| `docs/control-room-manual-checklist.md` | This file |
