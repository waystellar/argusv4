# Control Room Featured Broadcast Workflow (Web-Only)

This document defines a **web‑only workflow** for taking a **featured racer feed** (selected in Control Room) and pushing it into a **series organizer’s main livestream**, with optional overlays (leaderboard, CAN telemetry, race map) and a sponsor ticker/logo bar. It also includes **Claude‑ready implementation directions** that keep all operations in the **Control Room web UI** (no CLI, no manual service toggles).

---

## Goals (from product requirements)

1. **Featured feed output is only active when explicitly enabled.**
2. The **organizer’s program output** always reflects the **featured racer feed** without requiring Control Room users to press play in any embedded player.
3. **Mixing is required**: operators can overlay **leaderboard**, **CAN data**, and **race map** on the featured feed.
4. **Sponsor banner/ticker** is required: full‑width bottom bar with **uploadable logo** and **preloaded sponsor presets** toggled from the Control Room.
5. All operations must be done **through the Control Room web UI**.

---

## Workflow Overview (Operator View)

### 1) Pre‑event setup (one‑time per organizer/event)
- **Open Control Room → “Broadcast Output” panel.**
- Enter the organizer’s **Program Output destination** (YouTube RTMP ingest or other supported output) via a **web form**.
- Optionally, **preload sponsor assets** (logo images) and name them (e.g., “Toyo Tires”, “BFGoodrich”).
- Save the configuration (web UI persists the output target + sponsor library in cloud storage).

### 2) Live event operation (real‑time)
1. **Select a featured racer and camera** in the Control Room.
2. Toggle **“Program Output: ON”** (explicit activation).  
   - This starts the organizer’s output stream and instantly switches the program feed to the featured racer camera.
3. **Toggle overlays** as needed:
   - **Leaderboard** (semi‑transparent overlay)
   - **CAN telemetry** (selected metrics)
   - **Race map** (small overlay or picture‑in‑picture)
4. **Sponsor ticker**:
   - Click a **preloaded sponsor** to display its full‑width bottom banner.
   - Replace or disable the banner with a single click.

### 3) Switching featured feed during live broadcast
- Selecting a new featured racer/camera **automatically switches** the program output feed.
- No operator needs to interact with any embedded player; the program output switches on selection.
- Overlays and sponsor banner remain active unless toggled off.

### 4) Deactivation
- Toggle **“Program Output: OFF”** to stop the organizer’s stream.

---

## UI Requirements (Control Room)

### Broadcast Output Panel (new or expanded section)
**Fields**
- **Program Output Destination** (RTMP URL + Stream Key or unified URL)
- **Output Status** (Idle / Starting / Live / Error)
- **Controls**: “Start Program Output”, “Stop Program Output”

**Overlay Toggles**
- Leaderboard overlay (ON/OFF)
- CAN telemetry overlay (ON/OFF)
- Race map overlay (ON/OFF)

**Sponsor Banner Controls**
- Upload logo (PNG recommended)
- **Logo size guidance** shown in UI (e.g., 1920×140 or 1280×96) for a 16:9 stream
- Sponsor library list
- “Display sponsor” toggle/button per sponsor
- “Clear sponsor banner” button

### Camera Grid / Featured Feed
- The **featured camera** selection drives the **program output** automatically when the output is ON.
- Control Room should show **Program Output status** separate from any embedded preview.

---

## Data Flow (System View)

1. **Control Room selects featured feed** (existing featured camera selection flow).
2. **Program Output service** observes featured feed changes and **switches the input** of the organizer output pipeline.
3. **Overlay configuration** (leaderboard/CAN/map) is applied in the program output pipeline (not dependent on client playback).
4. **Sponsor banner** selection updates the overlay composition immediately.

**Key principle:** the **program output pipeline is server‑side**, so it does **not rely on any client player** being loaded or playing in the Control Room.

---

## Claude‑Ready Implementation Directions (Web‑Only)

> Use these prompts directly with Claude. They are structured to keep all actions inside the Control Room web UI and avoid manual CLI operations.

