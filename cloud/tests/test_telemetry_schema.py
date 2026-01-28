"""
PR-2: Telemetry Schema Cohesion Tests

Tests to verify:
1. Schema field names are consistent across Edge/Cloud/Web
2. TelemetryPoint accepts both canonical and legacy field names (aliases)
3. Permission filter uses canonical field names
4. TelemetryData model uses canonical field names

Run with: pytest tests/test_telemetry_schema.py -v
"""
import pytest
from pydantic import ValidationError

# Import schemas
from app.schemas import PositionPoint, TelemetryPoint, TelemetryIngestRequest
from app.models import TelemetryData
from app.services.permission_filter import DEFAULT_PERMISSIONS


# ============================================
# Test: Canonical Field Names
# ============================================

class TestCanonicalFieldNames:
    """Verify canonical field names are used consistently."""

    # PR-2 SCHEMA: Canonical field names for telemetry
    CANONICAL_TELEMETRY_FIELDS = {
        "ts_ms",
        "rpm",
        "gear",
        "throttle_pct",
        "coolant_temp_c",
        "oil_pressure_psi",
        "fuel_pressure_psi",
        "speed_mph",
        # NOTE: Suspension fields removed - not currently in use
        "heart_rate",
        "heart_rate_zone",
    }

    # PR-2 SCHEMA: Canonical field names for positions
    CANONICAL_POSITION_FIELDS = {
        "ts_ms",
        "lat",
        "lon",
        "speed_mps",
        "heading_deg",
        "altitude_m",
        "hdop",
        "satellites",
    }

    def test_position_point_uses_canonical_fields(self):
        """PositionPoint schema should accept canonical field names."""
        data = {
            "ts_ms": 1706000000000,
            "lat": 34.1234,
            "lon": -116.5678,
            "speed_mps": 25.5,
            "heading_deg": 180.0,
            "altitude_m": 1000.0,
            "hdop": 1.2,
            "satellites": 12,
        }
        point = PositionPoint(**data)
        assert point.ts_ms == 1706000000000
        assert point.lat == 34.1234
        assert point.speed_mps == 25.5

    def test_telemetry_point_uses_canonical_fields(self):
        """TelemetryPoint schema should accept canonical field names."""
        data = {
            "ts_ms": 1706000000000,
            "rpm": 5500,
            "gear": 4,
            "throttle_pct": 75.0,
            "coolant_temp_c": 95.0,
            "oil_pressure_psi": 45.0,
            "fuel_pressure_psi": 55.0,
            "speed_mph": 65.0,
            "heart_rate": 140,
            "heart_rate_zone": 3,
        }
        point = TelemetryPoint(**data)
        assert point.rpm == 5500
        assert point.gear == 4
        assert point.throttle_pct == 75.0
        assert point.coolant_temp_c == 95.0
        assert point.oil_pressure_psi == 45.0
        assert point.heart_rate_zone == 3

    def test_permission_filter_uses_canonical_fields(self):
        """DEFAULT_PERMISSIONS should use canonical field names."""
        # Check for canonical names, not legacy
        assert "coolant_temp_c" in DEFAULT_PERMISSIONS
        assert "oil_pressure_psi" in DEFAULT_PERMISSIONS
        assert "fuel_pressure_psi" in DEFAULT_PERMISSIONS
        assert "throttle_pct" in DEFAULT_PERMISSIONS
        assert "speed_mph" in DEFAULT_PERMISSIONS

        # Should NOT have legacy names
        assert "coolant_f" not in DEFAULT_PERMISSIONS
        assert "coolant_temp" not in DEFAULT_PERMISSIONS
        assert "oil_pressure" not in DEFAULT_PERMISSIONS
        assert "fuel_pressure" not in DEFAULT_PERMISSIONS
        assert "throttle_position" not in DEFAULT_PERMISSIONS


# ============================================
# Test: Legacy Field Name Aliases (Backwards Compat)
# ============================================

