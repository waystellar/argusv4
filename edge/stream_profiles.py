"""
Stream Profiles — Shared preset definitions and FFmpeg command builder.

STREAM-1: Provides 4 quality presets (1080p30, 720p30, 480p30, 360p30)
and a single build_ffmpeg_cmd() function used by both video_director.py
and pit_crew_dashboard.py to eliminate duplication.

The camera input is always captured at native resolution (e.g. 1920x1080
MJPEG from the DJI webcam) and downscaled in the FFmpeg output chain via
the `scale` filter.  This avoids UVC renegotiation on the source device.
"""
import json
import logging
import os
from dataclasses import dataclass, asdict
from typing import Dict, Optional

logger = logging.getLogger("stream_profiles")

# ============ Profile Definitions ============

# CAM-CONTRACT-1B: Canonical 4-camera slots (main, cockpit, chase, suspension)
# Backward compatibility: old names mapped via CAMERA_SLOT_ALIASES
VALID_CAMERAS = ("main", "cockpit", "chase", "suspension")

# CAM-CONTRACT-1B: Alias mapping for backward compatibility with legacy edge devices
CAMERA_SLOT_ALIASES = {
    # Old name -> New canonical name
    "pov": "cockpit",
    "roof": "chase",
    "front": "suspension",
    "rear": "suspension",  # CAM-CONTRACT-1B: rear is now suspension
    # Legacy 1-camera systems
    "cam0": "main",
    "camera": "main",
    "default": "main",
}

def normalize_camera_slot(slot_id: str) -> str:
    """CAM-CONTRACT-0: Normalize camera slot to canonical name."""
    if slot_id in VALID_CAMERAS:
        return slot_id
    return CAMERA_SLOT_ALIASES.get(slot_id, slot_id)

DEFAULT_PROFILE = "1080p30"

# State directory for persisted profile choice
STATE_DIR = os.environ.get("ARGUS_STATE_DIR", "/opt/argus/state")
PROFILE_STATE_FILE = os.path.join(STATE_DIR, "stream_profile.json")

# Dev fallback
PROFILE_STATE_FILE_DEV = os.path.join(os.path.dirname(__file__), "stream_profile_state.json")


@dataclass
class StreamProfile:
    """A single stream quality preset."""
    name: str            # Human-readable label
    scale_height: int    # FFmpeg scale=-2:<height>  (0 means no scaling)
    framerate: int       # Output FPS
    bitrate: str         # FFmpeg -b:v / -maxrate
    bufsize: str         # FFmpeg -bufsize
    audio_bitrate: str   # FFmpeg -b:a
    preset: str          # x264 preset
    tune: str            # x264 tune

    def to_dict(self) -> dict:
        return asdict(self)


STREAM_PROFILES: Dict[str, StreamProfile] = {
    "1080p30": StreamProfile(
        name="1080p (Full HD)",
        scale_height=0,       # No scaling — native 1080 passthrough
        framerate=30,
        bitrate="4500k",
        bufsize="9000k",
        audio_bitrate="128k",
        preset="ultrafast",
        tune="zerolatency",
    ),
    "720p30": StreamProfile(
        name="720p (HD)",
        scale_height=720,
        framerate=30,
        bitrate="2500k",
        bufsize="5000k",
        audio_bitrate="128k",
        preset="ultrafast",
        tune="zerolatency",
    ),
    "480p30": StreamProfile(
        name="480p (SD)",
        scale_height=480,
        framerate=30,
        bitrate="1200k",
        bufsize="2400k",
        audio_bitrate="96k",
        preset="ultrafast",
        tune="zerolatency",
    ),
    "360p30": StreamProfile(
        name="360p (Low)",
        scale_height=360,
        framerate=30,
        bitrate="800k",
        bufsize="1600k",
        audio_bitrate="64k",
        preset="ultrafast",
        tune="zerolatency",
    ),
}


def get_profile(profile_name: str) -> StreamProfile:
    """Return the requested profile, falling back to DEFAULT_PROFILE."""
    return STREAM_PROFILES.get(profile_name, STREAM_PROFILES[DEFAULT_PROFILE])


