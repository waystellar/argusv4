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

### 1. Page Load (~30 seconds)

| Check | What to Click | Expected Result |
|-------|--------------|-----------------|
| Navigate to Production | Click "Control Room" from landing | Event picker page loads |
| Select/Create Event | Click an event or create demo | Control Room loads with skeleton |
| Verify Header | N/A | "Control Room" title with pulsing red dot |

### 2. Layout & Structure (~60 seconds)

| Area | What to See |
|------|-------------|
| **Header Bar** | Back button, event name, status badges (X/Y online), keyboard shortcut hint, Logout button |
| **Left Column** | "ON AIR" panel with video preview or "Auto Mode" empty state |
| **Center Column** | "Camera Grid" with vehicle cards or "No feeds yet" empty state |
| **Right Column** | Leaderboard, Edge Devices, Alerts panels stacked vertically |

### 3. Empty States (~30 seconds)

| Panel | Empty State Message |
|-------|---------------------|
| On Air | "Auto Mode - No featured camera selected" |
| Camera Grid | "No feeds yet - Teams need to configure video feeds" |
| Leaderboard | "No timing data yet" |
| Edge Devices | "No edge devices connected" |
| Alerts | "No active alerts" |

### 4. Interactive Elements (~60 seconds)

| Action | Expected Behavior |
|--------|-------------------|
| Press `1-9` | Switches to corresponding vehicle camera (if available) |
| Press `Esc` | Clears featured camera, returns to Auto Mode |
| Click vehicle "Feature" button | Highlights vehicle, shows LIVE badge |
| Click camera button | Switches broadcast to that camera |
| Click edge device row | Opens drill-down modal with stream controls |
| Click "Logout" | Returns to production event picker |

---

## Visual Quality Gates

### Typography
- [ ] Page title uses `text-ds-heading` (18px, semibold)
- [ ] Section headers are consistent
- [ ] Body text is `text-ds-body-sm` (14px)
- [ ] Captions/labels are `text-ds-caption` (12px)

### Spacing
- [ ] Consistent `gap-ds-4` (16px) between panels
- [ ] Panel padding is `p-ds-4` (16px)
- [ ] Section padding is `p-ds-3` (12px)

### Colors
- [ ] Background: `bg-neutral-950` (darkest)
- [ ] Panels: `bg-neutral-900` (surface)
- [ ] Cards/buttons: `bg-neutral-800`
- [ ] Text: `text-neutral-50` (primary), `text-neutral-400` (secondary)
- [ ] Status colors: green=success, yellow=warning, red=error

### Badges
- [ ] Online count shows green/yellow/red based on ratio
- [ ] Streaming badge shows pulsing red dot
- [ ] Status badges use consistent sizing

---

## Mobile Responsiveness

| Viewport | Layout |
|----------|--------|
| Desktop (≥1024px) | 3-column grid (4+5+3) |
| Tablet (768-1023px) | Stacked columns |
| Mobile (<768px) | Single column, scrollable |

---

## Known Limitations

1. **No real video** - YouTube embed requires valid stream keys
2. **Mock data** - Without edge devices, lists show empty states
3. **No alerts** - Backend SSE events not implemented yet

---

## Automated Test

Run the smoke test:
```bash
./scripts/ui_smoke_control_room.sh
```

Expected output: "All critical checks passed!"
