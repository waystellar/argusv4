# Pit Crew Dashboard - 3-Minute Manual Verification Checklist

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

### 1. Page Load (~30 seconds)

| Check | What to Click | Expected Result |
|-------|---------------|-----------------|
| Navigate to Team | Click "Pit Crew Login" or go to /team | Login form or dashboard loads |
| Auth Check | N/A | If no token, shows login form |
| Dashboard Load | After login | Skeleton UI then content loads |

### 2. Header & Status Strip (~30 seconds)

| Element | What to See |
|---------|-------------|
| **Title** | "Pit Crew Ops Console" centered |
| **Event Badge** | Event name with status (accent-600 bg) |
| **Logout Button** | Right side, "Logout" text |

### 3. Tab Navigation (~30 seconds)

| Tab | Expected Content |
|-----|------------------|
| **Ops** (default) | Status banner, 4 status cards, diagnostics, alerts |
| **Sharing** | Visibility toggle, video feeds, telemetry policy |

### 4. Ops Tab Deep Dive (~60 seconds)

| Element | Expected Behavior |
|---------|-------------------|
| **Status Banner** | Shows event status (LIVE/SCHEDULED/FINISHED), time remaining |
| **Status Cards** | 4 cards: Edge Status, Stream Status, Last Position, Next Checkpoint |
| **Each Status Card** | Title, status indicator (colored dot), value, caption |
| **Diagnostics Panel** | Collapsible, shows: GPS, CAN, Stream, Uplink status |
| **Alerts Section** | Shows any warnings or errors |

### 5. Sharing Tab Deep Dive (~30 seconds)

| Element | Expected Behavior |
|---------|-------------------|
| **Visibility Toggle** | "Visible to Fans" toggle switch |
| **Video Feeds** | List of camera feeds with URL inputs, permission badges |
| **Add Feed Button** | Opens form for new camera feed |
| **Telemetry Policy** | Preset buttons, field group checkboxes (Production/Fans) |

### 6. Footer (~15 seconds)

| Element | What to See |
|---------|-------------|
| **Connection Status** | Badge showing "Connected" (green) or "Disconnected" (red) |
| **Last Sync** | Timestamp of last data refresh |
| **Version** | App version number |

---

## Visual Quality Gates

### Typography
- [ ] Title uses `text-ds-heading` (18px, semibold)
- [ ] Body text is `text-ds-body` or `text-ds-body-sm` (16/14px)
- [ ] Captions/labels are `text-ds-caption` (12px)
- [ ] Tab labels are `text-ds-body-sm`, uppercase

### Spacing
- [ ] Consistent `gap-ds-4` (16px) between sections
- [ ] Card padding is `p-ds-4` (16px)
- [ ] Header padding is `px-ds-4 py-ds-3`
- [ ] Status cards use `gap-ds-4` grid

### Colors
- [ ] Background: `bg-neutral-950` (darkest)
- [ ] Cards/surfaces: `bg-neutral-900`
- [ ] Input backgrounds: `bg-neutral-800`
- [ ] Text: `text-neutral-50` (primary), `text-neutral-400` (secondary)
- [ ] Accent: `accent-500/600` for interactive elements
- [ ] Status: green=connected/success, yellow=warning, red=error/disconnected

### Status Indicators
- [ ] Green dot for connected/healthy
- [ ] Yellow dot for warning/degraded
- [ ] Red dot for error/disconnected
- [ ] Status cards have colored left border

---

## Mobile Responsiveness

| Viewport | Layout |
|----------|--------|
| Desktop (>=1024px) | Full layout, 4-column status cards |
| Tablet (768-1023px) | 2-column status cards, compact diagnostics |
| Mobile (<768px) | Single column, stacked cards, full-width inputs |

---

## States to Test

### Loading States
- [ ] Initial load shows skeleton UI (pulsing placeholders)
- [ ] Buttons show spinner when saving
- [ ] Diagnostics refresh shows subtle indicator

### Empty States
- [ ] No video feeds: "No camera feeds configured" with add button
- [ ] No alerts: Clean section (no empty box)

### Error States
- [ ] Auth error: "Session expired" with login button
- [ ] Network error: Retry button with error message
- [ ] API error: Alert component with error details

---

## Known Limitations

1. **No real edge connection** - Without edge hardware, shows simulated status
2. **Mock diagnostics** - Diagnostics data is from last known state
3. **Video URL validation** - Only checks format, not stream availability

---

## Automated Test

Run the smoke test:
```bash
./scripts/ui_smoke_pit_crew.sh
```

Expected output: "All critical checks passed!"

---

## Before/After Summary

### Before (UI-4)
- Mixed gray-* colors (gray-400, gray-700, gray-800)
- Inconsistent typography (text-lg, text-sm, text-xs)
- Ad-hoc spacing (px-4, py-3, gap-2)
- Inline status indicators
- `bg-surface` and `bg-surface-light` colors

### After (UI-5)
- Consistent neutral-* palette (neutral-50 to neutral-950)
- Design system typography (text-ds-heading, text-ds-body-sm, text-ds-caption)
- Token-based spacing (p-ds-4, gap-ds-3, px-ds-4)
- Shared Badge component for all status displays
- Alert component for all error/warning messages
- StatusCard component with consistent styling
- Proper status-* colors for indicators
- Mobile-first responsive layout
