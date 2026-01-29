#!/usr/bin/env python3
"""
Argus Video Director Service - Remote Camera Switching

Connects to the cloud SSE stream and listens for camera switch commands
from the production director. When a switch command is received, this
service restarts the local FFmpeg streaming process with the new camera.

Architecture:
    [Cloud Production API]
           |
           | SSE: camera_switch events
           v
    [Video Director Service]
           |
           | Process management
           v
    [FFmpeg Process] --> [YouTube RTMP]
           ^
           |
    [/dev/video0..N] (cameras)

Camera Mapping:
    - "chase" -> /dev/video0 (rear-facing chase camera)
    - "pov"   -> /dev/video2 (driver POV camera)
    - "roof"  -> /dev/video4 (roof-mounted 360 camera)
    - "front" -> /dev/video6 (front bumper camera)

Usage:
    python video_director.py --event-id evt_xxx

Environment Variables:
    ARGUS_CLOUD_URL     - Cloud API base URL
    ARGUS_TRUCK_TOKEN   - Authentication token
    ARGUS_YOUTUBE_KEY   - YouTube stream key
    ARGUS_EVENT_ID      - Event ID to subscribe to
    ARGUS_LOG_LEVEL     - Logging level
"""
import argparse
import asyncio
import json
import logging
import os
import random
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Optional, Dict

import httpx

# ============ Configuration ============

@dataclass
class VideoConfig:
    """Video director configuration."""
    cloud_url: str = ""
    event_id: str = ""
    truck_token: str = ""
    youtube_key: str = ""

    # Camera device mapping
    cameras: Dict[str, str] = None

    # FFmpeg settings
    video_size: str = "1920x1080"
    framerate: int = 30
    bitrate: str = "4500k"
    preset: str = "ultrafast"
    tune: str = "zerolatency"

    # Reconnect settings
    sse_reconnect_delay: float = 5.0
    sse_max_reconnect_delay: float = 60.0

    def __post_init__(self):
        if self.cameras is None:
            # CAM-CONTRACT-1B: Canonical 4-camera slot mapping using udev symlinks
            # Slots: main (primary broadcast), cockpit (driver POV), chase (following), suspension (suspension cam)
            self.cameras = {
                "main": "/dev/argus_cam_main",
                "cockpit": "/dev/argus_cam_cockpit",
                "chase": "/dev/argus_cam_chase",
                "suspension": "/dev/argus_cam_suspension",
            }
            # Fallback to standard video devices (for dev/testing)
            self.cameras_fallback = {
                "main": "/dev/video0",
                "cockpit": "/dev/video2",
                "chase": "/dev/video4",
                "suspension": "/dev/video6",
            }
            # CAM-CONTRACT-1B: Backward compatibility aliases for legacy devices
            self.camera_aliases = {
                "pov": "cockpit",
                "roof": "chase",
                "front": "suspension",
                "rear": "suspension",
            }

    @classmethod
    def from_env(cls) -> "VideoConfig":
        """Load configuration from environment."""
        return cls(
            cloud_url=os.environ.get("ARGUS_CLOUD_URL", ""),
            event_id=os.environ.get("ARGUS_EVENT_ID", ""),
            truck_token=os.environ.get("ARGUS_TRUCK_TOKEN", ""),
            youtube_key=os.environ.get("ARGUS_YOUTUBE_KEY", ""),
        )


