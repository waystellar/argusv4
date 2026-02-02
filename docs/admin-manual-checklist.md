# Admin Dashboard - 3-Minute Manual Verification Checklist

## Quick Start

```bash
# Start the stack
cd argus_v4
./scripts/run_all.sh

# Or start frontend only
cd argus_v4/web
npm run dev
```

Then open: http://localhost:5173/admin

---

## Checklist (3 minutes)

### 1. Page Load & Auth (~30 seconds)

| Check | What to Click | Expected Result |
|-------|---------------|-----------------|
| Navigate to Admin | Go to `/admin` | If logged in: Dashboard loads; If not: Redirects to `/admin/login` |
| Auth Check | N/A | `ProtectedAdminRoute` checks `/admin/auth/status` endpoint |
| Login | Enter admin password | Token stored in `localStorage`, redirects to `/admin` |
| Loading State | N/A | `SkeletonHealthPanel` and `SkeletonEventItem` appear briefly, then content loads |

### 2. Header & Navigation (~30 seconds)

| Element | What to See | Source |
|---------|-------------|--------|
| **Title** | "Admin Control Center" in `text-ds-heading` | `AdminDashboard.tsx:138` via `PageHeader` |
| **Back Button** | Left arrow navigating to `/` | `PageHeader` component |
| **Home Button** | House icon on right side | `PageHeader` component |
| **Header Background** | `bg-neutral-850` with `border-neutral-700` bottom border | `PageHeader.tsx:40` |
| **Page Background** | `bg-neutral-950` (darkest) | `AdminDashboard.tsx:136` |

### 3. System Health Panel (~15 seconds)

| Element | Expected Behavior | Source |
|---------|-------------------|--------|
| **Section Card** | `bg-neutral-900` with `rounded-ds-lg` corners | `AdminDashboard.tsx:153` |
| **Heading** | "System Health" with wrench icon in `text-ds-heading` | `AdminDashboard.tsx:155` |
| **Health Cards** | Four cards: Database, Redis, Trucks Online, Last Data | `AdminDashboard.tsx:172-223` |
| **Card Style** | `bg-neutral-800/50` with `rounded-ds-md` corners | `AdminDashboard.tsx:174` |
| **Card Value** | Large number with `text-ds-title font-bold` | `AdminDashboard.tsx:179` |
| **Card Label** | Label with `text-ds-caption text-neutral-500` | `AdminDashboard.tsx:182` |
| **Status Dot** | Green (`bg-status-success`) for healthy, yellow/red for degraded/error | `AdminDashboard.tsx:176` |
| **Health Check Button** | "Run Health Check" with `bg-accent-500` styling | `AdminDashboard.tsx:162` |
| **Loading State** | `SkeletonHealthPanel` while data loads | `AdminDashboard.tsx:170` |

### 4. Events List (~45 seconds)

| Element | Expected Behavior | Source |
|---------|-------------------|--------|
| **Section Card** | `bg-neutral-900 rounded-ds-lg border border-neutral-800` | `AdminDashboard.tsx:245` |
| **Heading** | "Events" with flag icon | `AdminDashboard.tsx:248` |
| **New Event Button** | `<Link>` to `/admin/events/new` with `bg-status-success` styling | `AdminDashboard.tsx:252-260` |
| **Search Input** | Text filter with `bg-neutral-800 border-neutral-700 rounded-ds-md` | `AdminDashboard.tsx:276-293` |
| **Status Filter** | Dropdown: All / Live / Upcoming / Finished | `AdminDashboard.tsx:296-305` |
| **Event Cards** | `bg-neutral-800/50 hover:bg-neutral-800 rounded-ds-md p-ds-4` | `AdminDashboard.tsx:324` |
| **Card Content** | Event name (bold), Badge (status), event ID (mono), date, vehicle count | `AdminDashboard.tsx:326-354` |
| **Status Badge** | `Badge` component: `error`=in_progress, `info`=upcoming, `neutral`=completed | `AdminDashboard.tsx:46-55` |
| **Card Click** | `<Link>` navigates to `/admin/events/{eventId}` | `AdminDashboard.tsx:321-323` |
| **Empty State (no events)** | `EmptyState` with "No Events Yet" and "Create Your First Event" action | `AdminDashboard.tsx:379-387` |
| **Empty State (no matches)** | `EmptyState` with "No events match your search" and "Clear filters" | `AdminDashboard.tsx:364-376` |
| **Loading State** | Three `SkeletonEventItem` placeholders | `AdminDashboard.tsx:311-316` |

**Note:** Events use a card-list layout, NOT a `<table>`. No table headers or columns.

### 5. Create Event Page (~30 seconds)

