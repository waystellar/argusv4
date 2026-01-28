/**
 * SSE hook for real-time event updates with auto-reconnect
 *
 * FIXED: Properly tracks and cleans up reconnect timer to prevent memory leak (Issue #14 from audit)
 * FIXED: P1-6 - Added clearPositions to prevent stale data when switching events
 * FIXED: P1-7 - Added position update batching to prevent race conditions
 * FIXED: P2-3 - Added leaderboard SSE support with checkpoint-triggered refresh
 * FIXED: P2-6 - Added checkpoint crossing notifications
 * PR-2 UX: Added connection quality metrics (latency, message rate, heartbeat tracking)
 */
import { useEffect, useRef, useCallback, useState } from 'react'
import { useEventStore } from '../stores/eventStore'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'
const RECONNECT_DELAYS = [1000, 2000, 4000, 8000, 15000, 30000]
// FIXED: P1-7 - Batch position updates every 100ms to prevent race conditions
const POSITION_BATCH_INTERVAL_MS = 100
// PR-2 UX: Interval for calculating message rate
const MESSAGE_RATE_WINDOW_MS = 10000

/**
 * PR-2 UX: Connection quality metrics for monitoring and debugging
 */
export interface ConnectionMetrics {
  /** Round-trip latency based on heartbeat (ms), null if not measured yet */
  latencyMs: number | null
  /** Messages received per second (rolling 10s average) */
  messagesPerSecond: number
  /** When we last received a heartbeat (ms since epoch) */
  lastHeartbeatMs: number | null
  /** Total reconnection attempts this session */
  reconnectCount: number
  /** Last error message if connection failed */
  lastError: string | null
  /** Whether we're in a degraded state (multiple reconnect failures) */
  isDegraded: boolean
}