logging.basicConfig(
    level=os.environ.get("ARGUS_LOG_LEVEL", "INFO"),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("video_director")


# ============ EDGE-6: Stream States ============

STREAM_STATE_IDLE = "idle"           # No stream configured or requested
STREAM_STATE_STARTING = "starting"   # FFmpeg process is being launched
STREAM_STATE_ACTIVE = "active"       # FFmpeg running, stream healthy
STREAM_STATE_ERROR = "error"         # FFmpeg exited unexpectedly
STREAM_STATE_RETRYING = "retrying"   # Waiting for backoff before next attempt
STREAM_STATE_PAUSED = "paused"       # Gave up after too many failures (manual restart needed)

# Status file for dashboard and scripts to read
STREAM_STATUS_FILE = "/opt/argus/state/stream_status.json"

# EDGE-PROG-3: Program state file (shared with pit_crew_dashboard.py)
PROGRAM_STATE_FILE = "/opt/argus/state/program_state.json"


def _update_program_state_file(camera: str = None, streaming: bool = None, error: str = None):
    """
    EDGE-PROG-3: Update the program state file to sync with pit_crew_dashboard.
    Only updates the fields that are provided (non-None).
    """
    try:
        # Read existing state
        state = {
            'active_camera': 'chase',
            'streaming': False,
            'stream_destination': None,
            'last_switch_at': None,
            'last_stream_start_at': None,
            'last_error': None,
            'updated_at': None,
        }
        if os.path.exists(PROGRAM_STATE_FILE):
            with open(PROGRAM_STATE_FILE, 'r') as f:
                state.update(json.load(f))

        # Update provided fields
        now_ms = int(time.time() * 1000)
        if camera is not None:
            state['active_camera'] = camera
            state['last_switch_at'] = now_ms
        if streaming is not None:
            state['streaming'] = streaming
            if streaming:
                state['last_stream_start_at'] = now_ms
        if error is not None:
            state['last_error'] = error
        state['updated_at'] = now_ms

        # Write back
        os.makedirs(os.path.dirname(PROGRAM_STATE_FILE), exist_ok=True)
        with open(PROGRAM_STATE_FILE, 'w') as f:
            json.dump(state, f, indent=2)
        logger.debug(f"Updated program state: camera={camera}, streaming={streaming}")
    except Exception as e:
        logger.warning(f"Failed to update program state file: {e}")


# ============ FFmpeg Process Manager ============

class FFmpegManager:
    """
    Manages the FFmpeg streaming process.
    EDGE-6: Full supervisor pattern with state machine, exponential backoff
    with ceiling and jitter, auth failure detection, single-instance enforcement,
    and status file output.
    """

    # Backoff settings
    BACKOFF_BASE_S = 5.0
    BACKOFF_MAX_S = 120.0  # 2-minute ceiling
    BACKOFF_JITTER_S = 3.0
    MAX_CONSECUTIVE_FAILURES = 10  # Enter "paused" after this many failures
    AUTH_FAILURE_THRESHOLD = 3     # Enter "paused" after this many auth failures

    def __init__(self, config: VideoConfig):
        self.config = config
        self._process: Optional[subprocess.Popen] = None
        self._current_camera: Optional[str] = None
        # EDGE-6: Supervisor state
        self._state: str = STREAM_STATE_IDLE
        self._restart_count: int = 0
        self._auth_failure_count: int = 0
        self._last_error: str = ""
        self._last_error_time: float = 0.0
        self._next_retry_time: float = 0.0
        self._backoff_delay: float = self.BACKOFF_BASE_S
        self._stream_start_time: float = 0.0
        self._total_restarts: int = 0
        self._running: bool = True

    def _get_current_profile_name(self) -> str:
        """STREAM-1: Read currently persisted profile name."""
        try:
            from stream_profiles import load_profile_state
            return load_profile_state()["profile"]
        except Exception:
            return "1080p30"

    def _get_camera_device(self, camera_name: str) -> Optional[str]:
        """Get the device path for a camera name."""
        # Try udev symlink first
        device = self.config.cameras.get(camera_name)
        if device and os.path.exists(device):
            return device

        # Try fallback
        device = self.config.cameras_fallback.get(camera_name)
        if device and os.path.exists(device):
            logger.warning(f"Using fallback device for {camera_name}: {device}")
            return device

        logger.error(f"No device found for camera: {camera_name}")
        return None

    def _build_ffmpeg_command(self, camera_device: str) -> list:
        """Build the FFmpeg command line.

        STREAM-1: Uses shared stream_profiles module for preset-driven
        encoding.  Camera input is always captured at native resolution;
        downscaling happens in the FFmpeg output chain via the scale filter.
        """
        from stream_profiles import build_ffmpeg_cmd, load_profile_state, get_profile

        state = load_profile_state()
        profile = get_profile(state["profile"])
        return build_ffmpeg_cmd(
            camera_device,
            self.config.youtube_key,
            profile,
            input_size=self.config.video_size,
            input_framerate=self.config.framerate,
        )

    def _set_state(self, new_state: str, error: str = ""):
        """EDGE-6: Transition state and write status file."""
        old_state = self._state
        self._state = new_state
        if error:
            self._last_error = error
            self._last_error_time = time.time()
        if old_state != new_state:
            logger.info(f"Stream state: {old_state} -> {new_state}" +
                        (f" ({error})" if error else ""))
        self._write_status_file()

        # EDGE-PROG-3: Sync program state with stream state transitions
        is_streaming = new_state == STREAM_STATE_ACTIVE
        _update_program_state_file(
            camera=self._current_camera,
            streaming=is_streaming,
            error=error if error else None
        )

    def _write_status_file(self):
        """EDGE-6: Write stream status JSON for dashboard/scripts."""
        status = {
            "state": self._state,
            "camera": self._current_camera,
            "pid": self._process.pid if self._process and self.is_running else None,
            "restart_count": self._restart_count,
            "total_restarts": self._total_restarts,
            "auth_failure_count": self._auth_failure_count,
            "last_error": self._last_error,
            "last_error_time": self._last_error_time,
            "next_retry_time": self._next_retry_time if self._state == STREAM_STATE_RETRYING else None,
            "backoff_delay_s": round(self._backoff_delay, 1),
            "stream_start_time": self._stream_start_time if self._state == STREAM_STATE_ACTIVE else None,
            "youtube_key_set": bool(self.config.youtube_key),
            "stream_profile": self._get_current_profile_name(),
            "updated_at": time.time(),
        }
        try:
            os.makedirs(os.path.dirname(STREAM_STATUS_FILE), exist_ok=True)
            with open(STREAM_STATUS_FILE, "w") as f:
                json.dump(status, f, indent=2)
        except OSError as e:
            logger.debug(f"Could not write stream status file: {e}")

    def _classify_failure(self, exit_code: int, stderr_text: str) -> str:
        """EDGE-6: Classify ffmpeg failure type from exit code and stderr."""
        stderr_lower = stderr_text.lower()

        # Auth failures (bad stream key)
        if any(s in stderr_lower for s in [
            "unauthorized", "403", "authentication",
            "connection refused", "stream key",
            "publish denied", "netstream.publish.badname",
        ]):
            return "auth"

        # Network failures (transient)
        if any(s in stderr_lower for s in [
            "connection timed out", "broken pipe", "network unreachable",
            "connection reset", "i/o error", "name or service not known",
        ]):
            return "network"

        # Camera/device failures
        if any(s in stderr_lower for s in [
            "no such file", "device or resource busy", "v4l2",
            "permission denied", "no space left",
        ]):
            return "device"

        # Generic crash
        return "crash"

    async def start(self, camera_name: str) -> bool:
        """Start streaming from a specific camera."""
        # EDGE-6: Single-instance enforcement — stop any existing process
        await self.stop()

        self._set_state(STREAM_STATE_STARTING)

        device = self._get_camera_device(camera_name)
        if not device:
            self._set_state(STREAM_STATE_ERROR, f"camera '{camera_name}' not found")
            return False

        if not self.config.youtube_key:
            self._set_state(STREAM_STATE_PAUSED, "ARGUS_YOUTUBE_KEY not set")
            return False

        cmd = self._build_ffmpeg_command(device)
        logger.info(f"Starting FFmpeg for camera '{camera_name}' from {device}")

        try:
            # EDGE-6: Check for stale ffmpeg processes before launching
            self._kill_stale_ffmpeg()

            self._process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL,
            )
            self._current_camera = camera_name
            self._stream_start_time = time.time()
            self._set_state(STREAM_STATE_ACTIVE)

            logger.info(f"FFmpeg started (PID: {self._process.pid})")
            return True

        except FileNotFoundError:
            self._set_state(STREAM_STATE_PAUSED, "ffmpeg not installed")
            return False
        except Exception as e:
            self._set_state(STREAM_STATE_ERROR, str(e))
            return False

    def _kill_stale_ffmpeg(self):
        """EDGE-6: Kill any orphaned ffmpeg processes streaming to YouTube."""
        try:
            result = subprocess.run(
                ["pgrep", "-f", "ffmpeg.*rtmp.*youtube"],
                capture_output=True, text=True, timeout=3,
            )
            if result.stdout.strip():
                pids = result.stdout.strip().split("\n")
                for pid in pids:
                    pid = pid.strip()
                    if pid and pid.isdigit():
                        logger.warning(f"Killing stale ffmpeg process PID={pid}")
                        try:
                            os.kill(int(pid), signal.SIGTERM)
                        except (ProcessLookupError, PermissionError):
                            pass
                # Brief wait for cleanup
                time.sleep(0.5)
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    async def stop(self):
        """Stop the current FFmpeg process."""
        if self._process:
            logger.info("Stopping FFmpeg...")
            try:
                self._process.terminate()
                try:
                    self._process.wait(timeout=5.0)
                except subprocess.TimeoutExpired:
                    logger.warning("FFmpeg didn't terminate, killing...")
                    self._process.kill()
                    self._process.wait(timeout=2.0)
            except Exception as e:
                logger.error(f"Error stopping FFmpeg: {e}")
            finally:
                self._process = None

    async def switch_camera(self, camera_name: str) -> bool:
        """Switch to a different camera."""
        if camera_name == self._current_camera and self.is_running:
            logger.info(f"Already streaming from camera '{camera_name}'")
            return True

        logger.info(f"Switching camera: {self._current_camera} -> {camera_name}")
        # EDGE-6: Reset backoff on intentional camera switch
        self._restart_count = 0
        self._auth_failure_count = 0
        self._backoff_delay = self.BACKOFF_BASE_S
        return await self.start(camera_name)

    def unpause(self):
        """EDGE-6: Manual unpause — reset failure counters and allow retry."""
        if self._state == STREAM_STATE_PAUSED:
            logger.info("Stream unpaused by manual override — resetting counters")
            self._restart_count = 0
            self._auth_failure_count = 0
            self._backoff_delay = self.BACKOFF_BASE_S
            self._set_state(STREAM_STATE_IDLE)

    @property
    def is_running(self) -> bool:
        """Check if FFmpeg is running."""
        if self._process is None:
            return False
        return self._process.poll() is None

    @property
    def current_camera(self) -> Optional[str]:
        """Get current camera name."""
        return self._current_camera

    @property
    def state(self) -> str:
        """EDGE-6: Current stream state."""
        return self._state

    def get_status(self) -> dict:
        """EDGE-6: Get full stream status for API."""
        return {
            "state": self._state,
            "camera": self._current_camera,
            "pid": self._process.pid if self._process and self.is_running else None,
            "restart_count": self._restart_count,
            "total_restarts": self._total_restarts,
            "auth_failure_count": self._auth_failure_count,
            "last_error": self._last_error,
            "last_error_time": self._last_error_time,
            "next_retry_time": self._next_retry_time if self._state == STREAM_STATE_RETRYING else None,
            "backoff_delay_s": round(self._backoff_delay, 1),
            "youtube_key_set": bool(self.config.youtube_key),
        }

    async def monitor(self):
        """EDGE-6: Monitor FFmpeg process with supervised restart.

        State machine:
          idle -> starting -> active -> (crash) -> error -> retrying -> starting -> ...
          After MAX_CONSECUTIVE_FAILURES or AUTH_FAILURE_THRESHOLD -> paused
          paused requires manual unpause() or camera switch to retry.
        """
        while self._running:
            await asyncio.sleep(5.0)

            # Only act if we had a running process that has exited
            if self._process is None or self.is_running:
                # If active, make sure state reflects it
                if self._process and self.is_running and self._state != STREAM_STATE_ACTIVE:
                    self._set_state(STREAM_STATE_ACTIVE)
                continue

            # Process exited — read error output
            exit_code = self._process.returncode
            stderr_text = ""
            if self._process.stderr:
                try:
                    raw = self._process.stderr.read()
                    if raw:
                        stderr_text = raw.decode(errors="replace")[-1000:]
                except Exception:
                    pass

            failure_type = self._classify_failure(exit_code, stderr_text)
            # Sanitize error for logging (never log stream key)
            safe_error = stderr_text.replace(self.config.youtube_key, "****") if self.config.youtube_key else stderr_text
            error_summary = f"exit={exit_code} type={failure_type}"
            if safe_error:
                # Take last 200 chars for summary
                error_summary += f" stderr=...{safe_error[-200:]}"

            logger.warning(f"FFmpeg exited: {error_summary}")
            self._set_state(STREAM_STATE_ERROR, error_summary)

            # Track failures
            self._restart_count += 1
            self._total_restarts += 1
            if failure_type == "auth":
                self._auth_failure_count += 1

            # EDGE-6: Check if we should pause
            if self._auth_failure_count >= self.AUTH_FAILURE_THRESHOLD:
                self._set_state(STREAM_STATE_PAUSED,
                                f"Auth failed {self._auth_failure_count} times — check YouTube key")
                logger.error("Stream PAUSED: repeated auth failures. Fix key and run stream_restart.sh")
                continue

            if self._restart_count >= self.MAX_CONSECUTIVE_FAILURES:
                self._set_state(STREAM_STATE_PAUSED,
                                f"Failed {self._restart_count} times consecutively")
                logger.error("Stream PAUSED: too many failures. Run stream_restart.sh to retry")
                continue

            if failure_type == "device":
                self._set_state(STREAM_STATE_PAUSED,
                                f"Camera device error — check hardware")
                logger.error("Stream PAUSED: camera device error")
                continue

            # EDGE-6: Calculate backoff with jitter
            jitter = random.uniform(0, self.BACKOFF_JITTER_S)
            delay = self._backoff_delay + jitter
            self._next_retry_time = time.time() + delay
            self._set_state(STREAM_STATE_RETRYING,
                            f"retry #{self._restart_count} in {delay:.1f}s")

            logger.info(f"Retrying in {delay:.1f}s (backoff={self._backoff_delay:.1f}s + jitter={jitter:.1f}s)")
            await asyncio.sleep(delay)

            # Increase backoff for next time (exponential with ceiling)
            self._backoff_delay = min(self._backoff_delay * 2, self.BACKOFF_MAX_S)

            # Attempt restart if we still have a camera and haven't been stopped
            camera = self._current_camera
            if camera and self._running and self._state == STREAM_STATE_RETRYING:
                logger.info(f"Restarting FFmpeg for camera '{camera}' (attempt {self._restart_count})")
                success = await self.start(camera)
                if success:
                    # Reset counters on successful start (will be confirmed if stays up)
                    self._restart_count = 0
                    self._auth_failure_count = 0
                    self._backoff_delay = self.BACKOFF_BASE_S


