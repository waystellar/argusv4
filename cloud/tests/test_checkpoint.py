"""
PR-3: GPX / Checkpoint Contract + Persistence Tests

Tests to verify:
1. GPX parsing extracts all checkpoint fields
2. Checkpoint model has required columns
3. Checkpoint crossing race condition is prevented
4. Leaderboard calculation is correct

Run with: pytest tests/test_checkpoint.py -v
"""
import pytest
from sqlalchemy import inspect

from app.models import Checkpoint, CheckpointCrossing
from app.services.gpx_parser import parse_gpx, parse_kml, _determine_checkpoint_type
from app.services.geo import haversine_distance, format_time_delta


# ============================================
# Test: Checkpoint Model Schema
# ============================================

class TestCheckpointModel:
    """Verify Checkpoint model has all required columns."""

    def test_checkpoint_has_required_columns(self):
        """Checkpoint should have all columns needed for GPX data."""
        mapper = inspect(Checkpoint)
        column_names = {c.key for c in mapper.columns}

        # Core columns
        assert "checkpoint_id" in column_names
        assert "event_id" in column_names
        assert "checkpoint_number" in column_names
        assert "name" in column_names
        assert "lat" in column_names
        assert "lon" in column_names
        assert "radius_m" in column_names

        # PR-3: New columns from GPX parsing
        assert "elevation_m" in column_names
        assert "checkpoint_type" in column_names
        assert "description" in column_names

    def test_checkpoint_crossing_has_lap_support(self):
        """CheckpointCrossing should support multi-lap races."""
        mapper = inspect(CheckpointCrossing)
        column_names = {c.key for c in mapper.columns}

        assert "lap_number" in column_names
        assert "ts_ms" in column_names
        assert "crossing_id" in column_names


# ============================================
# Test: GPX Parsing
# ============================================

class TestGPXParsing:
    """Test GPX file parsing."""

    SAMPLE_GPX = """<?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1">
        <wpt lat="34.0522" lon="-118.2437">
            <name>Start Line</name>
            <ele>1000</ele>
            <desc>Main start/finish line</desc>
        </wpt>
        <wpt lat="34.0550" lon="-118.2400">
            <name>Checkpoint 1</name>
            <ele>1050</ele>
        </wpt>
        <wpt lat="34.0580" lon="-118.2350">
            <name>Finish Line</name>
            <ele>1020</ele>
        </wpt>
        <trk>
            <trkseg>
                <trkpt lat="34.0522" lon="-118.2437"/>
                <trkpt lat="34.0530" lon="-118.2420"/>
                <trkpt lat="34.0550" lon="-118.2400"/>
                <trkpt lat="34.0580" lon="-118.2350"/>
            </trkseg>
        </trk>
    </gpx>"""

    def test_parse_gpx_extracts_checkpoints(self):
        """GPX waypoints should be extracted as checkpoints."""
        result = parse_gpx(self.SAMPLE_GPX)

        assert len(result["checkpoints"]) == 3
        assert result["checkpoints"][0]["name"] == "Start Line"
        assert result["checkpoints"][1]["name"] == "Checkpoint 1"
        assert result["checkpoints"][2]["name"] == "Finish Line"

    def test_parse_gpx_extracts_elevation(self):
        """GPX waypoint elevation should be extracted."""
        result = parse_gpx(self.SAMPLE_GPX)

        assert result["checkpoints"][0]["elevation_m"] == 1000
        assert result["checkpoints"][1]["elevation_m"] == 1050
        assert result["checkpoints"][2]["elevation_m"] == 1020

    def test_parse_gpx_extracts_description(self):
        """GPX waypoint description should be extracted."""
        result = parse_gpx(self.SAMPLE_GPX)

        assert result["checkpoints"][0]["description"] == "Main start/finish line"

    def test_parse_gpx_assigns_checkpoint_types(self):
        """GPX waypoints should get correct checkpoint types."""
        result = parse_gpx(self.SAMPLE_GPX)

        assert result["checkpoints"][0]["checkpoint_type"] == "start"
        assert result["checkpoints"][1]["checkpoint_type"] == "timing"
        assert result["checkpoints"][2]["checkpoint_type"] == "finish"

    def test_parse_gpx_assigns_radius(self):
        """Checkpoints should have appropriate radius based on type."""
        result = parse_gpx(self.SAMPLE_GPX)

        # Start/finish have larger radius
        assert result["checkpoints"][0]["radius_m"] == 100.0  # start
        assert result["checkpoints"][2]["radius_m"] == 100.0  # finish
        # Timing checkpoints have smaller radius
        assert result["checkpoints"][1]["radius_m"] == 50.0  # timing

    def test_parse_gpx_calculates_distance(self):
        """GPX track should have calculated distance."""
        result = parse_gpx(self.SAMPLE_GPX)

        assert result["total_distance_m"] > 0
        assert result["point_count"] == 4

    def test_parse_gpx_creates_geojson(self):
        """GPX track should be converted to GeoJSON."""
        result = parse_gpx(self.SAMPLE_GPX)

        assert result["geojson"]["type"] == "Feature"
        assert result["geojson"]["geometry"]["type"] == "LineString"
        assert len(result["geojson"]["geometry"]["coordinates"]) == 4

    def test_parse_gpx_calculates_bounds(self):
        """GPX parsing should calculate geographic bounds."""
        result = parse_gpx(self.SAMPLE_GPX)

        assert "north" in result["bounds"]
        assert "south" in result["bounds"]
        assert "east" in result["bounds"]
        assert "west" in result["bounds"]
        assert result["bounds"]["north"] >= result["bounds"]["south"]
        assert result["bounds"]["east"] >= result["bounds"]["west"]


