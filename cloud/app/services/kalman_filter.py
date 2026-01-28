"""
Kalman filter for GPS position smoothing.

Uses a simple 2D constant velocity model to smooth GPS positions
and reject outliers based on predicted vs measured position.

FIXED: Memory leak - now uses LRU cache with max size to prevent
unbounded growth of filter cache in long-running server.
"""
import math
from collections import OrderedDict
from dataclasses import dataclass
from threading import Lock
from typing import Optional

# FIXED: Configuration for LRU cache to prevent memory leak
_MAX_FILTERS = 500  # Maximum number of vehicle filters to keep in memory
_filters_lock = Lock()  # Thread safety for cache operations


@dataclass
class KalmanState:
    """State vector: [x, y, vx, vy] in meters from reference point."""
    x: float
    y: float
    vx: float
    vy: float
    # Covariance matrix diagonal (simplified)
    p_x: float
    p_y: float
    p_vx: float
    p_vy: float
    last_ts_ms: int


class GPSKalmanFilter:
    """
    Kalman filter for GPS tracking with constant velocity model.

    Operates in local tangent plane (meters) to avoid lat/lon nonlinearity.
    Reference point is set to first observation.
    """

    def __init__(
        self,
        process_noise: float = 1.0,  # m/s^2 acceleration variance
        measurement_noise: float = 5.0,  # meters GPS accuracy
        outlier_threshold: float = 50.0,  # meters max innovation
    ):
        self.process_noise = process_noise
        self.measurement_noise = measurement_noise
        self.outlier_threshold = outlier_threshold

        # Reference point for local coordinates
        self.ref_lat: Optional[float] = None
        self.ref_lon: Optional[float] = None

        # Current state
        self.state: Optional[KalmanState] = None

    def _latlon_to_local(self, lat: float, lon: float) -> tuple[float, float]:
        """Convert lat/lon to local tangent plane (x=east, y=north) in meters."""
        if self.ref_lat is None:
            return 0.0, 0.0

        # Approximate conversion (good for small areas)
        lat_rad = math.radians(self.ref_lat)
        meters_per_deg_lat = 111320  # ~111km per degree
        meters_per_deg_lon = 111320 * math.cos(lat_rad)

        x = (lon - self.ref_lon) * meters_per_deg_lon
        y = (lat - self.ref_lat) * meters_per_deg_lat

        return x, y

    def _local_to_latlon(self, x: float, y: float) -> tuple[float, float]:
        """Convert local coordinates back to lat/lon."""
        if self.ref_lat is None:
            return 0.0, 0.0

        lat_rad = math.radians(self.ref_lat)
        meters_per_deg_lat = 111320
        meters_per_deg_lon = 111320 * math.cos(lat_rad)

        lat = self.ref_lat + y / meters_per_deg_lat
        lon = self.ref_lon + x / meters_per_deg_lon

        return lat, lon

    def update(
        self,
        lat: float,
        lon: float,
        ts_ms: int,
        speed_mps: Optional[float] = None,
        heading_deg: Optional[float] = None,
    ) -> tuple[float, float, float, float, bool]:
        """
        Process a new GPS measurement.

        Returns:
            (smoothed_lat, smoothed_lon, smoothed_speed_mps, smoothed_heading_deg, is_outlier)
        """
        # Initialize reference point
        if self.ref_lat is None:
            self.ref_lat = lat
            self.ref_lon = lon

        # Convert to local coordinates
        z_x, z_y = self._latlon_to_local(lat, lon)

        # Initialize state on first observation
        if self.state is None:
            # Use provided speed/heading if available
            if speed_mps is not None and heading_deg is not None:
                vx = speed_mps * math.sin(math.radians(heading_deg))
                vy = speed_mps * math.cos(math.radians(heading_deg))
            else:
                vx, vy = 0.0, 0.0

            self.state = KalmanState(
                x=z_x, y=z_y, vx=vx, vy=vy,
                p_x=self.measurement_noise ** 2,
                p_y=self.measurement_noise ** 2,
                p_vx=10.0,  # High initial velocity uncertainty
                p_vy=10.0,
                last_ts_ms=ts_ms,
            )
            return lat, lon, speed_mps or 0.0, heading_deg or 0.0, False

        # Time delta
        dt = (ts_ms - self.state.last_ts_ms) / 1000.0
        if dt <= 0:
            # Invalid timestamp, skip
            return lat, lon, speed_mps or 0.0, heading_deg or 0.0, True

        # Limit dt to reasonable range (handle gaps)
        dt = min(dt, 10.0)

        # ===== PREDICT =====
        # State prediction: x' = x + vx*dt, y' = y + vy*dt
        pred_x = self.state.x + self.state.vx * dt
        pred_y = self.state.y + self.state.vy * dt
        pred_vx = self.state.vx
        pred_vy = self.state.vy

        # Covariance prediction (simplified diagonal)
        q = self.process_noise * dt ** 2
        pred_p_x = self.state.p_x + self.state.p_vx * dt ** 2 + q
        pred_p_y = self.state.p_y + self.state.p_vy * dt ** 2 + q
        pred_p_vx = self.state.p_vx + q
        pred_p_vy = self.state.p_vy + q

        # ===== INNOVATION =====
        innov_x = z_x - pred_x
        innov_y = z_y - pred_y
        innov_dist = math.sqrt(innov_x ** 2 + innov_y ** 2)

        # Outlier detection
        is_outlier = innov_dist > self.outlier_threshold
        if is_outlier:
            # Don't update state, return predicted position
            pred_lat, pred_lon = self._local_to_latlon(pred_x, pred_y)
            speed = math.sqrt(pred_vx ** 2 + pred_vy ** 2)
            heading = math.degrees(math.atan2(pred_vx, pred_vy)) % 360

            # Still update timestamp to prevent state drift
            self.state.last_ts_ms = ts_ms
            self.state.x = pred_x
            self.state.y = pred_y

            return pred_lat, pred_lon, speed, heading, True

        # ===== UPDATE =====
        r = self.measurement_noise ** 2

        # Kalman gains (simplified scalar)
        k_x = pred_p_x / (pred_p_x + r)
        k_y = pred_p_y / (pred_p_y + r)
        k_vx = pred_p_vx / (pred_p_vx + r) * 0.5  # Reduce velocity correction
        k_vy = pred_p_vy / (pred_p_vy + r) * 0.5

        # State update
        self.state.x = pred_x + k_x * innov_x
        self.state.y = pred_y + k_y * innov_y

        # Velocity update from position innovation
        self.state.vx = pred_vx + k_vx * (innov_x / dt) if dt > 0.01 else pred_vx
        self.state.vy = pred_vy + k_vy * (innov_y / dt) if dt > 0.01 else pred_vy

        # If we have direct speed/heading measurement, blend it in
        if speed_mps is not None and heading_deg is not None:
            meas_vx = speed_mps * math.sin(math.radians(heading_deg))
            meas_vy = speed_mps * math.cos(math.radians(heading_deg))
            # Blend 50/50 with computed velocity
            self.state.vx = 0.5 * self.state.vx + 0.5 * meas_vx
            self.state.vy = 0.5 * self.state.vy + 0.5 * meas_vy

        # Covariance update
        self.state.p_x = (1 - k_x) * pred_p_x
        self.state.p_y = (1 - k_y) * pred_p_y
        self.state.p_vx = (1 - k_vx) * pred_p_vx
        self.state.p_vy = (1 - k_vy) * pred_p_vy

        self.state.last_ts_ms = ts_ms

        # Convert back to lat/lon
        smooth_lat, smooth_lon = self._local_to_latlon(self.state.x, self.state.y)
        smooth_speed = math.sqrt(self.state.vx ** 2 + self.state.vy ** 2)
        smooth_heading = math.degrees(math.atan2(self.state.vx, self.state.vy)) % 360

        return smooth_lat, smooth_lon, smooth_speed, smooth_heading, False

    def reset(self):
        """Reset filter state."""
        self.ref_lat = None
        self.ref_lon = None
        self.state = None