# ============ SSE Client ============

class SSEClient:
    """
    Server-Sent Events client for receiving camera switch commands.
    Handles reconnection with exponential backoff.
    """

    def __init__(self, config: VideoConfig, ffmpeg: FFmpegManager):
        self.config = config
        self.ffmpeg = ffmpeg
        self._running = False
        self._reconnect_delay = config.sse_reconnect_delay

    async def connect(self):
        """Connect to SSE stream and process events."""
        self._running = True

        url = f"{self.config.cloud_url.rstrip('/')}/api/v1/events/{self.config.event_id}/stream"
        headers = {
            "X-Truck-Token": self.config.truck_token,
            "Accept": "text/event-stream",
        }

        while self._running:
            try:
                logger.info(f"Connecting to SSE: {url}")

                async with httpx.AsyncClient(timeout=None) as client:
                    async with client.stream("GET", url, headers=headers) as response:
                        if response.status_code != 200:
                            logger.error(f"SSE connection failed: HTTP {response.status_code}")
                            await self._handle_reconnect()
                            continue

                        logger.info("SSE connected!")
                        self._reconnect_delay = self.config.sse_reconnect_delay

                        # Process events
                        await self._process_stream(response)

            except httpx.ConnectError:
                logger.warning("SSE connection failed (network unreachable)")
                await self._handle_reconnect()

            except httpx.ReadTimeout:
                logger.warning("SSE read timeout, reconnecting...")
                await self._handle_reconnect()

            except asyncio.CancelledError:
                break

            except Exception as e:
                logger.error(f"SSE error: {e}")
                await self._handle_reconnect()

    async def _process_stream(self, response):
        """Process SSE event stream."""
        event_type = None
        event_data = ""

        async for line in response.aiter_lines():
            if not self._running:
                break

            line = line.strip()

            if line.startswith("event:"):
                event_type = line[6:].strip()

            elif line.startswith("data:"):
                event_data = line[5:].strip()

            elif line == "":
                # End of event
                if event_type and event_data:
                    await self._handle_event(event_type, event_data)
                event_type = None
                event_data = ""

    async def _handle_event(self, event_type: str, data: str):
        """Handle a received SSE event."""
        try:
            payload = json.loads(data)
        except json.JSONDecodeError:
            logger.warning(f"Invalid JSON in SSE event: {data}")
            return

        logger.debug(f"SSE event: {event_type} -> {payload}")

        if event_type == "camera_switch":
            # Legacy event format for backwards compatibility
            camera = payload.get("camera_name") or payload.get("camera")
            if camera:
                logger.info(f"Received camera switch command: {camera}")
                success = await self.ffmpeg.switch_camera(camera)
                if success:
                    logger.info(f"Camera switched to: {camera}")
                else:
                    logger.error(f"Failed to switch to camera: {camera}")

        elif event_type == "edge_command":
            # PROD-CAM-2: Handle production director commands with ACK
            await self._handle_edge_command(payload)

        elif event_type == "featured_vehicle":
            # We might want to do something when our vehicle is featured
            vehicle_id = payload.get("vehicle_id")
            logger.info(f"Featured vehicle event: {vehicle_id}")

        elif event_type == "connected":
            logger.info("SSE stream connected and authenticated")

        elif event_type == "keepalive":
            logger.debug("SSE keepalive received")

    async def _handle_edge_command(self, payload: dict):
        """
        PROD-CAM-2: Handle edge_command events from production director.

        Expected payload format:
        {
            "command_id": "fc_xxxx",
            "command": "set_active_camera",
            "params": {"camera": "chase"},
            "vehicle_id": "veh_xxx",
            "sent_at": "2024-01-01T00:00:00"
        }
        """
        command_id = payload.get("command_id")
        command = payload.get("command")
        params = payload.get("params", {})
        vehicle_id = payload.get("vehicle_id")

        if not command_id or not command:
            logger.warning(f"Invalid edge_command payload: {payload}")
            return

        logger.info(f"Received edge_command: {command} (id={command_id})")

        success = False
        error_message = None

        if command == "set_active_camera":
            camera = params.get("camera")
            if not camera:
                error_message = "Missing camera parameter"
                logger.error(f"set_active_camera missing camera param: {params}")
            else:
                logger.info(f"Switching to camera: {camera}")
                success = await self.ffmpeg.switch_camera(camera)
                if success:
                    # EDGE-PROG-3: Update program state file for Cloud/Pit Crew sync
                    _update_program_state_file(camera=camera, streaming=True, error=None)
                else:
                    error_message = f"Failed to switch to camera '{camera}'"
                    _update_program_state_file(error=error_message)

        elif command == "set_stream_profile":
            # STREAM-3: Stream profile switching
            profile = params.get("profile")
            if profile:
                try:
                    from stream_profiles import save_profile_state
                    save_profile_state(profile)
                    # Restart stream with new profile if currently streaming
                    if self.ffmpeg.is_running and self.ffmpeg.current_camera:
                        success = await self.ffmpeg.switch_camera(self.ffmpeg.current_camera)
                    else:
                        success = True
                    logger.info(f"Stream profile set to: {profile}")
                except Exception as e:
                    error_message = f"Failed to set profile: {e}"
                    logger.error(error_message)
            else:
                error_message = "Missing profile parameter"

        else:
            logger.warning(f"Unknown edge command: {command}")
            error_message = f"Unknown command: {command}"

        # Send ACK back to cloud
        await self._send_command_response(command_id, success, error_message)

    async def _send_command_response(self, command_id: str, success: bool, error: str = None):
        """
        PROD-CAM-2: Send command acknowledgment back to cloud.

        POST /api/v1/events/{event_id}/edge/command-response
        """
        if not self.config.cloud_url or not self.config.event_id:
            logger.warning("Cannot send command response: cloud_url or event_id not configured")
            return

        url = f"{self.config.cloud_url.rstrip('/')}/api/v1/events/{self.config.event_id}/edge/command-response"
        headers = {
            "X-Truck-Token": self.config.truck_token,
            "Content-Type": "application/json",
        }
        payload = {
            "command_id": command_id,
            "status": "success" if success else "error",
            "message": error,
            "data": None,
        }

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.post(url, json=payload, headers=headers)
                if response.status_code in (200, 201, 202):
                    logger.info(f"Command response sent: {command_id} -> {'success' if success else 'failed'}")
                else:
                    logger.warning(f"Command response failed: HTTP {response.status_code}")
        except Exception as e:
            logger.error(f"Failed to send command response: {e}")

    async def _handle_reconnect(self):
        """Handle reconnection with exponential backoff."""
        logger.info(f"Reconnecting in {self._reconnect_delay:.1f} seconds...")
        await asyncio.sleep(self._reconnect_delay)

        # Increase delay for next time
        self._reconnect_delay = min(
            self._reconnect_delay * 2,
            self.config.sse_max_reconnect_delay
        )

    def stop(self):
        """Stop the SSE client."""
        self._running = False


