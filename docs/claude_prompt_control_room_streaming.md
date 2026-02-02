# Claude prompt pack: Control Room + Pit Crew streaming issues

This document consolidates root-cause findings from the repo and provides Claude-ready prompts to fix the reported issues. It is intentionally scoped to the Cloud Control Room UI, fan/watch-live UI, and the Edge Pit Crew dashboard streaming logic.

## Root-cause notes (from repo)

### A) Control Room “On Air” YouTube player fails while fan view works
- **Control Room** embeds the YouTube iframe from `broadcastState.active_feeds`, selecting the feed that matches the featured vehicle + camera. If that feed has no `youtube_url`, the Control Room shows “No Video Feed” or attempts to embed a missing/incorrect ID. (`web/src/pages/ControlRoom.tsx` uses `broadcastState.active_feeds` → `featuredFeed?.youtube_url` for the iframe.)
- **Broadcast state** `/production/events/{event_id}/broadcast` only returns **VideoFeed** records that are `permission_level == "public"`. It does **not** use edge heartbeats. If teams haven’t configured VideoFeed records, `active_feeds` is empty, even if a stream is live. (`cloud/app/routes/production.py` `get_broadcast_state` only queries `VideoFeed` and returns those as `active_feeds`.)
- **Fan view** uses `/production/events/{event_id}/vehicles/{vehicle_id}/stream-state` which **does** incorporate the edge heartbeat and streaming state, hence the fan view can show live streams while the Control Room cannot.

**Implication:** Control Room needs a fallback to edge heartbeat `youtube_url` or `camera` feeds (from `/production/events/{event_id}/cameras` or `/edge-status`) when a `VideoFeed` row is missing. Otherwise On Air embeds can fail even when streaming is actually live.

### B) Control Room camera grid shows “Offline” while edge shows cameras online
- The Control Room grid uses `/production/events/{event_id}/cameras` and displays camera status based on `cam.is_live`. (`web/src/pages/ControlRoom.tsx` sets “Live/Offline” from `cam.is_live`.)
- The `/cameras` endpoint sets `is_live=True` **only** when the edge heartbeat reports `streaming_status == "live"`, the streaming camera matches the camera slot, and **a YouTube URL is present**. (`cloud/app/routes/production.py` uses edge heartbeat fields to compute `is_live`.)
- Edge heartbeat **does** include camera device status (e.g., `online/offline`) in the `cameras` list, but that **is not exposed** in the camera grid response for display.

**Implication:** “Offline” in the grid currently means “not streaming live,” not “camera device offline.” To match your requested definition (“Online = heartbeat + device available”), the API/UI should surface device status separately from streaming status, and the grid should reflect that distinction.

### C) Pit Crew Dashboard “Start Stream” defaults to chase cam
- The pit crew UI has `streamingStatus = { status: 'idle', camera: 'chase' }` as its initial state. That value is used to **set the camera dropdown** in `pollStreamingStatus`, which causes the dropdown to jump to “chase” before you press Start. (`edge/pit_crew_dashboard.py` JS sets the select value from `streamingStatus.camera`.)
- The backend start handler falls back to `camera='chase'` if the request body is missing or invalid JSON. (`edge/pit_crew_dashboard.py` `handle_streaming_start`.)

**Implication:** UI state (not the backend) is overriding the user’s camera choice. Fixing the dropdown initialization / state sync removes the forced chase selection.

### D) “Switch stream” without stopping
- The edge dashboard already exposes `POST /api/streaming/switch-camera`, which calls `switch_camera()` and restarts the stream if necessary. (`edge/pit_crew_dashboard.py` `handle_streaming_switch_camera`.)
- The edge command handler also supports a `switch_camera` command (used by cloud control), so both Control Room and Pit Crew can support a “Switch Stream” action without stop/start.

### E) CSP report-only errors in the edge UI console
- The edge app **does** set a CSP header on the authenticated dashboard response and allows `cdn.jsdelivr.net` and `unpkg.com` scripts. (`edge/pit_crew_dashboard.py` `handle_index`.)
- The reported error shows a **report-only** CSP with `script-src-elem 'none'`, which is **not** defined by the edge app’s CSP.

**Implication:** report-only CSP is being injected upstream (proxy/extension/security tool) and is not coming from the edge app. The edge app’s CSP already allows the external scripts used in the dashboard.

---

## Prompt set #1 — Control Room: On Air embed + camera grid status

