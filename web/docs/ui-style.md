# Argus Design System - UI Style Guide

This document defines the design tokens and usage rules for the Argus v4 web UI.

## Design Principles

1. **Calm and Neutral** - Use true grays, no purple/blue tints on neutrals
2. **Subtle Depth** - Soft borders, minimal shadows, no heavy outlines
3. **Single Accent** - One accent color (blue) for primary actions only
4. **Hierarchy Through Typography** - Size and weight create hierarchy, not color
5. **Consistent Spacing** - Strict spacing scale, no arbitrary values

---

## Color Tokens

### Neutrals (Backgrounds, Surfaces, Text)

Use these for all non-accent UI elements:

| Token | Value | Usage |
|-------|-------|-------|
| `neutral-950` | `#0a0a0a` | Deepest background |
| `neutral-900` | `#171717` | Base background (`bg-base`) |
| `neutral-850` | `#1f1f1f` | Surface (`bg-surface`) |
| `neutral-800` | `#262626` | Elevated surface, cards |
| `neutral-700` | `#404040` | Strong borders |
| `neutral-600` | `#525252` | Disabled text |
| `neutral-500` | `#737373` | Muted text |
| `neutral-400` | `#a3a3a3` | Secondary text |
| `neutral-300` | `#d4d4d4` | Subtle text on light |
| `neutral-50` | `#fafafa` | Primary text (white) |

**CSS Variables:**
```css
var(--ds-bg-base)      /* neutral-900 */
var(--ds-bg-surface)   /* neutral-850 */
var(--ds-bg-elevated)  /* neutral-800 */
var(--ds-text-primary)   /* neutral-50 */
var(--ds-text-secondary) /* neutral-400 */
var(--ds-text-muted)     /* neutral-500 */
var(--ds-border-subtle)  /* neutral-800 */
var(--ds-border-default) /* neutral-700 */
```

### Accent (Primary Actions Only)

Use accent ONLY for:
- Primary buttons (CTA)
- Active/selected states
- Focus rings
- Links

| Token | Value | Usage |
|-------|-------|-------|
| `accent-600` | `#2563eb` | Primary button background |
| `accent-700` | `#1d4ed8` | Primary button hover |
| `accent-500` | `#3b82f6` | Focus ring, links |
| `accent-400` | `#60a5fa` | Active indicators |

**CSS Variables:**
```css
var(--ds-accent-500)
var(--ds-accent-600)
var(--ds-focus-ring-color)
```

### Status Colors

Use sparingly for semantic meaning:

| Token | Value | Usage |
|-------|-------|-------|
| `status-success` | `#22c55e` | Success states, online |
| `status-warning` | `#f59e0b` | Warning states, stale |
| `status-error` | `#ef4444` | Error states, offline |
| `status-info` | `#3b82f6` | Info states |

---

## Spacing Scale

**Strict scale: 4 / 8 / 12 / 16 / 24 / 32 / 48**

| Token | Value | Tailwind | Usage |
|-------|-------|----------|-------|
| `ds-1` | 4px | `space-ds-1` | Tight gaps (icon + text) |
| `ds-2` | 8px | `space-ds-2` | Compact gaps, inline items |
| `ds-3` | 12px | `space-ds-3` | Default small gap |
| `ds-4` | 16px | `space-ds-4` | Default gap, card padding |
| `ds-6` | 24px | `space-ds-6` | Comfortable gap |
| `ds-8` | 32px | `space-ds-8` | Section padding |
| `ds-12` | 48px | `space-ds-12` | Page sections |

**CSS Variables:**
```css
var(--ds-space-1)  /* 4px */
var(--ds-space-2)  /* 8px */
var(--ds-space-3)  /* 12px */
var(--ds-space-4)  /* 16px */
var(--ds-space-6)  /* 24px */
var(--ds-space-8)  /* 32px */
var(--ds-space-12) /* 48px */
```

### Utility Classes

```html
<!-- Stack (vertical) -->
<div class="ds-stack">...</div>      <!-- gap: 16px -->
<div class="ds-stack-sm">...</div>   <!-- gap: 8px -->
<div class="ds-stack-lg">...</div>   <!-- gap: 24px -->

<!-- Inline (horizontal) -->
<div class="ds-inline">...</div>     <!-- gap: 12px -->
<div class="ds-inline-sm">...</div>  <!-- gap: 8px -->
<div class="ds-inline-lg">...</div>  <!-- gap: 16px -->
```

---

## Typography Scale

| Class | Size | Weight | Usage |
|-------|------|--------|-------|
| `ds-text-display` | 32px / 2rem | 700 | Hero headlines |
| `ds-text-title` | 24px / 1.5rem | 700 | Page titles |
| `ds-text-heading` | 18px / 1.125rem | 600 | Section headers |
| `ds-text-body` | 16px / 1rem | 400 | Body text |
| `ds-text-body-sm` | 14px / 0.875rem | 400 | Secondary body |
| `ds-text-caption` | 12px / 0.75rem | 400 | Captions, hints |
| `ds-text-label` | 12px / 0.75rem | 500 | Labels (uppercase) |

**Tailwind fontSize tokens:**
```jsx
className="text-ds-title"    // 24px, bold
className="text-ds-heading"  // 18px, semibold
className="text-ds-body"     // 16px
className="text-ds-body-sm"  // 14px
className="text-ds-caption"  // 12px
```

---

## Border Radius

| Token | Value | Tailwind | Usage |
|-------|-------|----------|-------|
| `ds-sm` | 4px | `rounded-ds-sm` | Inputs, small elements |
| `ds-md` | 8px | `rounded-ds-md` | Buttons, cards |
| `ds-lg` | 12px | `rounded-ds-lg` | Modals, large cards |
| `ds-xl` | 16px | `rounded-ds-xl` | Hero elements |
| `ds-full` | 9999px | `rounded-ds-full` | Pills, avatars |

