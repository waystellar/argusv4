# Content Security Policy (CSP) — Edge & Cloud

## Overview

Argus uses Content-Security-Policy headers on both edge (pit crew dashboard) and cloud (nginx) to restrict resource loading. This document describes the expected CSP for each environment and how to verify.

---

## Edge CSP (Pit Crew Dashboard)

**Source of truth:** `edge/pit_crew_dashboard.py` (function `handle_index`, ~line 8625)

The edge dashboard serves HTML with a per-request nonce for script-src.

### Expected Directives

| Directive | Value | Rationale |
|-----------|-------|-----------|
| `default-src` | `'self'` | Baseline: only same-origin |
| `script-src` | `'nonce-<random>'` `https://cdn.jsdelivr.net` `https://unpkg.com` | Leaflet + Chart.js from CDN; nonce blocks inline XSS |
| `style-src` | `'self'` `'unsafe-inline'` `https://unpkg.com` | Leaflet CSS; inline styles used by Leaflet markers |
| `img-src` | `'self'` `data:` `https://*.tile.opentopomap.org` `https://*.basemaps.cartocdn.com` `https://*.tile.openstreetmap.org` | Map tiles from three providers |
| `connect-src` | `'self'` `https://*.tile.opentopomap.org` `https://*.basemaps.cartocdn.com` `https://*.tile.openstreetmap.org` | Tile fetch via JS (MapLibre/Leaflet) |
| `font-src` | `'self'` | No external fonts |
| `frame-src` | `https://www.youtube.com` `https://www.youtube-nocookie.com` | YouTube video embeds for camera feeds |
| `object-src` | `'none'` | Block Flash/Java plugins |

### Verification

```bash
# Source-code check (always works):
bash scripts/regress/csp_edge.sh

# Runtime check (requires edge running at port 8080):
curl -sI http://localhost:8080/ | grep -i content-security-policy
```

Expected: `frame-src https://www.youtube.com https://www.youtube-nocookie.com` in the header.

---

## Cloud CSP (nginx)

**Source of truth:** `web/nginx.conf` (line ~143)

The cloud frontend is served by nginx with a static CSP header.

### Expected Directives

| Directive | Value | Rationale |
|-----------|-------|-----------|
| `default-src` | `'self'` | Baseline |
| `script-src` | `'self'` `'unsafe-inline'` | Vite build injects inline scripts; nonce migration is P2 |
| `style-src` | `'self'` `'unsafe-inline'` | Tailwind + dynamic styles; nonce migration is P2 |
| `img-src` | `'self'` `data:` `blob:` `https://basemaps.cartocdn.com` `https://*.basemaps.cartocdn.com` `https://tile.openstreetmap.org` `https://*.tile.openstreetmap.org` `https://tile.opentopomap.org` `https://*.tile.opentopomap.org` `https://i.ytimg.com` `https://*.ytimg.com` | Map tiles (3 providers) + YouTube thumbnails |
| `font-src` | `'self'` `data:` | Self-hosted fonts |
| `connect-src` | `'self'` `ws:` `wss:` `https://basemaps.cartocdn.com` `https://*.basemaps.cartocdn.com` `https://tile.openstreetmap.org` `https://*.tile.openstreetmap.org` `https://tile.opentopomap.org` `https://*.tile.opentopomap.org` | SSE, WebSocket, tile fetches |
| `worker-src` | `'self'` `blob:` | Service worker + MapLibre web workers |
| `manifest-src` | `'self'` | PWA manifest |
| `frame-src` | `'self'` `https://www.youtube.com` `https://www.youtube-nocookie.com` | YouTube embeds (Control Room + Fan Watch) |
| `object-src` | `'none'` | Block plugins |
| `base-uri` | `'self'` | Prevent base tag injection |
| `frame-ancestors` | `'self'` | Prevent clickjacking |

### Service Worker CSP

The `/sw.js` route has a separate, tighter CSP:
```
default-src 'self'; script-src 'self'; connect-src 'self' https://*.basemaps.cartocdn.com https://*.tile.openstreetmap.org https://*.tile.opentopomap.org;
```

### Verification

```bash
# Source-code check (always works):
bash scripts/regress/csp_cloud.sh

# Runtime check (requires nginx — Vite dev server does NOT set CSP):
curl -sI https://<cloud-host>/ | grep -i content-security-policy
```

---

## Tile Domains Reference

All tile domains used in the app are defined in `web/src/config/basemap.ts`:

| Provider | Tile URL Pattern | Used In |
|----------|-----------------|---------|
| CARTO Positron | `https://{a,b,c}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png` | Base layer (always) |
| OpenTopoMap | `https://{a,b,c}.tile.opentopomap.org/{z}/{x}/{y}.png` | Topo overlay |
| OpenStreetMap | `https://*.tile.openstreetmap.org/...` | Fallback / attribution |

Both edge and cloud CSP must include these domains in `img-src` and `connect-src`.

---

## Known Limitations

1. **Cloud `script-src 'unsafe-inline'`** — Vite injects inline scripts during build. Removing `'unsafe-inline'` requires build-time nonce injection (tracked as P2-1).
2. **Cloud `style-src 'unsafe-inline'`** — Tailwind and dynamic component styles use inline styles. Removing requires CSP hash extraction (tracked as P2-1).
3. **Edge `style-src 'unsafe-inline'`** — Leaflet marker styles are inline. Cannot remove without Leaflet changes.

---

## Systemd StartLimit Policy

The argus-uplink service uses the same crash-loop protection as GPS/CAN/ANT:

| Setting | Value | Effect |
|---------|-------|--------|
| `StartLimitIntervalSec` | `60` | Window for counting failures |
| `StartLimitBurst` | `3` | Max starts within window |
| `Restart` | `on-failure` | Only restart on non-zero exit |
| `RestartSec` | `10` | Delay between restart attempts |

If the service crashes 3 times in 60 seconds, systemd stops it and reports `start-limit-hit`. The pit crew dashboard detects this via `_is_rate_limited()` and shows "Restart limit hit" in the service status panel.

### Verification

```bash
# Source-code check:
bash scripts/regress/systemd_uplink.sh

# Live system check (on edge device):
systemctl show argus-uplink -p StartLimitIntervalSec -p StartLimitBurst
# Expected: StartLimitIntervalSec=60s / StartLimitBurst=3
```