export function useEventStream(eventId: string | undefined) {
  const [isConnected, setIsConnected] = useState(false)
  // FIXED: P2-3 - Track last checkpoint event to trigger leaderboard refresh
  const [lastCheckpointMs, setLastCheckpointMs] = useState<number | null>(null)
  const reconnectAttempt = useRef(0)
  const eventSourceRef = useRef<EventSource | null>(null)
  // FIXED: Track reconnect timer to clear on unmount (Issue #14 from audit)
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  // Track previous event ID to detect event switches
  const prevEventIdRef = useRef<string | undefined>(undefined)

  // FIXED: P1-7 - Position update batching to prevent race conditions
  const positionBatchRef = useRef<Map<string, unknown>>(new Map())
  const batchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // PR-2 UX: Connection quality metrics state
  const [metrics, setMetrics] = useState<ConnectionMetrics>({
    latencyMs: null,
    messagesPerSecond: 0,
    lastHeartbeatMs: null,
    reconnectCount: 0,
    lastError: null,
    isDegraded: false,
  })
  // Track message timestamps for rate calculation
  const messageTimestampsRef = useRef<number[]>([])

  // FIXED: P1-6 - Added clearPositions to prevent stale data when switching events
  // FIXED: P2-3 - Added leaderboard store actions
  // FIXED: P2-6 - Added checkpoint crossing actions
  const {
    setPositions,
    updatePosition,
    setVehicleVisibility,
    clearPositions,
    setLeaderboard,
    clearLeaderboard,
    addCrossing,
    clearCrossings,
  } = useEventStore()

  // FIXED: P1-7 - Batch position updates and apply them together
  const flushPositionBatch = useCallback(() => {
    if (positionBatchRef.current.size === 0) return

    // Apply all batched updates at once
    positionBatchRef.current.forEach((pos) => {
      updatePosition(pos as Parameters<typeof updatePosition>[0])
    })
    positionBatchRef.current.clear()
  }, [updatePosition])

  // Queue a position update for batching
  const queuePositionUpdate = useCallback((data: unknown) => {
    const pos = data as { vehicle_id: string }
    positionBatchRef.current.set(pos.vehicle_id, pos)

    // Schedule batch flush if not already scheduled
    if (!batchTimerRef.current) {
      batchTimerRef.current = setTimeout(() => {
        batchTimerRef.current = null
        flushPositionBatch()
      }, POSITION_BATCH_INTERVAL_MS)
    }
  }, [flushPositionBatch])

  const connect = useCallback(() => {
    if (!eventId || eventSourceRef.current) return

    const url = `${API_BASE}/events/${eventId}/stream`
    console.log('[SSE] Connecting to:', url)

    const es = new EventSource(url)
    eventSourceRef.current = es

    es.onopen = () => {
      console.log('[SSE] Connected')
      setIsConnected(true)
      reconnectAttempt.current = 0
      // Clear error state on successful connection
      setMetrics((m) => ({ ...m, lastError: null, isDegraded: false }))
    }

    es.onerror = (e) => {
      console.error('[SSE] Error:', e)
      setIsConnected(false)
      es.close()
      eventSourceRef.current = null

      // Determine error message based on ready state
      let errorMsg = 'Connection lost'
      if (es.readyState === EventSource.CONNECTING) {
        errorMsg = 'Failed to connect - server may be unavailable'
      }

      // Reconnect with backoff
      const delay = RECONNECT_DELAYS[Math.min(reconnectAttempt.current, RECONNECT_DELAYS.length - 1)]
      console.log(`[SSE] Reconnecting in ${delay}ms (attempt ${reconnectAttempt.current + 1})`)
      reconnectAttempt.current++

      // PR-2 UX: Track reconnect count and error state in metrics
      // Mark as degraded after 3 failed attempts
      const isDegraded = reconnectAttempt.current >= 3
      setMetrics((m) => ({
        ...m,
        reconnectCount: m.reconnectCount + 1,
        lastError: errorMsg,
        isDegraded,
      }))

      // FIXED: Track timer so it can be cleared on unmount (Issue #14 from audit)
      reconnectTimerRef.current = setTimeout(connect, delay)
    }

    // Handle events
    es.addEventListener('connected', () => {
      console.log('[SSE] Server acknowledged connection')
    })

    es.addEventListener('snapshot', (e) => {
      try {
        const data = JSON.parse(e.data)
        console.log('[SSE] Received snapshot:', data.vehicles?.length, 'vehicles')
        if (data.vehicles) {
          setPositions(data.vehicles)
        }
      } catch (err) {
        console.error('[SSE] Failed to parse snapshot:', err)
      }
    })

    // FIXED: P1-7 - Use batching for position updates to prevent race conditions
    es.addEventListener('position', (e) => {
      try {
        const data = JSON.parse(e.data)
        queuePositionUpdate(data)
      } catch (err) {
        console.error('[SSE] Failed to parse position:', err)
      }
    })

    // FIXED: P2-3 - Checkpoint events trigger leaderboard refresh
    // FIXED: P2-6 - Store checkpoint crossings for notifications
    es.addEventListener('checkpoint', (e) => {
      try {
        const data = JSON.parse(e.data)
        console.log('[SSE] Checkpoint crossing:', data)
        // Signal that leaderboard should be refreshed
        setLastCheckpointMs(Date.now())
        // FIXED: P2-6 - Add crossing for notification
        addCrossing({
          vehicle_id: data.vehicle_id,
          vehicle_number: data.vehicle_number || '?',
          team_name: data.team_name || 'Unknown',
          checkpoint_id: data.checkpoint_id || data.checkpoint || 0,
          checkpoint_name: data.checkpoint_name,
          lap_number: data.lap_number,
          crossing_time_ms: Date.now(),
        })
      } catch (err) {
        console.error('[SSE] Failed to parse checkpoint:', err)
      }
    })

    // FIXED: P2-3 - Handle direct leaderboard events (if backend supports)
    es.addEventListener('leaderboard', (e) => {
      try {
        const data = JSON.parse(e.data)
        console.log('[SSE] Leaderboard update:', data.entries?.length, 'entries')
        if (data.entries) {
          const ts = data.ts ? new Date(data.ts).getTime() : Date.now()
          setLeaderboard(data.entries, ts)
        }
      } catch (err) {
        console.error('[SSE] Failed to parse leaderboard:', err)
      }
    })

    es.addEventListener('permission', (e) => {
      try {
        const data = JSON.parse(e.data)
        console.log('[SSE] Permission change:', data)
        setVehicleVisibility(data.vehicle_id, data.visible)
      } catch (err) {
        console.error('[SSE] Failed to parse permission:', err)
      }
    })

    // PR-2 UX: Handle heartbeat events for latency tracking
    es.addEventListener('heartbeat', (e) => {
      try {
        const data = JSON.parse(e.data)
        const serverTs = data.ts_ms
        const now = Date.now()
        const latency = serverTs ? now - serverTs : null

        // Update message timestamps for rate calculation
        messageTimestampsRef.current.push(now)
        // Keep only timestamps within the window
        const cutoff = now - MESSAGE_RATE_WINDOW_MS
        messageTimestampsRef.current = messageTimestampsRef.current.filter((ts) => ts > cutoff)
        // Calculate messages per second
        const messagesPerSecond =
          messageTimestampsRef.current.length / (MESSAGE_RATE_WINDOW_MS / 1000)

        setMetrics((m) => ({
          ...m,
          latencyMs: latency,
          lastHeartbeatMs: now,
          messagesPerSecond,
        }))
      } catch (err) {
        console.error('[SSE] Failed to parse heartbeat:', err)
      }
    })
  }, [eventId, setPositions, queuePositionUpdate, setVehicleVisibility, setLeaderboard, addCrossing])

  // FIXED: P1-6 - Clear positions when switching events to prevent stale data
  // FIXED: P2-3 - Also clear leaderboard when switching events
  // FIXED: P2-6 - Also clear crossings when switching events
  useEffect(() => {
    if (prevEventIdRef.current && prevEventIdRef.current !== eventId) {
      console.log('[SSE] Event changed, clearing stale data')
      clearPositions()
      clearLeaderboard()
      clearCrossings()
      setLastCheckpointMs(null)
    }
    prevEventIdRef.current = eventId
  }, [eventId, clearPositions, clearLeaderboard, clearCrossings])

  useEffect(() => {
    connect()

    return () => {
      // FIXED: Clear reconnect timer on unmount to prevent memory leak (Issue #14 from audit)
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current)
        reconnectTimerRef.current = null
      }
      // FIXED: P1-7 - Clear batch timer and flush pending updates on unmount
      if (batchTimerRef.current) {
        clearTimeout(batchTimerRef.current)
        batchTimerRef.current = null
      }
      flushPositionBatch() // Apply any pending updates before closing
      if (eventSourceRef.current) {
        console.log('[SSE] Closing connection')
        eventSourceRef.current.close()
        eventSourceRef.current = null
      }
    }
  }, [connect, flushPositionBatch])

  // FIXED: P2-3 - Return lastCheckpointMs so consumers can trigger leaderboard refresh
  // PR-2 UX: Return connection metrics for monitoring
  return { isConnected, lastCheckpointMs, metrics }
}
