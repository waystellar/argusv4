/**
 * SystemHealthIndicator - Detailed system health for ops/debugging
 *
 * UI-14: Migrated to design system tokens (neutral-*, status-*)
 *
 * PR-2 UX: Shows comprehensive connection and data health metrics.
 * Intended for organizers/admins, not general fans.
 *
 * Only visible when VITE_ENABLE_DEBUG_PANEL=true or for admin users.
 */
import { useState, useEffect } from 'react'
import type { ConnectionMetrics } from '../../hooks/useEventStream'
import { useEventStore, FRESHNESS_THRESHOLDS } from '../../stores/eventStore'

interface SystemHealthIndicatorProps {
  /** SSE connection state */
  isConnected: boolean
  /** Connection quality metrics from useEventStream */
  metrics: ConnectionMetrics
  /** Force show even without debug mode (for admin dashboard) */
  forceShow?: boolean
}

/**
 * Format milliseconds as human-readable time ago
 */
function formatTimeAgo(ms: number | null): string {
  if (ms === null) return 'Never'
  const ago = Date.now() - ms
  if (ago < 1000) return 'Just now'
  if (ago < 60000) return `${Math.floor(ago / 1000)}s ago`
  if (ago < 3600000) return `${Math.floor(ago / 60000)}m ago`
  return `${Math.floor(ago / 3600000)}h ago`
}

export default function SystemHealthIndicator({
  isConnected,
  metrics,
  forceShow = false,
}: SystemHealthIndicatorProps) {
  const [isExpanded, setIsExpanded] = useState(false)
  const [, setTick] = useState(0)
  const getVehicleStats = useEventStore((state) => state.getVehicleStats)
  const positions = useEventStore((state) => state.positions)

  // Force re-render every second to update time-based values
  useEffect(() => {
    const interval = setInterval(() => setTick((t) => t + 1), 1000)
    return () => clearInterval(interval)
  }, [])

  // Check if debug mode is enabled
  const debugEnabled =
    forceShow || import.meta.env.VITE_ENABLE_DEBUG_PANEL === 'true'

  if (!debugEnabled) return null

  const vehicleStats = getVehicleStats()
  const totalVehicles = positions.size

  // Calculate overall health score
  const healthScore =
    totalVehicles > 0
      ? Math.round((vehicleStats.fresh / totalVehicles) * 100)
      : 0
  const healthColor =
    healthScore >= 80
      ? 'text-status-success'
      : healthScore >= 50
        ? 'text-status-warning'
        : 'text-status-error'

  return (
    <div className="fixed bottom-4 right-4 z-50">
      {/* Collapsed badge */}
      {!isExpanded && (
        <button
          onClick={() => setIsExpanded(true)}
          className={`
            px-ds-3 py-ds-1 rounded-ds-full text-ds-caption font-medium
            ${isConnected ? 'bg-neutral-800/90' : 'bg-status-error/20'}
            backdrop-blur-sm shadow-ds-dark-lg border border-neutral-700
            hover:border-neutral-600 transition-colors duration-ds-fast
            focus:outline-none focus:ring-2 focus:ring-accent-500
          `}
        >
          <span className="flex items-center gap-ds-2">
            <span
              className={`w-2 h-2 rounded-full ${isConnected ? 'bg-status-success' : 'bg-status-error animate-pulse'}`}
            />
            {isConnected ? (
              <>
                <span className={healthColor}>{healthScore}%</span>
                {metrics.latencyMs !== null && (
                  <span className="text-neutral-400">{metrics.latencyMs}ms</span>
                )}
              </>
            ) : (
              <span className="text-status-error">Offline</span>
            )}
          </span>
        </button>
      )}

      {/* Expanded panel */}
      {isExpanded && (
        <div className="bg-neutral-900/95 backdrop-blur-sm rounded-ds-lg shadow-ds-overlay border border-neutral-700 w-72 text-ds-caption">
          {/* Header */}
          <div className="flex items-center justify-between px-ds-3 py-ds-2 border-b border-neutral-800">
            <span className="font-semibold text-neutral-200">System Health</span>
            <button
              onClick={() => setIsExpanded(false)}
              className="text-neutral-500 hover:text-neutral-300 transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500 rounded-ds-sm"
            >
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          {/* Content */}
          <div className="p-ds-3 space-y-ds-3">
            {/* Connection status */}
            <div className="flex items-center justify-between">
              <span className="text-neutral-400">Connection</span>
              <span className={isConnected ? 'text-status-success' : 'text-status-error'}>
                {isConnected ? 'Connected' : 'Disconnected'}
              </span>
            </div>

            {/* Latency */}
            <div className="flex items-center justify-between">
              <span className="text-neutral-400">Latency</span>
              <span
                className={
                  metrics.latencyMs === null
                    ? 'text-neutral-500'
                    : metrics.latencyMs <= 200
                      ? 'text-status-success'
                      : metrics.latencyMs <= 500
                        ? 'text-status-warning'
                        : 'text-status-error'
                }
              >
                {metrics.latencyMs !== null ? `${metrics.latencyMs}ms` : 'N/A'}
              </span>
            </div>

            {/* Message rate */}
            <div className="flex items-center justify-between">
              <span className="text-neutral-400">Message Rate</span>
              <span className="text-neutral-200">
                {metrics.messagesPerSecond.toFixed(1)}/s
              </span>
            </div>

            {/* Last heartbeat */}
            <div className="flex items-center justify-between">
              <span className="text-neutral-400">Last Heartbeat</span>
              <span className="text-neutral-200">
                {formatTimeAgo(metrics.lastHeartbeatMs)}
              </span>
            </div>

            {/* Reconnects */}
            <div className="flex items-center justify-between">
              <span className="text-neutral-400">Reconnects</span>
              <span
                className={
                  metrics.reconnectCount === 0
                    ? 'text-status-success'
                    : metrics.reconnectCount < 3
                      ? 'text-status-warning'
                      : 'text-status-error'
                }
              >
                {metrics.reconnectCount}
              </span>
            </div>

            {/* Divider */}
            <div className="border-t border-neutral-800 pt-ds-3">
              <span className="text-neutral-400 block mb-ds-2">Vehicle Status</span>

              {/* Vehicle stats */}
              <div className="flex gap-ds-4">
                <div className="flex-1 text-center">
                  <div className="text-lg font-semibold text-status-success">
                    {vehicleStats.fresh}
                  </div>
                  <div className="text-neutral-500">Fresh</div>
                </div>
                <div className="flex-1 text-center">
                  <div className="text-lg font-semibold text-status-warning">
                    {vehicleStats.stale}
                  </div>
                  <div className="text-neutral-500">Stale</div>
                </div>
                <div className="flex-1 text-center">
                  <div className="text-lg font-semibold text-neutral-400">
                    {vehicleStats.offline}
                  </div>
                  <div className="text-neutral-500">Offline</div>
                </div>
              </div>
            </div>

            {/* Thresholds info */}
            <div className="text-neutral-500 text-ds-caption pt-ds-2 border-t border-neutral-800">
              Fresh: &lt;{FRESHNESS_THRESHOLDS.fresh / 1000}s |
              Stale: &lt;{FRESHNESS_THRESHOLDS.stale / 1000}s |
              Offline: &gt;{FRESHNESS_THRESHOLDS.offline / 1000}s
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
