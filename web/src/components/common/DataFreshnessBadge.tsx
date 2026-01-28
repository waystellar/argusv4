/**
 * DataFreshnessBadge - Shows how fresh the displayed data is
 *
 * Automatically updates based on the last update timestamp to show:
 * - Fresh (green pulsing): Data updated within threshold
 * - Stale (yellow): Data older than fresh threshold but not offline
 * - Offline (gray): No data or very old data
 *
 * Also displays relative time since last update.
 */
import { useState, useEffect } from 'react'
import StatusPill, { getDataFreshnessVariant } from './StatusPill'

interface DataFreshnessBadgeProps {
  /** Timestamp of last data update (ms since epoch), null if never received */
  lastUpdateMs: number | null
  /** Threshold in ms for "fresh" state (default: 10000 = 10s) */
  freshThreshold?: number
  /** Threshold in ms for "stale" state (default: 60000 = 60s) */
  staleThreshold?: number
  /** Show relative time text (e.g., "5s ago") */
  showRelativeTime?: boolean
  /** Size variant */
  size?: 'xs' | 'sm' | 'md'
  /** Additional CSS classes */
  className?: string
}

function formatRelativeTime(ms: number | null): string {
  if (ms === null) return 'No data'

  const age = Date.now() - ms
  const seconds = Math.floor(age / 1000)

  if (seconds < 5) return 'Just now'
  if (seconds < 60) return `${seconds}s ago`

  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`

  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`

  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

export default function DataFreshnessBadge({
  lastUpdateMs,
  freshThreshold = 10000,
  staleThreshold = 60000,
  showRelativeTime = true,
  size = 'sm',
  className = '',
}: DataFreshnessBadgeProps) {
  // Force re-render every second to update relative time
  const [, setTick] = useState(0)

  useEffect(() => {
    const interval = setInterval(() => {
      setTick((t) => t + 1)
    }, 1000)
    return () => clearInterval(interval)
  }, [])

  const variant = getDataFreshnessVariant(lastUpdateMs, {
    fresh: freshThreshold,
    stale: staleThreshold,
  })

  // Custom labels based on freshness
  const getLabel = () => {
    if (showRelativeTime && lastUpdateMs !== null) {
      return formatRelativeTime(lastUpdateMs)
    }

    switch (variant) {
      case 'fresh':
        return 'Live'
      case 'stale':
        return 'Updating...'
      case 'offline':
        return 'Offline'
      default:
        return ''
    }
  }

  return (
    <StatusPill
      variant={variant}
      label={getLabel()}
      size={size}
      className={className}
    />
  )
}

/**
 * Hook to track data freshness
 * Returns a function to mark data as updated and the current freshness state
 */
export function useDataFreshness(thresholds?: {
  fresh?: number
  stale?: number
}) {
  const [lastUpdateMs, setLastUpdateMs] = useState<number | null>(null)
  const [, setTick] = useState(0)

  // Force re-render to update freshness state
  useEffect(() => {
    const interval = setInterval(() => {
      setTick((t) => t + 1)
    }, 1000)
    return () => clearInterval(interval)
  }, [])

  const markUpdated = () => {
    setLastUpdateMs(Date.now())
  }

  const variant = getDataFreshnessVariant(lastUpdateMs, thresholds)

  return {
    lastUpdateMs,
    markUpdated,
    variant,
    isFresh: variant === 'fresh',
    isStale: variant === 'stale',
    isOffline: variant === 'offline',
  }
}