class TestLegacyFieldAliases:
    """
    TelemetryPoint should accept legacy field names via validation_alias.
    This ensures backwards compatibility with v3 edge devices.
    """

    def test_accepts_legacy_throttle_position(self):
        """Legacy 'throttle_position' should map to 'throttle_pct'."""
        data = {
            "ts_ms": 1706000000000,
            "throttle_position": 75.0,  # Legacy name
        }
        point = TelemetryPoint(**data)
        assert point.throttle_pct == 75.0

    def test_accepts_legacy_coolant_f(self):
        """Legacy 'coolant_f' should map to 'coolant_temp_c'."""
        data = {
            "ts_ms": 1706000000000,
            "coolant_f": 95.0,  # Legacy name
        }
        point = TelemetryPoint(**data)
        assert point.coolant_temp_c == 95.0

    def test_accepts_legacy_oil_pressure(self):
        """Legacy 'oil_pressure' should map to 'oil_pressure_psi'."""
        data = {
            "ts_ms": 1706000000000,
            "oil_pressure": 45.0,  # Legacy name
        }
        point = TelemetryPoint(**data)
        assert point.oil_pressure_psi == 45.0

    def test_accepts_legacy_fuel_pressure(self):
        """Legacy 'fuel_pressure' should map to 'fuel_pressure_psi'."""
        data = {
            "ts_ms": 1706000000000,
            "fuel_pressure": 55.0,  # Legacy name
        }
        point = TelemetryPoint(**data)
        assert point.fuel_pressure_psi == 55.0


# ============================================
# Test: Ingest Request Validation
# ============================================

class TestIngestRequestValidation:
    """Test TelemetryIngestRequest validation."""

    def test_accepts_valid_request(self):
        """Valid request with positions and telemetry should be accepted."""
        data = {
            "positions": [
                {
                    "ts_ms": 1706000000000,
                    "lat": 34.1234,
                    "lon": -116.5678,
                    "speed_mps": 25.5,
                    "heading_deg": 180.0,
                }
            ],
            "telemetry": [
                {
                    "ts_ms": 1706000000000,
                    "rpm": 5500,
                    "coolant_temp_c": 95.0,
                }
            ],
        }
        request = TelemetryIngestRequest(**data)
        assert len(request.positions) == 1
        assert len(request.telemetry) == 1

    def test_requires_at_least_one_position(self):
        """Request must have at least one position."""
        data = {"positions": []}
        with pytest.raises(ValidationError):
            TelemetryIngestRequest(**data)

    def test_telemetry_is_optional(self):
        """Telemetry array is optional."""
        data = {
            "positions": [
                {
                    "ts_ms": 1706000000000,
                    "lat": 34.1234,
                    "lon": -116.5678,
                }
            ],
        }
        request = TelemetryIngestRequest(**data)
        assert request.telemetry is None


# ============================================
# Test: Position Point Validation
# ============================================

class TestPositionPointValidation:
    """Test PositionPoint field validation."""

    def test_lat_range(self):
        """Latitude must be -90 to 90."""
        with pytest.raises(ValidationError):
            PositionPoint(ts_ms=1706000000000, lat=91.0, lon=0.0)

    def test_lon_range(self):
        """Longitude must be -180 to 180."""
        with pytest.raises(ValidationError):
            PositionPoint(ts_ms=1706000000000, lat=0.0, lon=181.0)

    def test_heading_range(self):
        """Heading must be 0 to 360."""
        with pytest.raises(ValidationError):
            PositionPoint(ts_ms=1706000000000, lat=0.0, lon=0.0, heading_deg=361.0)

    def test_optional_fields(self):
        """Optional fields should default to None."""
        point = PositionPoint(ts_ms=1706000000000, lat=34.0, lon=-116.0)
        assert point.speed_mps is None
        assert point.heading_deg is None
        assert point.altitude_m is None
        assert point.hdop is None
        assert point.satellites is None


# ============================================
# Test: TelemetryData Model
# ============================================

class TestTelemetryDataModel:
    """Verify TelemetryData model uses canonical field names."""

    def test_model_has_canonical_fields(self):
        """TelemetryData should have canonical column names."""
        from sqlalchemy import inspect

        # Get column names from model
        mapper = inspect(TelemetryData)
        column_names = {c.key for c in mapper.columns}

        # Check for canonical names
        assert "coolant_temp_c" in column_names
        assert "oil_pressure_psi" in column_names
        assert "fuel_pressure_psi" in column_names
        assert "throttle_pct" in column_names
        assert "gear" in column_names
        assert "heart_rate_zone" in column_names

        # Should NOT have legacy names
        assert "coolant_f" not in column_names
        assert "oil_pressure" not in column_names
        assert "fuel_pressure" not in column_names
        assert "throttle_position" not in column_names