```text
You are working in Argus (repo: /workspace/argusv4). Focus on the Control Room UI and cloud production endpoints.

Problem:
1) Control Room “On Air” doesn’t show the YouTube stream even when it’s live (fan view works).
2) The camera grid labels all camera slots “Offline” even when edge reports cameras online.
3) I need a red dot over whichever camera in the control room is currently streaming to YouTube (per vehicle).

Root-cause notes (from repo):
- ControlRoom.tsx renders On Air from broadcastState.active_feeds; this is sourced from /production/events/{event_id}/broadcast, which only returns VideoFeed rows with permission_level == "public". If no VideoFeed exists, active_feeds is empty even if the edge is streaming. (cloud/app/routes/production.py get_broadcast_state + web/src/pages/ControlRoom.tsx)
- /production/events/{event_id}/cameras computes cam.is_live only when edge reports streaming_status == live AND the camera matches streaming_camera AND youtube_url is present. So “Offline” currently means “not streaming live,” not “camera device offline.” (cloud/app/routes/production.py)

Requested behavior:
- “Online” in the grid should mean edge heartbeat is present + camera device is available. Use streaming info separately for a live badge.
- On Air should fall back to edge heartbeat youtube_url when VideoFeed records are missing.
- Add a red dot overlay on the camera tile that is *currently streaming* (from edge status or featured camera state), even if the button is not selected.

Please implement:
A) Cloud: Update /production/events/{event_id}/broadcast or ControlRoom to use an edge-based fallback when active_feeds lacks the featured camera’s youtube_url. Options:
   - Add a new field to broadcast response (e.g., edge_youtube_url) from Redis edge status, OR
   - In ControlRoom, look up the live camera feed from /production/events/{event_id}/cameras and use its youtube_url/embed_url if broadcast active_feeds is empty.
B) Cloud: Update /production/events/{event_id}/cameras response to include device-level status (e.g., camera.status from edge heartbeat). Keep is_live for streaming state.
C) ControlRoom UI:
   - Use the new device status to show “Online/Offline” correctly.
   - Show “LIVE” (streaming) separately.
   - Add a red dot overlay on the camera tile whose camera_name matches edge.streaming_camera when streaming_status == live.

Testing:
- Add or update tests (if any) for the production camera list/broadcast state: a minimal pytest or python test that validates the response includes device_status + is_live and that youtube_url fallback works.
- Add a small frontend unit test (or TS test) that verifies the grid uses device status for “Online” and uses streaming camera to show the red dot.
- Provide a bash regression script that curls:
  - GET /api/v1/production/events/{event_id}/cameras
  - GET /api/v1/production/events/{event_id}/broadcast
  - GET /api/v1/production/events/{event_id}/edge-status
  and verifies status 200 + expected fields.
```

---

## Prompt set #2 — Edge Pit Crew: camera selection + switch-stream

```text
You are working in Argus (repo: /workspace/argusv4). Focus on the edge pit_crew_dashboard streaming UI and API handlers.

Problem:
- Clicking “Start Stream” on Main Cam defaults to Chase Cam even when the dropdown shows Main.
- Both Control Room and Pit Crew should be able to switch cameras *without stopping* the stream.

Root-cause notes (from repo):
- pit_crew_dashboard.js initializes streamingStatus.camera = 'chase' and uses it to overwrite the dropdown value in pollStreamingStatus. This makes the dropdown jump to Chase. (edge/pit_crew_dashboard.py)
- /api/streaming/switch-camera already exists and calls switch_camera(). It should be used instead of forcing stop/start. (edge/pit_crew_dashboard.py)

Please implement:
1) Fix the streaming dropdown behavior so it does NOT overwrite user selection when idle.
   - Only set the dropdown to streamingStatus.camera when streamingStatus.status is live/starting, or when the current selection is invalid.
   - Preserve the user’s selection when idle.
2) Add a “Switch Stream” button in the Pit Crew UI that calls /api/streaming/switch-camera with the selected camera. Keep Start/Stop for initial stream.
3) Ensure the switch command reports error states in the UI (same style as Start).
4) Optional: expose a single "switch" command from Control Room by using existing command flow if needed, or document that Control Room uses the production featured-camera state and edge already supports switch commands.

Testing:
- Add a small browser-less JS test or a minimal python test that asserts: given streamingStatus idle, the camera dropdown retains user-selected value; when streamingStatus live, dropdown reflects live camera.
- Add/extend the existing edge/verify_streaming.sh script to include POST /api/streaming/switch-camera and check response.
```

---

## Prompt set #3 — Watch Live: remove camera switching UI and highlight streaming camera

```text
You are working in Argus (repo: /workspace/argusv4). Focus on the fan "Watch Live" vehicle page (VehiclePage.tsx).

Problem:
- On Watch Live, users can click cameras to override the stream. Requirement: remove manual camera selection and only show/highlight the camera being streamed to YouTube.

Root-cause notes (from repo):
- VehiclePage currently supports manual camera override (`manualCameraOverride`) and renders a clickable camera switcher bar. (web/src/pages/VehiclePage.tsx)
- The stream state endpoint already provides the active camera (`active_camera`) and live status.

Please implement:
1) Remove manual camera override state and all click handlers for camera selection.
2) Only render a non-interactive camera list that highlights the active streaming camera (if live), and otherwise shows a neutral label (no clicking).
3) Ensure the selected video always follows stream state (active_camera) when live; if not live, use current fallback camera (chase or first).

Testing:
- Add a small unit test for the camera selection logic (active camera is used when stream is live, no manual override).
- Update snapshots if needed.
```

---

## Prompt set #4 — CSP report-only warnings (context only)

```text
The edge UI already sets CSP on the authenticated dashboard with a nonce and allows cdn.jsdelivr.net + unpkg.com. The report-only CSP errors with script-src-elem 'none' are NOT set by the edge app.

If you still see CSP report-only violations:
- Check for a reverse proxy, browser extension, or security appliance injecting Content-Security-Policy-Report-Only.
- If you decide to update CSP in the edge app, do not add 'unsafe-inline'; use existing nonces.
```

---

## File references (for Claude)
- `web/src/pages/ControlRoom.tsx` — camera grid, On Air embed, featured camera UI.
- `cloud/app/routes/production.py` — `/broadcast`, `/cameras`, edge-based camera feed aggregation.
- `edge/pit_crew_dashboard.py` — streaming UI JS, `/api/streaming/start`, `/api/streaming/switch-camera`, edge heartbeat payload.
- `web/src/pages/VehiclePage.tsx` — Watch Live camera selection logic.
