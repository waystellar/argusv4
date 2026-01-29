# CODEX Fix Queue (P0 → P2)

This queue orders fixes based on CODEX-0 through CODEX-6 findings. Each entry includes owner, blast radius, exact files, and a regression test gate.

## P0 — blocks core flows / system operation

1) **Edge CSP blocks YouTube iframes (frame-src 'none')**
   - **Owner:** edge
   - **Blast radius:** High — any embedded YouTube video on the edge UI is blocked by CSP (reported as framing blocked).
   - **Files:** `edge/pit_crew_dashboard.py` (CSP header in `handle_index`).【F:edge/pit_crew_dashboard.py†L8394-L8417】
   - **Regression test gate:** `curl -I https://<edge-host>/` must show `frame-src https://www.youtube.com https://www.youtube-nocookie.com` in the CSP header (or equivalent allowlist).【F:edge/pit_crew_dashboard.py†L8394-L8417】

2) **Uplink service crash-loop risk (no StartLimit in systemd unit)**
   - **Owner:** edge
   - **Blast radius:** High — uplink failure prevents edge↔cloud telemetry flow and can keep the system in a restart loop.
   - **Files:** `edge/install.sh` (systemd unit template for `argus-uplink.service` lacks StartLimit/Restart policy tuning).【F:edge/install.sh†L1788-L1820】
   - **Regression test gate:** `systemctl show argus-uplink -p StartLimitIntervalSec -p StartLimitBurst` should return non-empty limits, and a controlled crash should not lead to endless restart spam (journalctl confirms limit hit).

3) **Edge↔Cloud online visibility (uplink status reporting)**
   - **Owner:** edge + cloud
   - **Blast radius:** High — if uplink status is not surfaced, operators cannot confirm data flow health; blocks core ops decisions.
   - **Files:** `edge/pit_crew_dashboard.py` (uplink service status and details), `edge/scripts/edge_health_check.sh` (uplink health checks).【F:edge/pit_crew_dashboard.py†L9755-L9788】【F:edge/scripts/edge_health_check.sh†L97-L107】
   - **Regression test gate:** edge health check must show “Uplink service running” and dashboard service status must show `UP` or `STARTING` without throwing JS errors.

## P1 — major UX breakages

1) **Edge map tiles blocked by CSP (`img-src` too narrow)**
   - **Owner:** edge
   - **Blast radius:** Medium — course map renders blank or broken tiles in the edge dashboard.
   - **Files:** `edge/pit_crew_dashboard.py` (Leaflet tile URLs + CSP header).【F:edge/pit_crew_dashboard.py†L3776-L3810】【F:edge/pit_crew_dashboard.py†L8405-L8414】
   - **Regression test gate:** load the edge dashboard map and verify tiles from `*.tile.opentopomap.org` and `*.basemaps.cartocdn.com` render without CSP console errors.

2) **Cloud YouTube camera previews (iframe + thumbnail domains)**
   - **Owner:** web + nginx
   - **Blast radius:** Medium — camera previews and fan watch embeds fail if CSP is tightened incorrectly.
   - **Files:** `web/nginx.conf` (CSP allowlist), `web/src/components/VehicleDetail/YouTubeEmbed.tsx`, `web/src/components/RaceCenter/WatchTab.tsx` (thumbnail + iframe usage).【F:web/nginx.conf†L136-L145】【F:web/src/components/VehicleDetail/YouTubeEmbed.tsx†L160-L180】【F:web/src/components/RaceCenter/WatchTab.tsx†L59-L66】
   - **Regression test gate:** `curl -I https://<cloud-host>/` must include `frame-src` for YouTube and `img-src` for `i.ytimg.com`; verify a YouTube embed renders and thumbnails load without CSP errors.

3) **Cloud map tiles (CARTO + OpenTopoMap)**
   - **Owner:** web + nginx
   - **Blast radius:** Medium — interactive maps lose tiles or stay blank.
   - **Files:** `web/nginx.conf` (CSP allowlist), `web/src/config/basemap.ts` (tile domains).【F:web/nginx.conf†L136-L145】【F:web/src/config/basemap.ts†L23-L60】
   - **Regression test gate:** map view loads with CARTO base + OpenTopoMap overlay tiles and no CSP errors in console.

## P2 — polish / defense-in-depth

1) **Reduce CSP reliance on `'unsafe-inline'` in cloud UI**
   - **Owner:** web + nginx
   - **Blast radius:** Low — security hardening only; no expected feature changes.
   - **Files:** `web/nginx.conf` (CSP), `web/src/index.html` or build template (if inline scripts/styles exist and need nonce/hashes).【F:web/nginx.conf†L136-L145】
   - **Regression test gate:** app loads without CSP violations after replacing `'unsafe-inline'` with nonces/hashes; `curl -I` confirms updated CSP.

2) **Document CSP expectations for edge + cloud**
   - **Owner:** docs
   - **Blast radius:** Low — operational clarity.
   - **Files:** `edge/pit_crew_dashboard.py`, `web/nginx.conf` (source of truth for CSP).【F:edge/pit_crew_dashboard.py†L8394-L8417】【F:web/nginx.conf†L118-L145】
   - **Regression test gate:** documentation checklist includes CSP header verification via `curl -I` for `/` and `/sw.js`.