**Default usage:**
- Cards: `rounded-ds-lg` (12px)
- Buttons: `rounded-ds-md` (8px)
- Inputs: `rounded-ds-md` (8px)
- Badges/pills: `rounded-ds-full`

---

## Shadows / Elevation

Use shadows sparingly. Dark mode needs less shadow.

| Token | Usage |
|-------|-------|
| `shadow-ds-sm` | Subtle elevation (buttons) |
| `shadow-ds-md` | Medium elevation (cards) |
| `shadow-ds-lg` | High elevation (dropdowns) |
| `shadow-ds-dark-*` | Dark mode variants |
| `shadow-ds-overlay` | Modals, dialogs |

---

## Layout Containers

```html
<!-- Standard content container -->
<div class="ds-container">
  <!-- max-width: 1200px, centered, with gutters -->
</div>

<!-- Narrow container (forms, auth) -->
<div class="ds-container ds-container-narrow">
  <!-- max-width: 640px -->
</div>

<!-- Wide container (dashboards) -->
<div class="ds-container ds-container-wide">
  <!-- max-width: 1400px -->
</div>

<!-- Section spacing -->
<section class="ds-section">
  <!-- padding-top/bottom: 32px -->
</section>
```

---

## Focus States

All interactive elements MUST have visible focus states for accessibility.

```html
<!-- Focus ring appears on keyboard focus (Tab) -->
<button class="ds-btn ds-btn-primary">
  Click me
</button>

<!-- For elements on dark backgrounds, use inset focus -->
<button class="ds-focus-ring-inset">
  Dark background button
</button>
```

**CSS:**
```css
/* Applied globally via index.css */
*:focus-visible {
  outline: 2px solid var(--ds-focus-ring-color);
  outline-offset: 2px;
}
```

---

## Component Classes

### Buttons

```html
<button class="ds-btn ds-btn-primary">Primary</button>
<button class="ds-btn ds-btn-secondary">Secondary</button>
<button class="ds-btn ds-btn-danger">Danger</button>

<!-- Sizes -->
<button class="ds-btn ds-btn-primary ds-btn-sm">Small</button>
<button class="ds-btn ds-btn-primary ds-btn-lg">Large</button>

<!-- Disabled -->
<button class="ds-btn ds-btn-primary" disabled>Disabled</button>
```

### Cards

```html
<div class="ds-card">Basic card</div>
<div class="ds-card-elevated">Elevated card (with shadow)</div>
<button class="ds-card ds-card-interactive">Clickable card</button>
```

### Inputs

```html
<input class="ds-input" placeholder="Enter text..." />
```

### Badges

```html
<span class="ds-badge ds-badge-success">
  <span class="ds-badge-dot"></span>
  Online
</span>

<span class="ds-badge ds-badge-error">
  <span class="ds-badge-dot ds-badge-dot-pulse"></span>
  Offline
</span>

<span class="ds-badge ds-badge-neutral">Neutral</span>
```

---

## Do's and Don'ts

### Colors

| DO | DON'T |
|----|-------|
| Use `neutral-*` for backgrounds | Use arbitrary hex colors |
| Use `accent-*` for primary actions only | Use accent for decorative elements |
| Use `status-*` for semantic meaning | Use red/green without semantic meaning |

### Spacing

| DO | DON'T |
|----|-------|
| Use spacing scale: 4/8/12/16/24/32/48 | Use arbitrary values like 5px, 18px, 30px |
| Use `ds-stack` for vertical spacing | Mix different gap sizes in same context |
| Use `gap-*` instead of margins | Use margins for layout spacing |

### Typography

| DO | DON'T |
|----|-------|
| Use `ds-text-*` classes | Use arbitrary font sizes |
| Create hierarchy with size/weight | Use color for hierarchy |
| Use neutral colors for text | Use accent colors for body text |

### Borders & Shadows

| DO | DON'T |
|----|-------|
| Use `border-subtle` for cards | Use thick borders (2px+) |
| Use shadows sparingly | Add shadows to everything |
| Match shadow to dark mode | Use light-mode shadows in dark theme |

### Visual Style

| DO | DON'T |
|----|-------|
| Use solid colors | Use gradients |
| Use calm, muted tones | Use high-contrast neon colors |
| Keep UI quiet and neutral | Make every element "pop" |

---

## Migration Notes

The design system tokens are **additive**. Existing code continues to work:

- `bg-surface` → maps to `neutral-900`
- `primary-*` → alias for `accent-*`
- `text-gray-*` → still works (Tailwind default)

To migrate incrementally:
1. Use new tokens for new code
2. Refactor one component at a time
3. Replace `bg-gray-800` with `bg-neutral-800`
4. Replace ad-hoc spacing with `ds-space-*`

---

## Quick Reference

```jsx
// Backgrounds
"bg-neutral-900"     // Base
"bg-neutral-850"     // Surface (use: bg-surface)
"bg-neutral-800"     // Elevated

// Text
"text-neutral-50"    // Primary (white)
"text-neutral-400"   // Secondary
"text-neutral-500"   // Muted

// Borders
"border-neutral-800" // Subtle
"border-neutral-700" // Default

// Accent (primary actions only)
"bg-accent-600"      // Button background
"text-accent-500"    // Links

// Spacing
"p-ds-4"             // 16px padding
"gap-ds-3"           // 12px gap
"space-y-ds-6"       // 24px vertical spacing

// Border radius
"rounded-ds-md"      // 8px (buttons, cards)
"rounded-ds-lg"      // 12px (modals)
```