| Element | Expected Behavior | Source |
|---------|-------------------|--------|
| **Navigation** | "New Event" button navigates to `/admin/events/new` (separate page, not modal) | `AdminDashboard.tsx:252-260` |
| **Page** | Multi-step wizard with `PageHeader` | `EventCreate.tsx` |
| **Form Fields** | name, description, start/end dates, location, classes, max_vehicles, course_file | `EventCreate.tsx:61-70` |
| **Race Classes** | Predefined list: Ultra4, SCORE/BITD, Trucks, UTV, Moto, Other | `EventCreate.tsx:26-59` |
| **Input Style** | `bg-neutral-800` with `border-neutral-700`, `rounded-ds-md` | EventCreate design system tokens |
| **Submit** | Creates event via `POST /admin/events`, navigates to detail page on success | `EventCreate.tsx:89` |

**Note:** Event creation uses a dedicated page at `/admin/events/new`, NOT a modal overlay.

### 6. Event Detail Page (~30 seconds)

| Check | What to Click | Expected Result | Source |
|-------|---------------|-----------------|--------|
| Navigate | Click any event card | `EventDetail` page loads at `/admin/events/:eventId` | `App.tsx:127-131` |
| **Page Background** | N/A | `bg-neutral-900` | `EventDetail.tsx:322` |
| **Header** | "Event" title + event name subtitle via `PageHeader` | `EventDetail.tsx:323-326` |
| **Status Badge** | In header `rightSlot` with Badge component | `EventDetail.tsx:330-336` |
| **Status Controls** | "Start Race" (upcoming) or "End Race" (in_progress) buttons | `EventDetail.tsx:337-352` |
| **Course Map** | MapLibre map in `bg-neutral-800 rounded-ds-lg` card | `EventDetail.tsx:374-414` |
| **Event Details** | ID (with copy button), dates, classes, max vehicles, description | `EventDetail.tsx:416-496` |
| **Edit Button** | "Edit" link opens `EditEventModal` | `EventDetail.tsx:420-428` |
| **Vehicle List** | Cards with `divide-y divide-neutral-700` separator | `EventDetail.tsx:540-578` |
| **Vehicle Card** | Number, class `Badge`, team name, auth token (show/hide/copy/regenerate) | `VehicleCard` sub-component |
| **Add Vehicle** | Toggle form with number, team, driver, class inputs; validation | `AddVehicleForm` sub-component |
| **Empty State** | `EmptyState` with "No vehicles registered" | `EventDetail.tsx:549-561` |
| **Export CSV** | Download button exports vehicles to CSV | `EventDetail.tsx:242-267` |
| **Quick Links** | Fan Portal and Production Director external links | `EventDetail.tsx:625-648` |

---

## Sidebar Sections (AdminDashboard)

### Quick Actions
| Element | Behavior | Source |
|---------|----------|--------|
| **Start New Event** | Links to `/admin/events/new` | `AdminDashboard.tsx:401-410` |
| **View Live Event** | Shows only when `in_progress` event exists; links to fan portal | `AdminDashboard.tsx:412-423` |
| **Team Dashboard** | Links to `/team/login` | `AdminDashboard.tsx:425-434` |
| **API Documentation** | Opens `/docs` in new tab | `AdminDashboard.tsx:436-447` |
| **Bulk Import Vehicles** | Opens CSV upload modal (shows when events exist) | `AdminDashboard.tsx:449-464` |

### Getting Started Guide
- 4-step numbered list with `bg-accent-500` step indicators
- Steps: Create Event → Register Vehicles → Install Edge Software → Go Live

### System Info
- Shows Version (4.0.0) and API base URL

---

## Visual Quality Gates

### Typography
- [x] Headers use `text-ds-heading` (18px, semibold) — `AdminDashboard.tsx:155,248,398,471`
- [x] Body text is `text-ds-body` or `text-ds-body-sm` (16/14px) — used throughout
- [x] Captions/labels are `text-ds-caption` (12px) — `AdminDashboard.tsx:142,182,340,408`
- [x] Health values use `text-ds-title font-bold` (24px) — `AdminDashboard.tsx:179`

### Spacing
- [x] `gap-ds-6` (24px) between major sections — `AdminDashboard.tsx:149,151`
- [x] Section card padding is `p-ds-6` — `AdminDashboard.tsx:168`
- [x] Health card padding is `p-ds-4` (16px) — `AdminDashboard.tsx:174`
- [x] Form inputs use `px-ds-4 py-ds-2` — `AdminDashboard.tsx:281`

### Colors
- [x] Page background: `bg-neutral-950` — `AdminDashboard.tsx:136`
- [x] Section cards: `bg-neutral-900` — `AdminDashboard.tsx:153,245`
- [x] Inner cards: `bg-neutral-800/50` — `AdminDashboard.tsx:174,324`
- [x] Input backgrounds: `bg-neutral-800` with `border-neutral-700` — `AdminDashboard.tsx:281`
- [x] Primary text: `text-neutral-50` — throughout
- [x] Secondary text: `text-neutral-400` — `AdminDashboard.tsx:339`
- [x] Muted text: `text-neutral-500` — `AdminDashboard.tsx:142,182`
- [x] Accent: `accent-500` / `accent-600` for buttons — `AdminDashboard.tsx:162`
- [x] Success: `bg-status-success` for "New Event" button — `AdminDashboard.tsx:254`
- [x] Status indicators: `bg-status-success`, `bg-status-warning`, `bg-status-error` — `AdminDashboard.tsx:58-67`

