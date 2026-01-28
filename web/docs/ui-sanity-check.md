# UI Sanity Check

Quick validation that the design system changes haven't broken the app.

## 1. Build Check

```bash
cd web

# Install dependencies (if needed)
npm install

# Run production build
npm run build
```

**Expected:** Build completes without errors.

If you see Tailwind warnings about unknown classes, that's OK - we've added new tokens that aren't used yet.

## 2. Dev Server Check

```bash
# Start dev server
npm run dev
```

**Expected:** Server starts at http://localhost:5173

## 3. Visual Smoke Test (3 Pages)

Open the dev server in a browser and verify these pages render correctly:

### Page 1: Landing Page (`/`)

- [ ] Page loads without console errors
- [ ] All 4 buttons visible and clickable
- [ ] Text is readable (not missing/invisible)
- [ ] No broken layouts or overlapping elements

### Page 2: Event Discovery (`/events`)

- [ ] Page loads without console errors
- [ ] Header shows "Argus Racing"
- [ ] Search input visible and functional
- [ ] Event cards render (if events exist) or empty state shows
- [ ] Skeleton loading appears briefly on initial load

### Page 3: Admin Dashboard (`/admin`)

- [ ] Page loads (may redirect to login if not authenticated)
- [ ] Login page renders correctly OR
- [ ] Dashboard shows system health panel
- [ ] Event list section visible
- [ ] Cards have visible borders/backgrounds

## 4. TypeScript Check

```bash
# Run type check
npm run typecheck
# or
npx tsc --noEmit
```

**Expected:** No type errors related to the config changes.

## 5. Quick Console Check

Open browser DevTools Console on any page:

- [ ] No `Tailwind CSS` errors
- [ ] No `Cannot read property` errors
- [ ] No `undefined` CSS variable warnings

## Troubleshooting

### "Unknown utility class" warnings

These are expected for new `ds-*` tokens that aren't used yet. Ignore them.

### Build fails with CSS error

1. Check `tailwind.config.js` syntax is valid JS
2. Check `index.css` has no unclosed brackets
3. Run `npm run dev` to see specific error

### Page renders blank

1. Check browser console for errors
2. Verify `index.css` is imported in `main.tsx`
3. Check for CSS syntax errors in added rules

### Colors look wrong

The design system uses true grays (`neutral-*`) instead of the original purple-tinted grays. This is intentional. Existing pages use legacy aliases that map to the new neutrals.

## Rollback

If something is seriously broken, you can revert the config changes:

```bash
git checkout -- web/tailwind.config.js web/src/index.css
```

The docs files (`docs/ui-style.md`, `docs/ui-sanity-check.md`) don't affect functionality.
