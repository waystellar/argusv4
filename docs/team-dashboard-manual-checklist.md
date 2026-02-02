# Team Dashboard — 3-Minute Manual Verification Checklist

> **Reconciled against source code.** Every claim is backed by file:line evidence.
> Last reconciled: 2026-01-29

---

## Quick Start

```bash
cd argus_v4
./scripts/run_all.sh
# Or: cd argus_v4/web && npm run dev
```

Then open: http://localhost:5173/team (redirects to `/team/dashboard`)

---

## Route Structure

| Route | Behavior | Source |
|-------|----------|--------|
| `/team` | Redirects to `/team/dashboard` | [App.tsx:145](../web/src/App.tsx#L145) |
| `/team/login` | Login form (vehicle number + team token) | [App.tsx:146](../web/src/App.tsx#L146), [TeamLogin.tsx](../web/src/pages/TeamLogin.tsx) |
| `/team/dashboard` | Main dashboard (auth required) | [App.tsx:147](../web/src/App.tsx#L147), [TeamDashboard.tsx](../web/src/pages/TeamDashboard.tsx) |

> **Note:** "Pit Crew" refers to the **edge device's local dashboard** (`edge/pit_crew_dashboard.py`), not a separate cloud route. The Team Dashboard is a cloud gateway that links to the edge Pit Crew Portal when edge is online.

---

## Source Files

| File | Purpose |
|------|---------|
| [TeamDashboard.tsx](../web/src/pages/TeamDashboard.tsx) | Main dashboard (1212 lines) — Ops + Sharing tabs |
| [TeamLogin.tsx](../web/src/pages/TeamLogin.tsx) | Login form (146 lines) |
| [VideoFeedManager.tsx](../web/src/components/Team/VideoFeedManager.tsx) | 4-camera YouTube URL config (145 lines) |
| [PageHeader.tsx](../web/src/components/common/PageHeader.tsx) | Shared header with Back, Title, Home, rightSlot |
| [App.tsx](../web/src/App.tsx) | Route definitions |

---

## Checklist (3 minutes)

### 1. Page Load & Auth (~30 seconds)

| Check | What to Click | Expected Result | Source |
|-------|---------------|-----------------|--------|
| Navigate to `/team` | Go to /team | Redirects to /team/dashboard | [App.tsx:145](../web/src/App.tsx#L145) |
| Auth check | N/A | No `team_token` in localStorage → redirects to `/team/login` | [TeamDashboard.tsx:83-85](../web/src/pages/TeamDashboard.tsx#L83-L85) |
| Login | Vehicle number + token → "Sign In" | POST `/api/v1/team/login`, stores token, navigates to `/team/dashboard` | [TeamLogin.tsx:19-48](../web/src/pages/TeamLogin.tsx#L19-L48) |
| Loading state | N/A | Skeleton UI (pulsing header + tabs + cards + spinner + "Loading dashboard...") | [TeamDashboard.tsx:283-327](../web/src/pages/TeamDashboard.tsx#L283-L327) |

### 2. Header & Event Context (~30 seconds)

| Element | What to See | Source |
|---------|-------------|--------|
| **Title** | "Team Dashboard" | [TeamDashboard.tsx:363](../web/src/pages/TeamDashboard.tsx#L363) |
| **Subtitle** | "Manage your truck" | [TeamDashboard.tsx:364](../web/src/pages/TeamDashboard.tsx#L364) |
| **Back button** | Left side, navigates to `/team/login` | [TeamDashboard.tsx:365](../web/src/pages/TeamDashboard.tsx#L365) |
| **Logout button** | Right side, "Logout" text | [TeamDashboard.tsx:368-373](../web/src/pages/TeamDashboard.tsx#L368-L373) |
| **Home button** | Right side (house icon), navigates to `/` | [PageHeader.tsx:69-79](../web/src/components/common/PageHeader.tsx#L69-L79) |
| **Edge URL bar** | "Open Pit Crew Portal" (green dot) when edge online, "Waiting for edge device" otherwise | [TeamDashboard.tsx:377-415](../web/src/pages/TeamDashboard.tsx#L377-L415) |
| **Active Event** | Green dot + "Active Event" + LIVE/STALE/OFFLINE/WAITING Badge + event ID | [TeamDashboard.tsx:419-430](../web/src/pages/TeamDashboard.tsx#L419-L430) |
| **No Event** | Gray dot + "No Active Event" + "Register to go live" | [TeamDashboard.tsx:432-439](../web/src/pages/TeamDashboard.tsx#L432-L439) |

### 3. My Truck Section (~30 seconds)

| Element | Expected Behavior | Source |
|---------|-------------------|--------|
| **Section header** | "MY TRUCK" uppercase with tracking-wide | [TeamDashboard.tsx:629](../web/src/pages/TeamDashboard.tsx#L629) |
| **Truck card** | Vehicle number (#N) in accent box, team name, vehicle ID mono | [TeamDashboard.tsx:630-654](../web/src/pages/TeamDashboard.tsx#L630-L654) |
| **Status badges** | Online/Streaming/Offline/Waiting/No Data + Visible/Hidden | [TeamDashboard.tsx:644-653](../web/src/pages/TeamDashboard.tsx#L644-L653) |
| **Quick stats** | 3-column grid: Hz, Last Seen, Queue | [TeamDashboard.tsx:657-676](../web/src/pages/TeamDashboard.tsx#L657-L676) |

### 4. Next Action Prompt (~15 seconds)

| State | Alert Label | Message | Source |
|-------|-------------|---------|--------|
| No event | "Registration Required" | "No active event found for this truck." | [TeamDashboard.tsx:589-594](../web/src/pages/TeamDashboard.tsx#L589-L594) |
| Waiting for edge | "Waiting for Edge" | "Waiting for first heartbeat from edge device." | [TeamDashboard.tsx:596-601](../web/src/pages/TeamDashboard.tsx#L596-L601) |
| Edge offline | "Connect Edge" | "Edge device is not connected." | [TeamDashboard.tsx:603-611](../web/src/pages/TeamDashboard.tsx#L603-L611) |
| No stream | "Start Streaming" | "Video stream is not active." | [TeamDashboard.tsx:613-618](../web/src/pages/TeamDashboard.tsx#L613-L618) |
| All good | No alert shown | `getNextAction()` returns null | [TeamDashboard.tsx:620](../web/src/pages/TeamDashboard.tsx#L620) |

### 5. Streaming & Edge Status (~30 seconds)

| Element | Expected Behavior | Source |
|---------|-------------------|--------|
| **Section header** | "STREAMING & EDGE STATUS" uppercase | [TeamDashboard.tsx:691](../web/src/pages/TeamDashboard.tsx#L691) |
| **Edge Device card** | Heartbeat indicator: "Edge Online"/"Heartbeat delayed"/"Edge Offline"/"Waiting" + Last Seen | [TeamDashboard.tsx:692-724](../web/src/pages/TeamDashboard.tsx#L692-L724) |
| **GPS card** | Locked (green), Searching (yellow), No Signal (red), Unknown (gray) | [TeamDashboard.tsx:728-745](../web/src/pages/TeamDashboard.tsx#L728-L745) |
| **CAN Bus card** | Active (green), Idle (yellow), Error (red), Unknown (gray) | [TeamDashboard.tsx:748-763](../web/src/pages/TeamDashboard.tsx#L748-L763) |
| **Video card** | Streaming (green), Configured (blue), Not Set (gray), Unknown (gray) | [TeamDashboard.tsx:766-781](../web/src/pages/TeamDashboard.tsx#L766-L781) |
| **Visibility card** | READ-ONLY: "Visible"/"Hidden" + "Managed from Pit Crew" | [TeamDashboard.tsx:783-802](../web/src/pages/TeamDashboard.tsx#L783-L802) |
| **Stream control** | Only visible when `video_status === 'streaming'` + event active | [TeamDashboard.tsx:805-818](../web/src/pages/TeamDashboard.tsx#L805-L818) |

### 6. Diagnostics Section (~30 seconds)

| Element | Expected Behavior | Source |
|---------|-------------------|--------|
| **Section header** | "DIAGNOSTICS" uppercase + Copy button | [TeamDashboard.tsx:822-850](../web/src/pages/TeamDashboard.tsx#L822-L850) |
| **Copy button** | "Copy" → copies diagnostics → shows "Copied!" | [TeamDashboard.tsx:825-849](../web/src/pages/TeamDashboard.tsx#L825-L849) |
| **Diagnostic rows** | Vehicle ID, Event ID, Edge Status, Edge Last Seen, Edge URL (if present), Edge IP (if present), Edge Version (if present), Queue Depth, Last Position | [TeamDashboard.tsx:853-887](../web/src/pages/TeamDashboard.tsx#L853-L887) |

### 7. Tab Navigation (~15 seconds)

| Tab | Label | Expected Content | Source |
|-----|-------|------------------|--------|
| **Ops** (default) | "Ops" (with alert dot if stale/offline) | My Truck, Next Action, Streaming Status, Diagnostics, Alerts | [TeamDashboard.tsx:452-472](../web/src/pages/TeamDashboard.tsx#L452-L472) |
| **Sharing** | "Sharing" | Visibility (read-only), Telemetry (read-only), Video feeds | [TeamDashboard.tsx:474-492](../web/src/pages/TeamDashboard.tsx#L474-L492) |

### 8. Sharing Tab Detail

| Element | Expected Behavior | Source |
|---------|-------------------|--------|
| **Event Status** | "Active Event" (success) or "No Active Event" (warning) | [TeamDashboard.tsx:941-951](../web/src/pages/TeamDashboard.tsx#L941-L951) |
| **Vehicle Visibility** | READ-ONLY: Badge "Visible"/"Hidden" + "Manage visibility from your Pit Crew Portal" | [TeamDashboard.tsx:953-969](../web/src/pages/TeamDashboard.tsx#L953-L969) |
| **Telemetry Sharing** | READ-ONLY: "Telemetry sharing policy is managed from your Pit Crew Portal" | [TeamDashboard.tsx:971-977](../web/src/pages/TeamDashboard.tsx#L971-L977) |
| **Video Feeds** | 4 camera slots (Main, Cockpit, Chase, Suspension), each with URL or "No URL configured", Edit/Save/Cancel | [VideoFeedManager.tsx:21-145](../web/src/components/Team/VideoFeedManager.tsx#L21-L145) |

### 9. Footer

| Element | What to See | Source |
|---------|-------------|--------|
| **Preview Fan View** | Link to fan view (opens in new tab). Only visible when event_id exists AND vehicle is visible. | [TeamDashboard.tsx:519-540](../web/src/pages/TeamDashboard.tsx#L519-L540) |

---

## Visual Quality Gates

### Typography
- [x] Title: `text-ds-heading` via PageHeader — [PageHeader.tsx:57](../web/src/components/common/PageHeader.tsx#L57)
- [x] Body: `text-ds-body` / `text-ds-body-sm` — throughout
- [x] Captions: `text-ds-caption` — [TeamDashboard.tsx:629](../web/src/pages/TeamDashboard.tsx#L629)
- [x] Section headers: `uppercase tracking-wide` — [TeamDashboard.tsx:629,691,824](../web/src/pages/TeamDashboard.tsx#L629)

### Spacing
- [x] Section gaps: `space-y-ds-4` — [TeamDashboard.tsx:626](../web/src/pages/TeamDashboard.tsx#L626)
- [x] Card padding: `p-ds-4` — [TeamDashboard.tsx:630](../web/src/pages/TeamDashboard.tsx#L630)
- [x] Status cards: 2-column `grid-cols-2 gap-ds-3` — [TeamDashboard.tsx:726](../web/src/pages/TeamDashboard.tsx#L726)

### Colors
- [x] Background: `bg-neutral-950` — [TeamDashboard.tsx:360](../web/src/pages/TeamDashboard.tsx#L360)
- [x] Cards: `bg-neutral-900` — [TeamDashboard.tsx:630](../web/src/pages/TeamDashboard.tsx#L630)
- [x] Header: `bg-neutral-850 border-neutral-700` — [PageHeader.tsx:40](../web/src/components/common/PageHeader.tsx#L40)
- [x] Text: `text-neutral-50` (primary), `text-neutral-400` (secondary)
- [x] Accent: `accent-500/600` for interactive
- [x] Status: `status-success` (green), `status-warning` (yellow), `status-error` (red)

### Status Badges
- [x] Badge component with variant prop — [TeamDashboard.tsx:645](../web/src/pages/TeamDashboard.tsx#L645)
- [x] Pulsing dot for active states — [TeamDashboard.tsx:645](../web/src/pages/TeamDashboard.tsx#L645) (`pulse={truckStatus.variant === 'success'}`)
- [x] Colors: success=green, warning=yellow, error=red, neutral=gray

---

## States to Test

### Loading States
- [x] Skeleton UI: pulsing header + tabs + content placeholders + centered spinner + "Loading dashboard..." — [TeamDashboard.tsx:283-327](../web/src/pages/TeamDashboard.tsx#L283-L327)
- [x] Login button: spinner + "Signing in..." — [TeamLogin.tsx:121-128](../web/src/pages/TeamLogin.tsx#L121-L128)

### No Event State
- [x] Event context bar: "No Active Event" + "Register to go live" — [TeamDashboard.tsx:432-439](../web/src/pages/TeamDashboard.tsx#L432-L439)
- [x] Next action: "Registration Required" alert — [TeamDashboard.tsx:589-594](../web/src/pages/TeamDashboard.tsx#L589-L594)
- [x] Status cards: show "Unknown" state — status defaults to `'unknown'` when diagnostics null

### Error States
- [x] 401: Clears token, redirects to login — [TeamDashboard.tsx:116-120](../web/src/pages/TeamDashboard.tsx#L116-L120)
- [x] 403: "Access denied. Your session may have expired." — [TeamDashboard.tsx:122-123](../web/src/pages/TeamDashboard.tsx#L122-L123)
- [x] Auth error display: EmptyState + "Your session has expired" + Login button — [TeamDashboard.tsx:330-352](../web/src/pages/TeamDashboard.tsx#L330-L352)
- [x] Network error: EmptyState + Retry button — [TeamDashboard.tsx:344-347](../web/src/pages/TeamDashboard.tsx#L344-L347)

---

## Mobile Responsiveness

| Viewport | Layout | Source |
|----------|--------|--------|
| All widths | Single column, `grid-cols-2` for status cards | [TeamDashboard.tsx:726](../web/src/pages/TeamDashboard.tsx#L726) |
| Touch targets | `min-h-[48px]` / `min-h-[44px]` / `min-h-[40px]` on all buttons | PageHeader + TeamDashboard |

---

## Automated Test

```bash
bash scripts/ui_smoke_team_dashboard.sh
```

57 checks across 11 sections (A–K). Expected output: `All critical checks passed!`

---

## Known Limitations

1. **Visibility is read-only** — toggle moved to edge Pit Crew Portal (TEAM-3 refactor)
2. **Telemetry sharing is read-only** — managed from edge Pit Crew Portal (TEAM-3)
3. **No "Add Feed" button** — 4 camera slots are pre-defined (main, cockpit, chase, suspension)
4. **No connection badge in footer** — footer shows "Preview Fan View" link only
5. **Diagnostics always visible** — not collapsible, always rendered in Ops tab
6. **No bare `/team` page** — `/team` redirects to `/team/dashboard` which requires auth