# FIXED: LRU cache with maximum size to prevent memory leak
# Previously used unbounded dict that grew indefinitely
_filters: OrderedDict[str, GPSKalmanFilter] = OrderedDict()


def get_filter(vehicle_id: str) -> GPSKalmanFilter:
    """
    Get or create Kalman filter for a vehicle.

    FIXED: Now uses LRU eviction to prevent memory leak.
    Least recently used filters are evicted when cache exceeds _MAX_FILTERS.
    """
    with _filters_lock:
        if vehicle_id in _filters:
            # Move to end (most recently used)
            _filters.move_to_end(vehicle_id)
            return _filters[vehicle_id]

        # Create new filter
        kf = GPSKalmanFilter()
        _filters[vehicle_id] = kf

        # FIXED: Evict oldest entries if over limit (LRU eviction)
        while len(_filters) > _MAX_FILTERS:
            _filters.popitem(last=False)  # Remove oldest (first) item

        return kf


def smooth_position(
    vehicle_id: str,
    lat: float,
    lon: float,
    ts_ms: int,
    speed_mps: Optional[float] = None,
    heading_deg: Optional[float] = None,
) -> tuple[float, float, float, float, bool]:
    """
    Smooth a GPS position using per-vehicle Kalman filter.

    Returns:
        (smoothed_lat, smoothed_lon, smoothed_speed, smoothed_heading, is_outlier)
    """
    kf = get_filter(vehicle_id)
    return kf.update(lat, lon, ts_ms, speed_mps, heading_deg)


def reset_filter(vehicle_id: str):
    """Reset filter for a vehicle (e.g., at race start)."""
    with _filters_lock:
        if vehicle_id in _filters:
            del _filters[vehicle_id]


def get_filter_cache_stats() -> dict:
    """Get statistics about the filter cache (for monitoring)."""
    with _filters_lock:
        return {
            "current_size": len(_filters),
            "max_size": _MAX_FILTERS,
            "vehicle_ids": list(_filters.keys())[-10:],  # Last 10 only
        }
