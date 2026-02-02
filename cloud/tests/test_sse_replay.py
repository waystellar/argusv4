"""
Tests for SSE replay buffer (Gap 3).

Validates:
- incr_sse_seq returns incrementing IDs
- buffer_sse_event stores events in Redis list with LTRIM
- get_replay_events returns events after a given sequence ID
- get_replay_events returns empty list when after_seq is too recent
- Buffer caps at SSE_REPLAY_BUFFER_SIZE
"""
import pytest
import json
from unittest.mock import AsyncMock, patch

from app import redis_client


class TestSSEReplayBuffer:
    """Tests for SSE replay Redis helpers."""

    @pytest.mark.asyncio
    async def test_incr_sse_seq_returns_int(self):
        """incr_sse_seq should increment and return a sequence number."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_r = AsyncMock()
            mock_r.incr.return_value = 42
            mock_get_redis.return_value = mock_r

            seq = await redis_client.incr_sse_seq("event-1")
            assert seq == 42
            mock_r.incr.assert_called_once_with("sse_seq:event-1")
            mock_r.expire.assert_called_once_with("sse_seq:event-1", 7200)

    @pytest.mark.asyncio
    async def test_buffer_sse_event_stores_and_trims(self):
        """buffer_sse_event should rpush an entry and ltrim to buffer size."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_r = AsyncMock()
            mock_get_redis.return_value = mock_r

            await redis_client.buffer_sse_event(
                "event-1", 10, "checkpoint",
                {"vehicle_id": "v1", "checkpoint_id": 3},
            )

            # Verify rpush called with correct key and JSON entry
            assert mock_r.rpush.call_count == 1
            key_arg = mock_r.rpush.call_args[0][0]
            entry_arg = mock_r.rpush.call_args[0][1]
            assert key_arg == "sse_replay:event-1"
            entry = json.loads(entry_arg)
            assert entry["seq"] == 10
            assert entry["type"] == "checkpoint"
            assert entry["data"]["vehicle_id"] == "v1"

            # Verify ltrim to keep last N entries
            mock_r.ltrim.assert_called_once_with(
                "sse_replay:event-1",
                -redis_client.SSE_REPLAY_BUFFER_SIZE,
                -1,
            )
            mock_r.expire.assert_called_once_with("sse_replay:event-1", 7200)

    @pytest.mark.asyncio
    async def test_get_replay_events_filters_by_seq(self):
        """get_replay_events should return only events with seq > after_seq."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_r = AsyncMock()
            mock_get_redis.return_value = mock_r

            # Simulate 5 buffered events
            mock_r.lrange.return_value = [
                json.dumps({"seq": 1, "type": "position", "data": {"v": 1}}),
                json.dumps({"seq": 2, "type": "position", "data": {"v": 2}}),
                json.dumps({"seq": 3, "type": "checkpoint", "data": {"v": 3}}),
                json.dumps({"seq": 4, "type": "position", "data": {"v": 4}}),
                json.dumps({"seq": 5, "type": "permission", "data": {"v": 5}}),
            ]

            # Request events after seq 3
            events = await redis_client.get_replay_events("event-1", 3)
            assert len(events) == 2
            assert events[0]["seq"] == 4
            assert events[1]["seq"] == 5

    @pytest.mark.asyncio
    async def test_get_replay_events_empty_when_caught_up(self):
        """get_replay_events returns empty list when no events after after_seq."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_r = AsyncMock()
            mock_get_redis.return_value = mock_r
            mock_r.lrange.return_value = [
                json.dumps({"seq": 1, "type": "position", "data": {}}),
            ]

            events = await redis_client.get_replay_events("event-1", 99)
            assert events == []

    @pytest.mark.asyncio
    async def test_get_replay_events_empty_buffer(self):
        """get_replay_events returns empty list when buffer is empty."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_r = AsyncMock()
            mock_get_redis.return_value = mock_r
            mock_r.lrange.return_value = []

            events = await redis_client.get_replay_events("event-1", 0)
            assert events == []


class TestPublishEventWithReplay:
    """Tests that publish_event now buffers events for replay."""

    @pytest.mark.asyncio
    async def test_publish_event_assigns_seq_and_buffers(self):
        """publish_event should assign a seq ID and buffer non-heartbeat events."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_r = AsyncMock()
            mock_r.incr.return_value = 7
            mock_get_redis.return_value = mock_r

            await redis_client.publish_event(
                "event-1", "checkpoint", {"vehicle_id": "v1"}
            )

            # Should have published with seq in the message
            publish_call = mock_r.publish.call_args
            channel = publish_call[0][0]
            message = json.loads(publish_call[0][1])
            assert channel == "stream:event-1"
            assert message["seq"] == 7
            assert message["type"] == "checkpoint"

            # Should have buffered (rpush called)
            assert mock_r.rpush.call_count == 1

    @pytest.mark.asyncio
    async def test_publish_heartbeat_not_buffered(self):
        """Heartbeat events should NOT be buffered for replay."""
        with patch.object(redis_client, 'get_redis') as mock_get_redis:
            mock_r = AsyncMock()
            mock_r.incr.return_value = 8
            mock_get_redis.return_value = mock_r

            await redis_client.publish_event(
                "event-1", "heartbeat", {"ts_ms": 1234567890}
            )

            # Published but NOT buffered
            assert mock_r.publish.call_count == 1
            assert mock_r.rpush.call_count == 0
