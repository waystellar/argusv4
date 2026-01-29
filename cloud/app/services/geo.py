"""
Geographic utilities: haversine distance, checkpoint detection, course projection.
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


# ============ PROGRESS-1: Course Progress Computation ============

METERS_PER_MILE = 1609.344


def project_onto_course(
    lat: float,
    lon: float,
    coordinates: list[list[float]],
    cumulative_m: list[float],
) -> Optional[tuple[float, float]]:
    """
    Project a GPS point onto the nearest segment of a course polyline.

    Args:
        lat: Vehicle latitude
        lon: Vehicle longitude
        coordinates: Course polyline as list of [lon, lat] pairs (GeoJSON order)
        cumulative_m: Precomputed cumulative distances in meters at each polyline point

    Returns:
        (progress_m, off_course_m) tuple, or None if course has < 2 points.
        progress_m: Distance along course from start to the projection point.
        off_course_m: Perpendicular distance from vehicle to course.
    """
    if len(coordinates) < 2 or len(cumulative_m) < 2:
        return None

    best_progress_m = 0.0
    best_off_course_m = float("inf")

    for i in range(len(coordinates) - 1):
        # GeoJSON coordinates are [lon, lat]
        seg_start_lon, seg_start_lat = coordinates[i]
        seg_end_lon, seg_end_lat = coordinates[i + 1]

        # Compute segment length in meters
        seg_len_m = cumulative_m[i + 1] - cumulative_m[i]
        if seg_len_m <= 0:
            continue

        # Project point onto segment using flat-earth approximation (fine for short segments)
        # Convert to local cartesian (meters) relative to segment start
        cos_lat = cos(radians(seg_start_lat))
        dx_seg = (seg_end_lon - seg_start_lon) * cos_lat
        dy_seg = seg_end_lat - seg_start_lat
        dx_pt = (lon - seg_start_lon) * cos_lat
        dy_pt = lat - seg_start_lat

        # Parametric projection: t in [0, 1] is fraction along segment
        seg_sq = dx_seg * dx_seg + dy_seg * dy_seg
        if seg_sq < 1e-18:
            continue
        t = max(0.0, min(1.0, (dx_pt * dx_seg + dy_pt * dy_seg) / seg_sq))

        # Projected point in local coords
        proj_x = dx_seg * t
        proj_y = dy_seg * t

        # Distance from vehicle to projected point (degrees, approximate)
        diff_x = dx_pt - proj_x
        diff_y = dy_pt - proj_y

        # Convert back to meters using haversine for accuracy
        proj_lat = seg_start_lat + (seg_end_lat - seg_start_lat) * t
        proj_lon = seg_start_lon + (seg_end_lon - seg_start_lon) * t
        off_course_m = haversine_distance(lat, lon, proj_lat, proj_lon)

        if off_course_m < best_off_course_m:
            best_off_course_m = off_course_m
            best_progress_m = cumulative_m[i] + seg_len_m * t

    return (best_progress_m, best_off_course_m)


def compute_progress_miles(
    lat: float,
    lon: float,
    course_geojson: Optional[dict],
) -> Optional[tuple[float, float, float]]:
    """
    Compute course progress for a vehicle GPS position.

    Args:
        lat: Vehicle latitude
        lon: Vehicle longitude
        course_geojson: Event's course_geojson (GeoJSON FeatureCollection)

    Returns:
        (progress_miles, miles_remaining, course_length_miles) or None if no course.
    """
    if not course_geojson:
        return None

    features = course_geojson.get("features", [])
    if not features:
        return None

    feature = features[0]
    geometry = feature.get("geometry", {})
    properties = feature.get("properties", {})

    coordinates = geometry.get("coordinates", [])
    cumulative_m = properties.get("cumulative_m", [])
    total_distance_m = properties.get("distance_m", 0.0)

    if not coordinates or not cumulative_m or total_distance_m <= 0:
        return None

    result = project_onto_course(lat, lon, coordinates, cumulative_m)
    if result is None:
        return None

    progress_m, off_course_m = result
    course_length_miles = total_distance_m / METERS_PER_MILE
    progress_miles = progress_m / METERS_PER_MILE
    miles_remaining = course_length_miles - progress_miles

    return (progress_miles, miles_remaining, course_length_miles)