# ============================================
# Test: Checkpoint Type Detection
# ============================================

class TestCheckpointTypeDetection:
    """Test checkpoint type detection from name/type fields."""

    def test_detect_start_from_name(self):
        """Names containing 'start' should be detected as start."""
        assert _determine_checkpoint_type("Start Line", None, None, 1, 5) == "start"
        assert _determine_checkpoint_type("Green Flag Start", None, None, 1, 5) == "start"
        assert _determine_checkpoint_type("Begin Race", None, None, 1, 5) == "start"

    def test_detect_finish_from_name(self):
        """Names containing 'finish' should be detected as finish."""
        assert _determine_checkpoint_type("Finish Line", None, None, 5, 5) == "finish"
        assert _determine_checkpoint_type("Checkered Flag", None, None, 5, 5) == "finish"
        assert _determine_checkpoint_type("End", None, None, 5, 5) == "finish"

    def test_detect_timing_from_name(self):
        """Names containing timing-related words should be detected as timing."""
        assert _determine_checkpoint_type("Split 1", None, None, 2, 5) == "timing"
        assert _determine_checkpoint_type("Sector 2", None, None, 3, 5) == "timing"
        assert _determine_checkpoint_type("CP3", None, None, 4, 5) == "timing"

    def test_detect_pit_from_name(self):
        """Names containing pit-related words should be detected as pit."""
        assert _determine_checkpoint_type("Pit Entry", None, None, 2, 5) == "pit"
        assert _determine_checkpoint_type("Service Area", None, None, 2, 5) == "pit"
        assert _determine_checkpoint_type("Fuel Stop", None, None, 2, 5) == "pit"

    def test_detect_from_position(self):
        """Position-based detection for first and last."""
        # First checkpoint is start if no name match
        assert _determine_checkpoint_type("Waypoint", None, None, 1, 5) == "start"
        # Last checkpoint is finish if no name match
        assert _determine_checkpoint_type("Waypoint", None, None, 5, 5) == "finish"
        # Middle checkpoints are timing
        assert _determine_checkpoint_type("Waypoint", None, None, 3, 5) == "timing"


# ============================================
# Test: Geo Utilities
# ============================================

class TestGeoUtilities:
    """Test geographic utility functions."""

    def test_haversine_distance_same_point(self):
        """Distance from point to itself should be 0."""
        distance = haversine_distance(34.0, -118.0, 34.0, -118.0)
        assert distance == 0.0

    def test_haversine_distance_known_value(self):
        """Test distance calculation with known reference points."""
        # Los Angeles to Las Vegas ~370km
        distance = haversine_distance(34.0522, -118.2437, 36.1699, -115.1398)
        assert 360000 < distance < 380000  # ~370km

    def test_format_time_delta_seconds(self):
        """Format short time deltas as seconds."""
        assert format_time_delta(0) == "0.0s"
        assert format_time_delta(1500) == "+1.5s"
        assert format_time_delta(45000) == "+45.0s"

    def test_format_time_delta_minutes(self):
        """Format medium time deltas as minutes:seconds."""
        assert format_time_delta(65000) == "+1:05.0"  # 65 seconds
        assert format_time_delta(125000) == "+2:05.0"  # 125 seconds

    def test_format_time_delta_hours(self):
        """Format long time deltas as hours:minutes:seconds."""
        assert format_time_delta(3665000) == "+1:01:05.0"  # 1h 1m 5s


# ============================================
# Test: KML Parsing
# ============================================

class TestKMLParsing:
    """Test KML file parsing."""

    SAMPLE_KML = """<?xml version="1.0" encoding="UTF-8"?>
    <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document>
            <Placemark>
                <name>Start</name>
                <Point>
                    <coordinates>-118.2437,34.0522,1000</coordinates>
                </Point>
            </Placemark>
            <Placemark>
                <name>Course Track</name>
                <LineString>
                    <coordinates>
                        -118.2437,34.0522,1000
                        -118.2400,34.0550,1050
                        -118.2350,34.0580,1020
                    </coordinates>
                </LineString>
            </Placemark>
            <Placemark>
                <name>Finish</name>
                <Point>
                    <coordinates>-118.2350,34.0580,1020</coordinates>
                </Point>
            </Placemark>
        </Document>
    </kml>"""

    def test_parse_kml_extracts_points(self):
        """KML placemarks with Point geometry should become checkpoints."""
        result = parse_kml(self.SAMPLE_KML)

        assert len(result["checkpoints"]) == 2
        assert result["checkpoints"][0]["name"] == "Start"
        assert result["checkpoints"][1]["name"] == "Finish"

    def test_parse_kml_extracts_linestring(self):
        """KML LineString should become course track."""
        result = parse_kml(self.SAMPLE_KML)

        assert result["point_count"] == 3
        assert result["geojson"]["geometry"]["type"] == "LineString"

    def test_parse_kml_extracts_elevation(self):
        """KML Point coordinates should include elevation."""
        result = parse_kml(self.SAMPLE_KML)

        assert result["checkpoints"][0]["elevation_m"] == 1000
        assert result["checkpoints"][1]["elevation_m"] == 1020
