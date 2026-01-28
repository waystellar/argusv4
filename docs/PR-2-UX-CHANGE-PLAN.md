# PR-2 UX: Live Data Plumbing Improvements - Change Plan

## Summary

Improve the real-time data pipeline reliability and user feedback for production environments with intermittent Starlink connectivity.

## Current State Analysis

The existing SSE implementation is **solid foundation** with:
- Redis pub/sub fan-out for scalability
- Session scope fix (generator creates own session)
- Position batching (100ms) on frontend to prevent race conditions
- Timer cleanup on unmount (memory leak fix)
- Timestamp comparison to prevent stale data overwriting newer data
- Basic connection status indicator ("Reconnecting...")
- DataFreshnessBadge with configurable thresholds

**Gaps Identified:**
1. No connection quality metrics (latency, message rate)
2. Per-vehicle staleness not tracked (all vehicles treated as single "connected" state)
3. No heartbeat monitoring from backend
4. No global system health indicator for operations/debugging
5. No message statistics for troubleshooting

---

## Files to Change

### Backend (Cloud)

| File | Change Type | Description |
|------|-------------|-------------|
| [stream.py](../cloud/app/routes/stream.py) | MODIFY | Add heartbeat with server timestamp, add message stats |
| [redis_client.py](../cloud/app/redis_client.py) | MODIFY | Add per-vehicle last-seen tracking |

### Frontend (Web)

| File | Change Type | Description |
|------|-------------|-------------|
| [useEventStream.ts](../web/src/hooks/useEventStream.ts) | MODIFY | Add connection quality metrics, heartbeat monitoring |
| [eventStore.ts](../web/src/stores/eventStore.ts) | MODIFY | Add per-vehicle staleness tracking, global health state |
| [ConnectionStatus.tsx](../web/src/components/common/ConnectionStatus.tsx) | MODIFY | Enhanced status with latency, message rate |
| [SystemHealthIndicator.tsx](../web/src/components/common/SystemHealthIndicator.tsx) | CREATE | New component for ops/debugging |

### Tests

| File | Change Type | Description |
|------|-------------|-------------|
| [test_sse_streaming.py](../cloud/tests/test_sse_streaming.py) | CREATE | SSE heartbeat and message format tests |
| [useEventStream.test.ts](../web/src/hooks/useEventStream.test.ts) | CREATE | Connection quality tracking tests |

---

## Implementation Details

### 1. Backend: Enhanced Heartbeat (stream.py)

**Change:** Modify keepalive to send heartbeat event with server timestamp instead of comment.

```python
# Current (comment-only keepalive):
yield {"comment": "keepalive"}

# New (heartbeat event with data):
yield {
    "event": "heartbeat",
    "data": json.dumps({
        "server_ts": datetime.utcnow().isoformat(),
        "ts_ms": int(datetime.utcnow().timestamp() * 1000),
    }),
}
```

**Rationale:** Allows frontend to measure round-trip latency and detect clock skew.

### 2. Backend: Per-Vehicle Last-Seen (redis_client.py)

**Change:** Track last position timestamp per vehicle for staleness queries.

```python
async def set_vehicle_last_seen(event_id: str, vehicle_id: str, ts_ms: int) -> None:
    """Track when vehicle last sent data."""
    r = await get_redis()
    key = f"lastseen:{event_id}"
    await r.hset(key, vehicle_id, str(ts_ms))
    await r.expire(key, 3600)

async def get_stale_vehicles(event_id: str, threshold_ms: int = 30000) -> list[str]:
    """Get vehicles that haven't sent data recently."""
    r = await get_redis()
    key = f"lastseen:{event_id}"
    data = await r.hgetall(key)
    now_ms = int(datetime.utcnow().timestamp() * 1000)
    return [vid for vid, ts in data.items() if now_ms - int(ts) > threshold_ms]
```

### 3. Frontend: Connection Quality Metrics (useEventStream.ts)

**Change:** Track latency, message rate, and connection health.

```typescript
interface ConnectionMetrics {
  latencyMs: number | null       // Based on heartbeat round-trip
  messagesPerSecond: number      // Rolling 10s average
  lastHeartbeatMs: number | null // When we last got heartbeat
  reconnectCount: number         // Total reconnects this session
}

// In hook:
const [metrics, setMetrics] = useState<ConnectionMetrics>({...})

// Handle heartbeat events:
es.addEventListener('heartbeat', (e) => {
  const data = JSON.parse(e.data)
  const serverTs = data.ts_ms
  const latency = Date.now() - serverTs
  setMetrics(m => ({ ...m, latencyMs: latency, lastHeartbeatMs: Date.now() }))
})
```

