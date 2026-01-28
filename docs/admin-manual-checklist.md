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
| Navigate to Admin | Go to /admin | If logged in: Dashboard loads; If not: Login form appears |
| Auth Check | N/A | Dashboard shows or "Enter admin token" prompt |
| Loading State | N/A | Skeleton UI appears briefly, then content loads |

### 2. Header & Navigation (~30 seconds)

| Element | What to See |
|---------|-------------|
| **Title** | "Admin Control Center" |
| **Navigation** | Links to Home, Events, other admin areas |
| **Background** | `bg-neutral-950` (darkest) |
| **Header Style** | `bg-neutral-900` with `border-neutral-800` bottom border |

### 3. Stats Row (~15 seconds)

| Element | Expected Behavior |
|---------|-------------------|
| **Stats Cards** | Three cards: Total Events, Active Now, Total Vehicles |
| **Card Style** | `bg-neutral-900` with `rounded-ds-lg` corners |
| **Typography** | Large number with `text-ds-heading`, label with `text-ds-caption` |
| **Active Count** | Shows green accent for active events |

### 4. Events Table (~45 seconds)

| Element | Expected Behavior |
|---------|-------------------|
| **Table Header** | Columns: Event Name, Status, Vehicles, Start Date, Actions |
| **Row Hover** | `hover:bg-neutral-800` on table rows |
| **Status Badge** | Uses Badge component with variants (error=in_progress, info=upcoming, neutral=completed) |
| **Empty State** | If no events: EmptyState component with "No events yet" and create button |
| **Row Click** | Clicking row navigates to /admin/events/:id |

### 5. Create Event Modal (~30 seconds)

| Element | Expected Behavior |
|---------|-------------------|
| **Button** | "Create Event" button with accent styling |
| **Modal Open** | Click button opens modal overlay |
| **Form Fields** | Event name, description, start/end dates, location |
| **Form Labels** | Consistent `text-ds-body-sm` with `text-neutral-300` |
| **Input Style** | `bg-neutral-800` with `border-neutral-700`, `rounded-ds-md` |
| **Submit Button** | Primary action with accent color |
| **Cancel Button** | Secondary action with neutral styling |

### 6. Event Detail Page (~30 seconds)

| Check | What to Click | Expected Result |
|-------|---------------|-----------------|
| Navigate | Click any event row | EventDetail page loads |
| **Header** | Event name, status badge, edit button |
| **Course Map** | MapLibre map showing course (if coordinates set) |
| **Vehicle List** | Table of registered vehicles |
| **Vehicle Card** | Number, team name, class badge (Badge component) |
| **Add Vehicle** | Form with number, team, class inputs |
| **Empty State** | If no vehicles: EmptyState with "No vehicles registered" |

---

## Visual Quality Gates

### Typography
- [ ] Headers use `text-ds-heading` (18px, semibold)
- [ ] Body text is `text-ds-body` or `text-ds-body-sm` (16/14px)
- [ ] Captions/labels are `text-ds-caption` (12px)
- [ ] Table headers use uppercase with `tracking-wide`

### Spacing
- [ ] Consistent `gap-ds-4` (16px) between sections
- [ ] Card padding is `p-ds-4` (16px)
- [ ] Table cell padding is `px-ds-4 py-ds-3`
- [ ] Form inputs use consistent spacing

### Colors
- [ ] Background: `bg-neutral-950` (darkest)
- [ ] Cards/surfaces: `bg-neutral-900`
- [ ] Input backgrounds: `bg-neutral-800`
- [ ] Borders: `border-neutral-700` or `border-neutral-800`
- [ ] Text: `text-neutral-50` (primary), `text-neutral-400` (secondary)
- [ ] Accent: `accent-500/600` for interactive elements
- [ ] Status: Uses Badge component with proper variants

### Status Badges
- [ ] Uses Badge component (not inline classes)
- [ ] `variant="error"` for in_progress/live events
- [ ] `variant="info"` for upcoming events
- [ ] `variant="neutral"` for completed/default states
- [ ] `variant="success"` for healthy/online states

### Border Radius
- [ ] Cards use `rounded-ds-lg` (12px)
- [ ] Inputs use `rounded-ds-md` (8px)
- [ ] Badges use `rounded-ds-sm` (4px) or pill shape

---

## States to Test

### Loading States
- [ ] Initial load shows skeleton UI (pulsing placeholders)
- [ ] Table shows skeleton rows while loading
- [ ] Buttons show spinner when submitting

### Empty States
- [ ] No events: EmptyState component with create action
- [ ] No vehicles: EmptyState component with add action
- [ ] Uses consistent EmptyState component styling

### Error States
- [ ] Auth error: "Session expired" with login redirect
- [ ] Network error: Retry button with error message
- [ ] Form validation: Inline errors with actionable text
- [ ] Toast notifications for success/error feedback

---

## Mobile Responsiveness

| Viewport | Layout |
|----------|--------|
| Desktop (>=1024px) | Full layout, multi-column stats, wide tables |
| Tablet (768-1023px) | Compact layout, 2-column stats, scrollable tables |
| Mobile (<768px) | Single column, stacked cards, horizontal scroll for tables |

---

## Automated Test

Run the smoke test:
```bash
./scripts/ui_smoke_admin.sh
```

Expected output: "All critical checks passed!"

---

## Before/After Summary (UI-7)

### Before (UI-6)
- Mixed `gray-*` colors (gray-400, gray-700, gray-800, gray-900)
- Inconsistent typography (text-lg, text-sm, text-xs)
- Ad-hoc spacing (px-4, py-3, gap-2)
- Inline status badge styling
- No shared EmptyState component
- Inconsistent border radius values

### After (UI-7)
- Consistent `neutral-*` palette (neutral-50 to neutral-950)
- Design system typography (text-ds-heading, text-ds-body-sm, text-ds-caption)
- Token-based spacing (p-ds-4, gap-ds-3, px-ds-4)
- Badge component for all status displays
- EmptyState component for empty tables
- Consistent `rounded-ds-*` border radius tokens
- Proper `status-*` colors for semantic indicators
- Improved table styling with hover states
- Standardized form inputs with consistent styling

---

## Files Changed in UI-7

| File | Changes |
|------|---------|
| `web/src/pages/admin/AdminDashboard.tsx` | Design system tokens, Badge/EmptyState components |
| `web/src/pages/admin/EventDetail.tsx` | Design system tokens, Badge/EmptyState components |
| `scripts/ui_smoke_admin.sh` | New smoke test script |
| `docs/admin-manual-checklist.md` | New manual checklist |