### Prompt 1 — Add “Program Output” controls to Control Room UI
```text
You are working in Argus (repo: /workspace/argusv4). Implement a “Program Output” panel in the Control Room UI.

Requirements:
1) Add a new panel to the Control Room page:
   - Input fields for Program Output destination (RTMP URL and Stream Key or combined URL)
   - Buttons: Start Program Output, Stop Program Output
   - Status indicator: Idle / Starting / Live / Error

2) Add overlay toggles in the same panel:
   - Leaderboard overlay (ON/OFF)
   - CAN telemetry overlay (ON/OFF)
   - Race map overlay (ON/OFF)

3) Add Sponsor Banner controls:
   - Upload sponsor logo (PNG recommended)
   - Sponsor list with “Display” button
   - “Clear sponsor banner” button
   - Show size guidance text (e.g., 1920x140 or 1280x96 for 16:9)

4) All of the above must be functional via the web UI (no CLI).

Testing:
- Add a minimal frontend test or component test that verifies the panel renders and buttons invoke the correct API calls.
- Provide a curl regression snippet to validate the new endpoints exist and respond with 200/201.
```

### Prompt 2 — Add/extend backend endpoints for program output + overlays
```text
You are working in Argus (repo: /workspace/argusv4). Add cloud endpoints to support the Program Output panel.

Requirements:
1) Create endpoints to:
   - Save program output destination for an event
   - Start/stop the program output
   - Update overlay settings (leaderboard/CAN/map)
   - Manage sponsor library (upload/list/select/clear)

2) Make these endpoints available to Control Room users (admin auth).
3) Persist configuration in the database or Redis (choose minimal, durable storage).
4) Return status fields that the UI can poll for (Idle/Starting/Live/Error).

Testing:
- Add a lightweight API test or python test to verify:
  - Output config save returns 200
  - Status transitions can be set
  - Sponsor list returns uploaded items
```

### Prompt 3 — Program Output pipeline: featured feed switching
```text
You are working in Argus (repo: /workspace/argusv4). Implement server-side program output switching based on featured feed.

Requirements:
1) When Program Output is ON, the output should always use the currently featured feed (featured racer + camera).
2) Switching featured feed should immediately retarget the program output input (no Control Room player interaction required).
3) If Program Output is OFF, no outgoing program stream should run.

Notes:
- Use the existing featured feed state stored in Redis or returned by /production/events/{event_id}/broadcast.
- The program output pipeline should run independently of Control Room player state.

Testing:
- Add a small integration test or mock that simulates switching featured feed and verifies the output target is updated.
```

### Prompt 4 — Sponsor banner overlay + preloaded sponsors
```text
You are working in Argus (repo: /workspace/argusv4). Implement sponsor banner overlay support with a selectable sponsor library.

Requirements:
1) Allow uploading sponsor logo assets via the Control Room UI.
2) Store sponsor assets per event with metadata (name, uploaded_at, file_url).
3) Provide a “Display” toggle per sponsor that sets the active banner.
4) Provide a “Clear sponsor banner” control.
5) Overlay must span the bottom of the program output in a news-style ticker bar.

Testing:
- Add a regression check that uploading a logo returns a valid URL and that selecting a sponsor updates the active banner.
```

### Prompt 5 — Overlay mixing toggles (leaderboard/CAN/map)
```text
You are working in Argus (repo: /workspace/argusv4). Implement overlay toggles for leaderboard, CAN telemetry, and race map in the program output pipeline.

Requirements:
1) Each overlay can be toggled ON/OFF from the Control Room UI.
2) Overlays must be applied server-side in the program output pipeline (not tied to client playback).
3) Overlays should be semi-transparent and not block the video feed.

Testing:
- Add a small API test that toggles each overlay and verifies the stored state.
```

---

## Acceptance Criteria

- **Program Output only runs when enabled**, and always uses the **featured racer feed**.
- **No manual play** is required in any Control Room embedded player for the program output to switch.
- Overlays (leaderboard/CAN/map) can be toggled on/off live.
- Sponsor library supports **upload + select + clear** and renders a **full‑width ticker bar**.
- All workflows are **driven from Control Room web UI**.

---

## Notes for Implementation Choices

- **Storage:** use S3 or existing object storage for sponsor logos; store metadata in DB.
- **Security:** restrict program output controls to admin/production roles.
- **Performance:** make overlay updates lightweight and cacheable where possible.