# ============ Main Service ============

class VideoDirectorService:
    """
    Main video director service.
    """

    def __init__(self, config: VideoConfig):
        self.config = config
        self.ffmpeg = FFmpegManager(config)
        self.sse = SSEClient(config, self.ffmpeg)
        self._running = False

    async def start(self):
        """Start the video director service."""
        logger.info("=" * 60)
        logger.info("Argus Video Director Service Starting")
        logger.info("=" * 60)
        logger.info(f"Event ID: {self.config.event_id}")
        logger.info(f"Cloud URL: {self.config.cloud_url}")
        logger.info(f"YouTube Key: {'*' * 10 if self.config.youtube_key else 'NOT SET'}")
        logger.info("=" * 60)

        if not self.config.event_id:
            logger.error("ARGUS_EVENT_ID not set!")
            return

        if not self.config.cloud_url:
            logger.error("ARGUS_CLOUD_URL not set!")
            return

        self._running = True

        # Start with default camera (chase cam)
        if self.config.youtube_key:
            await self.ffmpeg.start("chase")

        # Start tasks
        tasks = [
            asyncio.create_task(self.sse.connect()),
            asyncio.create_task(self.ffmpeg.monitor()),
        ]

        try:
            await asyncio.gather(*tasks)
        except asyncio.CancelledError:
            pass
        finally:
            await self.stop()

    def get_streaming_status(self) -> dict:
        """EDGE-6: Get streaming status for dashboard API."""
        return self.ffmpeg.get_status()

    async def stop(self):
        """Stop the service."""
        logger.info("Stopping video director service...")
        self._running = False
        self.ffmpeg._running = False
        self.sse.stop()
        await self.ffmpeg.stop()
        self.ffmpeg._set_state(STREAM_STATE_IDLE)
        logger.info("Video director service stopped")


# ============ Main Entry Point ============

async def main():
    parser = argparse.ArgumentParser(description="Argus Video Director Service")
    parser.add_argument(
        "--event-id", "-e",
        default=os.environ.get("ARGUS_EVENT_ID", ""),
        help="Event ID to subscribe to",
    )
    parser.add_argument(
        "--camera", "-c",
        default="chase",
        help="Initial camera (default: chase)",
    )
    parser.add_argument(
        "--no-stream",
        action="store_true",
        help="Don't start FFmpeg (SSE only)",
    )
    args = parser.parse_args()

    config = VideoConfig.from_env()
    if args.event_id:
        config.event_id = args.event_id

    if args.no_stream:
        config.youtube_key = ""  # Disable streaming

    service = VideoDirectorService(config)

    # Handle signals
    loop = asyncio.get_event_loop()

    def signal_handler():
        logger.info("Received shutdown signal")
        asyncio.create_task(service.stop())

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, signal_handler)

    try:
        await service.start()
    except KeyboardInterrupt:
        pass
    finally:
        await service.stop()


if __name__ == "__main__":
    asyncio.run(main())
