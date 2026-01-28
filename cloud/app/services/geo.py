"""
Geographic utilities: haversine distance, checkpoint detection.
"""
from math import radians, cos, sin, asin, sqrt
from typing import Optional

from app.config import get_settings

settings = get_settings()


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate distance in meters between two lat/lon points.
    Uses the haversine formula for great-circle distance.
    """
    R = 6371000  # Earth radius in meters

    lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    c = 2 * asin(sqrt(a))

    return R * c


def is_valid_speed(
    new_lat: float,
    new_lon: float,
    new_ts_ms: int,
    old_lat: Optional[float],
    old_lon: Optional[float],
    old_ts_ms: Optional[int],
    max_speed_mps: float = None,
) -> bool:
    """
    Validate that movement between two points doesn't exceed max speed.
    Used for GPS outlier rejection.
    """
    if old_lat is None or old_lon is None or old_ts_ms is None:
        return True  # First point always valid

    if max_speed_mps is None:
        max_speed_mps = settings.max_speed_mps

    dt_seconds = (new_ts_ms - old_ts_ms) / 1000.0
    if dt_seconds <= 0:
        return False  # Invalid timestamp (backwards in time)

    distance = haversine_distance(new_lat, new_lon, old_lat, old_lon)
    implied_speed = distance / dt_seconds

    return implied_speed <= max_speed_mps


def format_time_delta(delta_ms: int) -> str:
    """Format time delta in human-readable format."""
    if delta_ms == 0:
        return "0.0s"

    seconds = delta_ms / 1000.0

    if seconds < 60:
        return f"+{seconds:.1f}s"
    elif seconds < 3600:
        minutes = int(seconds // 60)
        remaining_seconds = seconds % 60
        return f"+{minutes}:{remaining_seconds:04.1f}"
    else:
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        remaining_seconds = seconds % 60
        return f"+{hours}:{minutes:02d}:{remaining_seconds:04.1f}"
