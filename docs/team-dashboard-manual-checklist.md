# Team Dashboard - 3-Minute Manual Verification Checklist

## Quick Start

```bash
# Start the stack
cd argus_v4
./scripts/run_all.sh

# Or start frontend only
cd argus_v4/web
npm run dev
```

Then open: http://localhost:5173/team

---

## Checklist (3 minutes)

### 1. Page Load & Auth (~30 seconds)

| Check | What to Click | Expected Result |
|-------|---------------|-----------------|
| Navigate to Team | Go to /team | If logged in: Dashboard loads; If not: Redirects to /team/login |
| Auth Check | N/A | Dashboard shows or login form appears |
| Loading State | N/A | Skeleton UI appears briefly, then content loads |

### 2. Header & Event Context (~30 seconds)

| Element | What to See |
|---------|-------------|
| **Title** | "Team Dashboard" with "Manage your truck" subtitle |
| **Home Button** | Left side, navigates to / |
| **Logout Button** | Right side, logs out when clicked |
| **Event Context Bar** | Below header - shows event status |
| **Active Event** | Green dot + "Active Event" + LIVE/STALE/OFFLINE badge + event ID |
| **No Event** | Gray dot + "No Active Event" + "Register to go live" text |

### 3. My Truck Section (~30 seconds)

| Element | Expected Behavior |
|---------|-------------------|
| **Section Header** | "MY TRUCK" uppercase label |
| **Truck Card** | Vehicle number in accent box, team name, vehicle ID |
| **Status Badges** | Right side: Online/Streaming/Offline/No Data + Visible/Hidden |
| **Quick Stats Row** | Three columns: Hz (data rate), Last Seen (time), Queue (depth) |

### 4. Next Action Prompt (~15 seconds)

| State | Expected Alert |
|-------|----------------|
| No event registered | Blue info alert: "Registration Required" with guidance |
| Edge offline | Blue info alert: "Connect Edge" with guidance |
| No stream active | Blue info alert: "Start Streaming" with guidance |
| All good | No alert shown |

### 5. Streaming & Edge Status (~30 seconds)

| Element | Expected Behavior |
|---------|-------------------|
| **Section Header** | "STREAMING & EDGE STATUS" uppercase label |
| **GPS Card** | Status: Locked (green), Searching (yellow), No Signal (red), Unknown (gray) |
| **CAN Bus Card** | Status: Active (green), Idle (yellow), Error (red), Unknown (gray) |
| **Video Card** | Status: Streaming (green), Configured (blue), Not Set (gray), Unknown (gray) |
| **Visibility Card** | Toggle button: Visible (green) or Hidden (gray) |
| **Stream Control** | Only shows when actively streaming - Stop Stream button |

### 6. Diagnostics Section (~30 seconds)

| Element | Expected Behavior |
|---------|-------------------|
| **Section Header** | "DIAGNOSTICS" with Copy button |
| **Copy Button** | Click to copy diagnostics to clipboard |
| **Diagnostic Rows** | Vehicle ID, Event ID, Edge Last Seen, Queue Depth, Last Position |

### 7. Tab Navigation (~15 seconds)

| Tab | Expected Content |
|-----|------------------|
| **Ops** (default) | My Truck, Next Action, Streaming Status, Diagnostics, Alerts |
| **Sharing** | Visibility toggle, Telemetry sharing policy, Video feeds |

---

## Visual Quality Gates

### Typography
- [ ] Title uses `text-ds-heading` (18px, semibold)
- [ ] Body text is `text-ds-body` or `text-ds-body-sm`
- [ ] Captions/labels are `text-ds-caption` (12px)
- [ ] Section headers are uppercase with tracking-wide

### Spacing
- [ ] Consistent `gap-ds-4` (16px) between sections
- [ ] Card padding is `p-ds-4` (16px)
- [ ] Status cards use 2-column grid with `gap-ds-3`

### Colors
- [ ] Background: `bg-neutral-950` (darkest)
- [ ] Cards/surfaces: `bg-neutral-900`
- [ ] Headers: `bg-neutral-900` with `border-neutral-800`
- [ ] Text: `text-neutral-50` (primary), `text-neutral-400` (secondary)
- [ ] Accent: `accent-500/600` for highlights
- [ ] Status: green=online/success, yellow=warning, red=error/offline, blue=info

### Status Badges
- [ ] Use Badge component with appropriate variant
- [ ] Pulsing dot for active states (online, streaming)
- [ ] Correct colors: success=green, warning=yellow, error=red, default=gray

---

## States to Test

### Loading States
- [ ] Initial load shows skeleton UI
- [ ] Skeleton includes header, tabs, content placeholders
- [ ] Central loading indicator with spinner

### Empty States / No Event
- [ ] Event context bar shows "No Active Event"
- [ ] Next action prompt explains registration
- [ ] Status cards show "Unknown" state

### Error States
- [ ] Auth error: Redirects to login or shows retry
- [ ] Network error: Shows EmptyState with retry button
- [ ] API error: Shows error message with action

---

## Mobile Responsiveness

| Viewport | Layout |
|----------|--------|
| Desktop (>=1024px) | Full layout with all elements visible |
| Tablet (768-1023px) | Compact layout, 2-column status grid |
| Mobile (<768px) | Single column, stacked cards, full-width buttons |

---

## Automated Test

Run the smoke test:
```bash
./scripts/ui_smoke_team_dashboard.sh
```

Expected output: "All critical checks passed!"

---

## Before/After Summary (UI-6)

### Before (UI-5)
- Header showed only vehicle number and team name
- No clear event context bar
- Status banner was event-dependent only
- No "My Truck" section
- No next action prompts
- Status cards without section header

### After (UI-6)
- Full "Team Dashboard" header with home/logout
- Dedicated event context bar (always visible)
- "My Truck" section with vehicle info + status badges
- Quick stats row (Hz, Last Seen, Queue)
- Smart next action prompts based on state
- "Streaming & Edge Status" section with clear header
- Cleaner diagnostics section with copy button
- Removed duplicate logout button (now in header only)