def list_profiles() -> list:
    """Return a list of available profile dicts for API responses."""
    return [
        {"id": pid, **p.to_dict()}
        for pid, p in STREAM_PROFILES.items()
    ]


# ============ FFmpeg Command Builder ============

def build_ffmpeg_cmd(
    camera_device: str,
    stream_key: str,
    profile: StreamProfile,
    *,
    input_format: str = "mjpeg",
    input_size: str = "1920x1080",
    input_framerate: int = 30,
) -> list:
    """
    Build an FFmpeg command list for streaming to YouTube RTMP.

    The camera always captures at `input_size` (native resolution).
    If the profile requires downscaling, a `scale` filter is applied
    in the output chain — no UVC renegotiation on the source device.

    Args:
        camera_device:  V4L2 device path (e.g. /dev/video0)
        stream_key:     YouTube RTMP stream key (never logged)
        profile:        StreamProfile preset to use
        input_format:   Camera capture format (default: mjpeg)
        input_size:     Camera capture resolution (default: 1920x1080)
        input_framerate: Camera capture FPS (default: 30)

    Returns:
        Complete FFmpeg argv list ready for subprocess.Popen.
    """
    rtmp_url = f"rtmp://a.rtmp.youtube.com/live2/{stream_key}"

    keyframe_interval = profile.framerate * 2  # 2-second GOP

    cmd = [
        "ffmpeg",
        "-y",  # Overwrite output
        "-f", "v4l2",
        "-input_format", input_format,
        "-framerate", str(input_framerate),
        "-video_size", input_size,
        "-i", camera_device,

        # Silent audio track (YouTube requires audio)
        "-f", "lavfi",
        "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
        "-c:a", "aac",
        "-b:a", profile.audio_bitrate,
        "-shortest",
    ]

    # Video filter chain: downscale if needed, then set output FPS
    vf_parts = []
    if profile.scale_height > 0:
        vf_parts.append(f"scale=-2:{profile.scale_height}")
    if profile.framerate != input_framerate:
        vf_parts.append(f"fps={profile.framerate}")

    if vf_parts:
        cmd.extend(["-vf", ",".join(vf_parts)])

    cmd.extend([
        # Video encoding
        "-c:v", "libx264",
        "-preset", profile.preset,
        "-tune", profile.tune,
        "-b:v", profile.bitrate,
        "-maxrate", profile.bitrate,
        "-bufsize", profile.bufsize,
        "-pix_fmt", "yuv420p",
        "-g", str(keyframe_interval),

        # Output
        "-f", "flv",
        rtmp_url,
    ])

    return cmd


# ============ Profile Persistence ============

def _get_state_path() -> str:
    """Return writable state file path (prod or dev fallback)."""
    prod_dir = os.path.dirname(PROFILE_STATE_FILE)
    if os.path.isdir(prod_dir):
        return PROFILE_STATE_FILE
    return PROFILE_STATE_FILE_DEV


def load_profile_state() -> dict:
    """
    Load persisted stream profile state from disk.

    Returns dict with keys:
        profile:   str  (profile id, e.g. "720p30")
        auto_mode: bool (stub for future adaptive logic)
    """
    path = _get_state_path()
    try:
        if os.path.exists(path):
            with open(path, "r") as f:
                data = json.load(f)
            # Validate
            profile_name = data.get("profile", DEFAULT_PROFILE)
            if profile_name not in STREAM_PROFILES:
                profile_name = DEFAULT_PROFILE
            return {
                "profile": profile_name,
                "auto_mode": bool(data.get("auto_mode", False)),
            }
    except (json.JSONDecodeError, OSError) as e:
        logger.warning(f"Could not load stream profile state: {e}")

    return {"profile": DEFAULT_PROFILE, "auto_mode": False}


def save_profile_state(profile_name: str, auto_mode: bool = False) -> bool:
    """Persist the selected profile and auto_mode flag. Returns True on success."""
    if profile_name not in STREAM_PROFILES:
        return False
    path = _get_state_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump({
                "profile": profile_name,
                "auto_mode": auto_mode,
                "updated_at": int(__import__("time").time() * 1000),
            }, f, indent=2)
        return True
    except OSError as e:
        logger.error(f"Failed to save stream profile state: {e}")
        return False
