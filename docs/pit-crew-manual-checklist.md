# Pit Crew Dashboard (Team Dashboard) — 3-Minute Manual Verification Checklist

> **Reconciled against source code.** Every claim below is backed by file:line evidence.
> Last reconciled: 2026-01-29

---

## Quick Start

```bash
# Start the stack
cd argus_v4
./scripts/run_all.sh

# Or start frontend only
cd argus_v4/web && npm run dev
```

Then open: http://localhost:5173/team/login

---

## Source Files

| File | Purpose |
|------|---------|
| [TeamDashboard.tsx](../web/src/pages/TeamDashboard.tsx) | Main dashboard (1212 lines) — Ops + Sharing tabs |
| [TeamLogin.tsx](../web/src/pages/TeamLogin.tsx) | Login form (146 lines) |
| [VideoFeedManager.tsx](../web/src/components/Team/VideoFeedManager.tsx) | 4-camera YouTube URL config (145 lines) |
| [App.tsx](../web/src/App.tsx) | Route definitions (lines 144–146) |
| [LandingPage.tsx](../web/src/pages/LandingPage.tsx) | Landing CTA "Manage My Truck" |

---

## Checklist (3 minutes)

### 1. Page Load & Auth (~30 seconds)

| Check | What to Click | Expected Result | Source |
|-------|---------------|-----------------|--------|
| Navigate to Team | Click "Manage My Truck" on landing or go to `/team/login` | Login form loads | [LandingPage.tsx](../web/src/pages/LandingPage.tsx), [App.tsx:144](../web/src/App.tsx#L144) |
| Auth Check | N/A | If no `team_token` in localStorage, redirects to login | [TeamDashboard.tsx:116-122](../web/src/pages/TeamDashboard.tsx#L116-L122) |
| Login | Enter vehicle number + team token, click "Sign In" | POST to `/api/v1/team/login`, stores token, navigates to `/team/dashboard` | [TeamLogin.tsx:19-48](../web/src/pages/TeamLogin.tsx#L19-L48) |
| Dashboard Load | After login | Skeleton UI (pulsing header + tabs + cards + spinner) then content | [TeamDashboard.tsx:283-327](../web/src/pages/TeamDashboard.tsx#L283-L327) |

### 2. Header & Status Strip (~30 seconds)

| Element | What to See | Source |
|---------|-------------|--------|
| **Title** | "Team Dashboard" via PageHeader | [TeamDashboard.tsx:363](../web/src/pages/TeamDashboard.tsx#L363) |
| **Subtitle** | "Manage your truck" | [TeamDashboard.tsx:364](../web/src/pages/TeamDashboard.tsx#L364) |
| **Logout Button** | Right side, "Logout" text | [TeamDashboard.tsx:368-373](../web/src/pages/TeamDashboard.tsx#L368-L373) |
| **Edge URL Bar** | "Open Pit Crew Portal" button (green dot) when edge online, "Waiting for edge device" otherwise | [TeamDashboard.tsx:377-415](../web/src/pages/TeamDashboard.tsx#L377-L415) |
| **Event Context Bar** | "Active Event" with LIVE/OFFLINE/STALE/WAITING Badge, or "No Active Event" | [TeamDashboard.tsx:417-441](../web/src/pages/TeamDashboard.tsx#L417-L441) |

### 3. Tab Navigation (~30 seconds)

| Tab | Label | Expected Content | Source |
|-----|-------|------------------|--------|
| **Ops** (default) | "Ops" (with alert dot if stale/offline) | My Truck card, Edge Device status, status cards, diagnostics, alerts | [TeamDashboard.tsx:452-472](../web/src/pages/TeamDashboard.tsx#L452-L472) |
| **Sharing** | "Sharing" | Visibility (read-only), Telemetry (read-only), Video feeds | [TeamDashboard.tsx:474-492](../web/src/pages/TeamDashboard.tsx#L474-L492) |

### 4. Ops Tab Deep Dive (~60 seconds)

| Element | Expected Behavior | Source |
|---------|-------------------|--------|
| **My Truck Card** | Vehicle number (#N), team name, status badges (Online/Offline/Streaming/Stale/Waiting + Visible/Hidden), quick stats row (Hz, Last Seen, Queue) | [TeamDashboard.tsx:628-678](../web/src/pages/TeamDashboard.tsx#L628-L678) |
| **Next Action** | Contextual guidance via Alert component (conditional) | [TeamDashboard.tsx:681-687](../web/src/pages/TeamDashboard.tsx#L681-L687) |
| **Edge Device Status** | Heartbeat indicator with status text: "Edge Online", "Heartbeat delayed", "Edge Offline", "Waiting for edge" + Last Seen time | [TeamDashboard.tsx:690-724](../web/src/pages/TeamDashboard.tsx#L690-L724) |
| **Status Cards** | 2-column grid: **GPS** (Locked/Searching/No Signal/Unknown), **CAN Bus** (Active/Idle/Error/Unknown), **Video** (Streaming/Configured/Not Set/Unknown), **Visibility** (Visible/Hidden, read-only, "Managed from Pit Crew") | [TeamDashboard.tsx:726-803](../web/src/pages/TeamDashboard.tsx#L726-L803) |
| **Stream Control** | Only visible when `video_status === 'streaming'` and event active | [TeamDashboard.tsx:805-818](../web/src/pages/TeamDashboard.tsx#L805-L818) |
| **Diagnostics** | Always visible (NOT collapsible). Fields: Vehicle ID, Event ID, Edge Status, Edge Last Seen, Edge URL, Edge IP, Edge Version, Queue Depth, Last Position. Copy button. | [TeamDashboard.tsx:822-889](../web/src/pages/TeamDashboard.tsx#L822-L889) |
| **Alerts** | Conditional — only renders when issues exist. Shows: "Edge Device Offline", "Stale Data", "GPS Signal Lost" | [TeamDashboard.tsx:891-921](../web/src/pages/TeamDashboard.tsx#L891-L921) |

### 5. Sharing Tab Deep Dive (~30 seconds)

| Element | Expected Behavior | Source |
|---------|-------------------|--------|
| **Event Status Alert** | "Active Event" (success) or "No Active Event" (warning) | [TeamDashboard.tsx:941-951](../web/src/pages/TeamDashboard.tsx#L941-L951) |
| **Vehicle Visibility** | READ-ONLY display. Badge shows "Visible" (success) or "Hidden" (error). Text: "Manage visibility from your Pit Crew Portal (Team tab)." | [TeamDashboard.tsx:953-969](../web/src/pages/TeamDashboard.tsx#L953-L969) |
| **Telemetry Sharing** | READ-ONLY notice: "Telemetry sharing policy is managed from your Pit Crew Portal (Team tab)." | [TeamDashboard.tsx:971-977](../web/src/pages/TeamDashboard.tsx#L971-L977) |
| **Video Feeds** | 4 fixed camera slots (Main Cam, Cockpit, Chase Cam, Suspension). Each shows URL or "No URL configured". Edit button opens inline form with URL input + permission select (Public/Premium/Private) + Save/Cancel. | [VideoFeedManager.tsx:21-145](../web/src/components/Team/VideoFeedManager.tsx#L21-L145) |

### 6. Footer (~15 seconds)

| Element | What to See | Source |
|---------|-------------|--------|
| **Preview Fan View** | Link to `/events/{event_id}/vehicles/{vehicle_id}` (opens in new tab). Only visible when event_id exists AND vehicle is visible. | [TeamDashboard.tsx:519-540](../web/src/pages/TeamDashboard.tsx#L519-L540) |

> **Note:** There is no connection status badge, last sync timestamp, or version string in the footer.

---

## Visual Quality Gates

### Typography
- [x] Title uses `text-ds-heading` via PageHeader — [TeamDashboard.tsx:362](../web/src/pages/TeamDashboard.tsx#L362)
- [x] Body text is `text-ds-body` or `text-ds-body-sm` — throughout
- [x] Captions/labels are `text-ds-caption` — [TeamDashboard.tsx:629](../web/src/pages/TeamDashboard.tsx#L629)
- [x] Tab labels are `text-ds-body-sm font-medium` (NOT uppercase) — [TeamDashboard.tsx:454](../web/src/pages/TeamDashboard.tsx#L454)

### Spacing
- [x] Consistent `gap-ds-4` / `space-y-ds-4` between sections — [TeamDashboard.tsx:626](../web/src/pages/TeamDashboard.tsx#L626)
- [x] Card padding is `p-ds-4` — [TeamDashboard.tsx:630](../web/src/pages/TeamDashboard.tsx#L630)
- [x] Header padding is `px-ds-4 py-ds-3` via PageHeader
- [x] Status cards use `gap-ds-3` grid — [TeamDashboard.tsx:726](../web/src/pages/TeamDashboard.tsx#L726)

### Colors
- [x] Background: `bg-neutral-950` — [TeamDashboard.tsx:360](../web/src/pages/TeamDashboard.tsx#L360)
- [x] Cards/surfaces: `bg-neutral-900` — [TeamDashboard.tsx:630](../web/src/pages/TeamDashboard.tsx#L630)
- [x] Input backgrounds: `bg-neutral-950` — [TeamLogin.tsx:84](../web/src/pages/TeamLogin.tsx#L84)
- [x] Text: `text-neutral-50` (primary), `text-neutral-400` (secondary) — throughout
- [x] Accent: `accent-500`/`accent-600` for interactive elements — [TeamDashboard.tsx:387](../web/src/pages/TeamDashboard.tsx#L387)
- [x] Status: `status-success` (green), `status-warning` (yellow), `status-error` (red) — [TeamDashboard.tsx:697](../web/src/pages/TeamDashboard.tsx#L697)

### Status Indicators
- [x] Green dot (`bg-status-success animate-pulse`) for online/healthy — [TeamDashboard.tsx:697](../web/src/pages/TeamDashboard.tsx#L697)
- [x] Yellow dot (`bg-status-warning animate-pulse`) for stale/degraded — [TeamDashboard.tsx:698](../web/src/pages/TeamDashboard.tsx#L698)
- [x] Red dot (`bg-status-error`) for offline/error — [TeamDashboard.tsx:699](../web/src/pages/TeamDashboard.tsx#L699)
- [x] Status cards use colored dot indicator (NOT colored left border) — [TeamDashboard.tsx:995-1032](../web/src/pages/TeamDashboard.tsx#L995-L1032)

---

## Mobile Responsiveness

| Viewport | Layout | Source |
|----------|--------|--------|
| All widths | Single column, `grid-cols-2` for status cards | [TeamDashboard.tsx:726](../web/src/pages/TeamDashboard.tsx#L726) |
| Touch targets | All buttons have `min-h-[48px]` or `min-h-[40px]` + `min-h-[36px]` | [TeamDashboard.tsx:370,452,527](../web/src/pages/TeamDashboard.tsx#L370) |

> **Note:** The dashboard uses a fixed 2-column grid for status cards at all widths (not 4-column).

---

## States to Test

### Loading States
- [x] Initial load shows skeleton UI (pulsing header + tabs + cards + centered spinner + "Loading dashboard...") — [TeamDashboard.tsx:283-327](../web/src/pages/TeamDashboard.tsx#L283-L327)
- [x] Login button shows spinner + "Signing in..." when loading — [TeamLogin.tsx:121-128](../web/src/pages/TeamLogin.tsx#L121-L128)

### Empty States
- [x] No video URL: "No URL configured" per camera slot with Edit button — [VideoFeedManager.tsx:130](../web/src/components/Team/VideoFeedManager.tsx#L130)
- [x] No alerts: Alerts section not rendered at all (clean, no empty box) — [TeamDashboard.tsx:892](../web/src/pages/TeamDashboard.tsx#L892)

### Error States
- [x] 401 error: Clears token, redirects to login — [TeamDashboard.tsx:116-120](../web/src/pages/TeamDashboard.tsx#L116-L120)
- [x] 403 error: "Access denied. Your session may have expired." — [TeamDashboard.tsx:122-123](../web/src/pages/TeamDashboard.tsx#L122-L123)
- [x] Auth error display: EmptyState with "Your session has expired. Please log in again." + Login button — [TeamDashboard.tsx:330-352](../web/src/pages/TeamDashboard.tsx#L330-L352)
- [x] Network error: EmptyState with Retry button — [TeamDashboard.tsx:344-347](../web/src/pages/TeamDashboard.tsx#L344-L347)

---

## Automated Test

```bash
bash scripts/ui_smoke_pit_crew.sh
```

47 checks across 7 sections (A–G). Expected output: `ALL CHECKS PASSED`

---

## Known Limitations

1. **Visibility is read-only** — toggle was moved to edge Pit Crew Portal (TEAM-3 refactor)
2. **Telemetry sharing is read-only** — managed from edge Pit Crew Portal (TEAM-3 refactor)
3. **No "Add Feed" button** — 4 camera slots are pre-defined (main, cockpit, chase, suspension)
4. **No connection badge in footer** — footer only shows "Preview Fan View" link
5. **Diagnostics always visible** — not collapsible, always rendered in Ops tab