### 4. Frontend: Per-Vehicle Staleness (eventStore.ts)

**Change:** Track per-vehicle last update timestamp and compute staleness.

```typescript
interface EventState {
  // Existing...
  positions: Map<string, VehiclePosition>

  // New: per-vehicle health
  vehicleLastUpdate: Map<string, number>  // vehicle_id -> timestamp

  // New: computed staleness
  getStaleVehicles: (thresholdMs?: number) => string[]
  getVehicleFreshness: (vehicleId: string) => 'fresh' | 'stale' | 'offline'
}
```

### 5. Frontend: Enhanced ConnectionStatus (ConnectionStatus.tsx)

**Change:** Show latency and connection quality when expanded.

```tsx
interface ConnectionStatusProps {
  isConnected: boolean
  metrics?: ConnectionMetrics
  showDetails?: boolean
}

// Render latency badge when connected
{isConnected && metrics?.latencyMs !== null && (
  <span className={`text-xs ${metrics.latencyMs > 500 ? 'text-yellow-400' : 'text-green-400'}`}>
    {metrics.latencyMs}ms
  </span>
)}
```

### 6. Frontend: SystemHealthIndicator (NEW)

**Purpose:** Debugging/ops view showing system-wide health.

```tsx
// Shows:
// - Connection state and latency
// - Message rate (msgs/sec)
// - Vehicle count (active/stale/offline)
// - Last successful update timestamp
// - Reconnect count

// Only visible in debug mode or for organizers
```

---

## Risk Assessment

### Low Risk
- Adding heartbeat event type (backwards compatible)
- Adding connection metrics (additive only)
- Creating new SystemHealthIndicator component (opt-in)

### Medium Risk
- Per-vehicle staleness tracking could increase memory usage with many vehicles
  - **Mitigation:** Use Map with LRU eviction, limit to 500 vehicles

### No Breaking Changes
- All changes are additive
- Existing SSE event types unchanged
- No schema changes to API responses

---

## Testing Plan

### Unit Tests
1. **test_sse_streaming.py:**
   - Verify heartbeat event format
   - Verify heartbeat interval matches config
   - Verify per-vehicle last-seen tracking

2. **useEventStream.test.ts:**
   - Verify latency calculation from heartbeat
   - Verify message rate calculation
   - Verify reconnect count tracking

### Integration Tests
1. Connect to SSE, verify heartbeat received within 30s
2. Simulate vehicle going stale, verify frontend detects
3. Simulate reconnection, verify metrics reset properly

### Manual Verification Checklist

- [ ] Start SSE connection, verify "Connected" status shows
- [ ] Wait 30s, verify at least one heartbeat received (check console)
- [ ] Disconnect network, verify "Reconnecting..." shows
- [ ] Reconnect, verify automatic reconnection works
- [ ] With debug mode enabled, verify SystemHealthIndicator shows metrics
- [ ] Simulate vehicle not sending for 30s, verify stale indicator shows
- [ ] Check browser memory after 1 hour with 50 vehicles (should be stable)

---

## Rollback Plan

### If Backend Changes Cause Issues:
```bash
# Revert stream.py heartbeat change
git checkout HEAD~1 -- cloud/app/routes/stream.py

# Restart server
sudo systemctl restart argus-cloud
```

### If Frontend Changes Cause Issues:
```bash
# Revert frontend changes
git checkout HEAD~1 -- web/src/hooks/useEventStream.ts
git checkout HEAD~1 -- web/src/stores/eventStore.ts
git checkout HEAD~1 -- web/src/components/common/ConnectionStatus.tsx

# Rebuild
cd web && npm run build
```

### Feature Flag Option:
Add `VITE_ENABLE_CONNECTION_METRICS=false` to disable new metrics UI without code changes.

---

## Implementation Order

1. Backend: Add heartbeat event (stream.py)
2. Backend: Add per-vehicle last-seen (redis_client.py)
3. Frontend: Add connection metrics to useEventStream
4. Frontend: Add per-vehicle staleness to eventStore
5. Frontend: Update ConnectionStatus component
6. Frontend: Create SystemHealthIndicator (opt-in)
7. Write tests
8. Manual verification

---

## Estimated Scope

- **Backend:** ~50 lines of new/modified code
- **Frontend:** ~150 lines of new/modified code
- **Tests:** ~100 lines
- **Total:** ~300 lines

This is a focused improvement that enhances observability and user feedback without major architectural changes.
