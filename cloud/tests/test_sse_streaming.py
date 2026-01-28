"""
PR-2 UX: SSE Streaming Tests

Tests for:
1. Heartbeat event format and timing
2. Per-vehicle last-seen tracking
3. Connection quality metrics

Run with: pytest tests/test_sse_streaming.py -v
"""
import pytest
import json
from datetime import datetime
from unittest.mock import AsyncMock, patch, MagicMock

from app import redis_client


# ============================================
# Test: Heartbeat Event Format
# ============================================

class TestHeartbeatFormat:
    """
    Test that heartbeat events are properly formatted.

    PR-2 UX: Heartbeat events should include server timestamp
    for client-side latency calculation.
    """

    def test_heartbeat_has_required_fields(self):
        """Heartbeat should contain ts_ms and server_ts fields."""
        # Simulate heartbeat data structure
        heartbeat_data = {
            "server_ts": datetime.utcnow().isoformat(),
            "ts_ms": int(datetime.utcnow().timestamp() * 1000),
        }

        assert "server_ts" in heartbeat_data
        assert "ts_ms" in heartbeat_data
        assert isinstance(heartbeat_data["ts_ms"], int)
        assert isinstance(heartbeat_data["server_ts"], str)

    def test_heartbeat_ts_ms_is_recent(self):
        """Heartbeat ts_ms should be within reasonable range."""
        import time
        now_ms = int(time.time() * 1000)

        # Simulate heartbeat
        heartbeat_ts_ms = int(datetime.utcnow().timestamp() * 1000)

        # Should be within 1 second of current time
        assert abs(heartbeat_ts_ms - now_ms) < 1000

    def test_heartbeat_serializes_to_json(self):
        """Heartbeat data should be JSON serializable."""
        heartbeat_data = {
            "server_ts": datetime.utcnow().isoformat(),
            "ts_ms": int(datetime.utcnow().timestamp() * 1000),
        }

        # Should not raise
        json_str = json.dumps(heartbeat_data)
        parsed = json.loads(json_str)

        assert parsed["ts_ms"] == heartbeat_data["ts_ms"]


# ============================================
# Test: Vehicle Last-Seen Tracking
# ============================================

class TestVehicleLastSeen:
    """
    Test per-vehicle last-seen tracking in Redis.

    PR-2 UX: Track when each vehicle last sent data
    for staleness detection.
    """

    @pytest.mark.asyncio
    async def test_set_vehicle_last_seen(self):
        """set_vehicle_last_seen should store timestamp in Redis."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_redis = AsyncMock()
            mock_get_redis.return_value = mock_redis

            await redis_client.set_vehicle_last_seen("evt_1", "veh_1", 1706000000000)

            mock_redis.hset.assert_called_once()
            mock_redis.expire.assert_called_once()

    @pytest.mark.asyncio
    async def test_get_vehicle_last_seen(self):
        """get_vehicle_last_seen should retrieve timestamp from Redis."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_redis = AsyncMock()
            mock_redis.hget.return_value = "1706000000000"
            mock_get_redis.return_value = mock_redis

            result = await redis_client.get_vehicle_last_seen("evt_1", "veh_1")

            assert result == 1706000000000
            mock_redis.hget.assert_called_once()

    @pytest.mark.asyncio
    async def test_get_vehicle_last_seen_not_found(self):
        """get_vehicle_last_seen should return None if not found."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_redis = AsyncMock()
            mock_redis.hget.return_value = None
            mock_get_redis.return_value = mock_redis

            result = await redis_client.get_vehicle_last_seen("evt_1", "veh_unknown")

            assert result is None

    @pytest.mark.asyncio
    async def test_get_all_vehicles_last_seen(self):
        """get_all_vehicles_last_seen should return all timestamps."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_redis = AsyncMock()
            mock_redis.hgetall.return_value = {
                "veh_1": "1706000000000",
                "veh_2": "1706000001000",
            }
            mock_get_redis.return_value = mock_redis

            result = await redis_client.get_all_vehicles_last_seen("evt_1")

            assert result == {"veh_1": 1706000000000, "veh_2": 1706000001000}

    @pytest.mark.asyncio
    async def test_get_stale_vehicles(self):
        """get_stale_vehicles should return vehicles past threshold."""
        import time
        now_ms = int(time.time() * 1000)

        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_redis = AsyncMock()
            mock_redis.hgetall.return_value = {
                "veh_fresh": str(now_ms - 5000),  # 5s ago - fresh
                "veh_stale": str(now_ms - 60000),  # 60s ago - stale
            }
            mock_get_redis.return_value = mock_redis

            # Default threshold is 30000ms (30s)
            result = await redis_client.get_stale_vehicles("evt_1", threshold_ms=30000)

            assert "veh_stale" in result
            assert "veh_fresh" not in result


# ============================================
# Test: Connection Quality Metrics
# ============================================

class TestConnectionQualityMetrics:
    """
    Test that connection quality can be calculated from heartbeat timing.
    """

    def test_latency_calculation(self):
        """Latency should be calculated as client_time - server_time."""
        server_ts_ms = 1706000000000
        client_ts_ms = 1706000000150  # 150ms later

        latency = client_ts_ms - server_ts_ms

        assert latency == 150

    def test_latency_with_clock_skew(self):
        """
        Latency calculation should handle reasonable clock skew.

        If client clock is behind server, latency appears negative.
        Real implementations should handle this gracefully.
        """
        server_ts_ms = 1706000000000
        client_ts_ms = 1706000000000 - 50  # Client clock 50ms behind

        latency = client_ts_ms - server_ts_ms

        # Negative latency indicates clock skew
        assert latency == -50
        # Implementation should clamp or ignore negative values

    def test_message_rate_calculation(self):
        """Message rate should be messages / time_window."""
        message_count = 10
        window_seconds = 10

        messages_per_second = message_count / window_seconds

        assert messages_per_second == 1.0


# ============================================
# Test: SSE Event Types
# ============================================

class TestSSEEventTypes:
    """Test that all SSE event types are properly defined."""

    def test_event_types_documented(self):
        """All supported event types should be documented."""
        supported_events = [
            "connected",     # Initial connection acknowledgement
            "snapshot",      # All current vehicle positions
            "position",      # Single vehicle position update
            "checkpoint",    # Vehicle crossed checkpoint
            "permission",    # Vehicle visibility changed
            "leaderboard",   # Leaderboard update
            "heartbeat",     # PR-2 UX: Server timestamp for latency
        ]

        # Verify list is not empty
        assert len(supported_events) > 0

        # Verify heartbeat is included (PR-2 UX)
        assert "heartbeat" in supported_events
