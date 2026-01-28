/**
 * Connection status indicator
 *
 * UI-15: Migrated to design system tokens (neutral-*, status-*)
 * PR-2 UX: Enhanced to show latency and connection quality when metrics provided.
 */
import type { ConnectionMetrics } from '../../hooks/useEventStream'

interface ConnectionStatusProps {
  isConnected: boolean
  /** PR-2 UX: Optional connection metrics for enhanced display */
  metrics?: ConnectionMetrics
  /** Show expanded details (latency, message rate) when connected */
  showDetails?: boolean
}

/**
 * Get latency quality indicator color
 */
function getLatencyColor(latencyMs: number | null): string {
  if (latencyMs === null) return 'text-neutral-400'
  if (latencyMs <= 100) return 'text-status-success'
  if (latencyMs <= 300) return 'text-status-warning'
  if (latencyMs <= 500) return 'text-status-warning'
  return 'text-status-error'
}

export default function ConnectionStatus({
  isConnected,
  metrics,
  showDetails = false,
}: ConnectionStatusProps) {
  // Disconnected state - always show
  if (!isConnected) {
    return (
      <div className="bg-status-error/20 text-status-error text-ds-caption text-center py-ds-1 flex items-center justify-center gap-ds-2">
        <span className="w-2 h-2 bg-status-error rounded-full animate-pulse" />
        Reconnecting...
        {metrics && metrics.reconnectCount > 0 && (
          <span className="opacity-60">({metrics.reconnectCount})</span>
        )}
      </div>
    )
  }

  // Connected with details requested and metrics available
  if (showDetails && metrics) {
    const latencyColor = getLatencyColor(metrics.latencyMs)

    return (
      <div className="bg-neutral-900/50 text-ds-caption text-center py-ds-1 flex items-center justify-center gap-ds-3 border-b border-neutral-800/50">
        {/* Connection indicator */}
        <span className="flex items-center gap-1.5 text-status-success">
          <span className="w-1.5 h-1.5 bg-status-success rounded-full" />
          Live
        </span>

        {/* Latency */}
        {metrics.latencyMs !== null && (
          <span className={`${latencyColor}`}>
            {metrics.latencyMs}ms
          </span>
        )}

        {/* Message rate (only if active) */}
        {metrics.messagesPerSecond > 0 && (
          <span className="text-neutral-400">
            {metrics.messagesPerSecond.toFixed(1)}/s
          </span>
        )}
      </div>
    )
  }

  // Connected without details - show nothing (clean UI)
  return null
}