### Status Badges
- [x] Uses `Badge` component (imported from `../../components/ui/Badge`)
- [x] `variant="error"` for `in_progress` / LIVE events — `AdminDashboard.tsx:49`
- [x] `variant="info"` for `upcoming` events — `AdminDashboard.tsx:51`
- [x] `variant="neutral"` for `completed` / default — `AdminDashboard.tsx:53`
- [x] EventDetail uses different mapping: `success`=in_progress, `warning`=upcoming — `EventDetail.tsx:65-74`

### Border Radius
- [x] Section cards: `rounded-ds-lg` (12px) — `AdminDashboard.tsx:153`
- [x] Inner cards/inputs: `rounded-ds-md` (8px) — `AdminDashboard.tsx:174,281`
- [x] Small elements: `rounded-ds-sm` (4px) — `AdminDashboard.tsx:340`

---

## States to Test

### Loading States
- [x] Health panel shows `SkeletonHealthPanel` — `AdminDashboard.tsx:170`
- [x] Events list shows `SkeletonEventItem` rows — `AdminDashboard.tsx:311-316`
- [x] Vehicle list shows `SkeletonVehicleCard` — `EventDetail.tsx:542-547`
- [x] "Run Health Check" button shows "Checking..." when running — `AdminDashboard.tsx:164`
- [x] Event detail loading shows centered spinner — `EventDetail.tsx:302-308`

### Empty States
- [x] No events: `EmptyState` with "No Events Yet" and create action — `AdminDashboard.tsx:379-387`
- [x] No search results: `EmptyState` with "No events match your search" — `AdminDashboard.tsx:364-376`
- [x] No vehicles: `EmptyState` with "No vehicles registered" — `EventDetail.tsx:549-561`
- [x] No course: "No course uploaded" overlay on map — `EventDetail.tsx:850-860`

### Error States
- [x] Auth failure: `ProtectedAdminRoute` redirects to `/admin/login` — `App.tsx:30-94`
- [x] Health check error: Shows error message with "Retry" button — `AdminDashboard.tsx:226-239`
- [x] Form validation: Inline errors with field-level messages — `AddVehicleForm` sub-component
- [x] Toast notifications: `useToast()` for success/error feedback — throughout

---

## Mobile Responsiveness

| Viewport | Layout | Source |
|----------|--------|--------|
| Desktop (>=1024px) | 3-column grid: 2-col main + 1-col sidebar | `AdminDashboard.tsx:149` `lg:grid-cols-3` |
| Tablet / Mobile (<1024px) | Single column: all sections stacked | Grid collapses to `grid-cols-1` |
| Health cards | 2-col on mobile, 4-col on md+ | `AdminDashboard.tsx:172` `grid-cols-2 md:grid-cols-4` |
| Search + filter | Stacked on mobile, inline on sm+ | `AdminDashboard.tsx:265` `flex-col sm:flex-row` |

---

## Automated Test

Run the smoke test:
```bash
bash scripts/ui_smoke_admin.sh
```

Expected output: `All critical checks passed!`

The smoke test validates 38 checks across 7 sections:
- A: Source files exist (6 checks)
- B: AdminDashboard design system (10 checks)
- C: EventDetail design system (10 checks)
- D: Routing configuration (5 checks)
- E: Key UI elements (10 checks)
- F: Design token config (5 checks)
- G: Frontend server runtime (3 checks, skipped if not running)

**Limitation:** The smoke test validates source code structure and tokens via `grep`. It cannot validate rendered UI output without a browser. Manual verification is required for visual layout, hover states, and responsive behavior.

---

## Files

| File | Purpose |
|------|---------|
| `web/src/pages/admin/AdminDashboard.tsx` | Main admin page — health panel, event list, sidebar |
| `web/src/pages/admin/EventDetail.tsx` | Event management — map, vehicles, status controls |
| `web/src/pages/admin/EventCreate.tsx` | Multi-step event creation wizard |
| `web/src/pages/admin/AdminLogin.tsx` | Password-based admin authentication |
| `web/src/App.tsx` | Route definitions and `ProtectedAdminRoute` auth guard |
| `web/src/components/ui/Badge.tsx` | Status badge component (variants: neutral, success, warning, error, info) |
| `web/src/components/ui/EmptyState.tsx` | Empty state placeholder with action buttons |
| `web/src/components/common/PageHeader.tsx` | Reusable header with back/home navigation |
| `web/src/components/common/Skeleton.tsx` | Loading placeholder components |
| `web/tailwind.config.js` | Design system token definitions |
| `scripts/ui_smoke_admin.sh` | Automated smoke test (38 checks) |
| `docs/admin-manual-checklist.md` | This file |
