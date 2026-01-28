/**
 * StatusPill - Reusable status indicator component
 *
 * UI-14: Migrated to design system tokens (neutral-*, status-*)
 *
 * Provides consistent status badges across the app for:
 * - Event status (live, upcoming, finished)
 * - Connection status (connected, disconnected, reconnecting)
 * - Data freshness (fresh, stale, offline)
 * - Semantic status (success, warning, error, info)
 */

type StatusVariant =
  | 'live'
  | 'upcoming'
  | 'finished'
  | 'connected'
  | 'disconnected'
  | 'reconnecting'
  | 'fresh'
  | 'stale'
  | 'offline'
  | 'success'
  | 'warning'
  | 'error'
  | 'info'
  | 'neutral'

type StatusSize = 'xs' | 'sm' | 'md'

interface StatusPillProps {
  variant: StatusVariant
  /** Override the default label */
  label?: string
  /** Show pulsing indicator dot */
  pulse?: boolean
  /** Size variant */
  size?: StatusSize
  /** Additional CSS classes */
  className?: string
  /** Whether to show the dot indicator */
  showDot?: boolean
}

// Configuration for each status variant — design system tokens
const VARIANT_CONFIG: Record<
  StatusVariant,
  {
    bg: string
    text: string
    dotColor: string
    defaultLabel: string
    defaultPulse: boolean
    defaultShowDot: boolean
  }
> = {
  // Event status
  live: {
    bg: 'bg-status-success',
    text: 'text-white',
    dotColor: 'bg-neutral-50',
    defaultLabel: 'LIVE',
    defaultPulse: true,
    defaultShowDot: true,
  },
  upcoming: {
    bg: 'bg-status-info',
    text: 'text-white',
    dotColor: 'bg-neutral-50',
    defaultLabel: 'UPCOMING',
    defaultPulse: false,
    defaultShowDot: false,
  },
  finished: {
    bg: 'bg-neutral-600',
    text: 'text-neutral-200',
    dotColor: 'bg-neutral-400',
    defaultLabel: 'FINISHED',
    defaultPulse: false,
    defaultShowDot: false,
  },

  // Connection status
  connected: {
    bg: 'bg-status-success/15',
    text: 'text-status-success',
    dotColor: 'bg-status-success',
    defaultLabel: 'Connected',
    defaultPulse: false,
    defaultShowDot: true,
  },
  disconnected: {
    bg: 'bg-status-error/15',
    text: 'text-status-error',
    dotColor: 'bg-status-error',
    defaultLabel: 'Disconnected',
    defaultPulse: true,
    defaultShowDot: true,
  },
  reconnecting: {
    bg: 'bg-status-warning/15',
    text: 'text-status-warning',
    dotColor: 'bg-status-warning',
    defaultLabel: 'Reconnecting...',
    defaultPulse: true,
    defaultShowDot: true,
  },

  // Data freshness
  fresh: {
    bg: 'bg-status-success/10',
    text: 'text-status-success',
    dotColor: 'bg-status-success',
    defaultLabel: 'Live',
    defaultPulse: true,
    defaultShowDot: true,
  },
  stale: {
    bg: 'bg-status-warning/10',
    text: 'text-status-warning',
    dotColor: 'bg-status-warning',
    defaultLabel: 'Stale',
    defaultPulse: false,
    defaultShowDot: true,
  },
  offline: {
    bg: 'bg-neutral-800',
    text: 'text-neutral-500',
    dotColor: 'bg-neutral-500',
    defaultLabel: 'Offline',
    defaultPulse: false,
    defaultShowDot: true,
  },

  // Semantic status
  success: {
    bg: 'bg-status-success/15',
    text: 'text-status-success',
    dotColor: 'bg-status-success',
    defaultLabel: 'Success',
    defaultPulse: false,
    defaultShowDot: false,
  },
  warning: {
    bg: 'bg-status-warning/15',
    text: 'text-status-warning',
    dotColor: 'bg-status-warning',
    defaultLabel: 'Warning',
    defaultPulse: false,
    defaultShowDot: false,
  },
  error: {
    bg: 'bg-status-error/15',
    text: 'text-status-error',
    dotColor: 'bg-status-error',
    defaultLabel: 'Error',
    defaultPulse: false,
    defaultShowDot: false,
  },
  info: {
    bg: 'bg-status-info/15',
    text: 'text-status-info',
    dotColor: 'bg-status-info',
    defaultLabel: 'Info',
    defaultPulse: false,
    defaultShowDot: false,
  },
  neutral: {
    bg: 'bg-neutral-700',
    text: 'text-neutral-300',
    dotColor: 'bg-neutral-400',
    defaultLabel: '',
    defaultPulse: false,
    defaultShowDot: false,
  },
}

// Size configurations — design system spacing and typography tokens
const SIZE_CONFIG: Record<StatusSize, { pill: string; dot: string; font: string }> = {
  xs: {
    pill: 'px-ds-1 py-0.5 gap-1',
    dot: 'w-1.5 h-1.5',
    font: 'text-ds-caption',
  },
  sm: {
    pill: 'px-ds-2 py-0.5 gap-1.5',
    dot: 'w-2 h-2',
    font: 'text-ds-caption',
  },
  md: {
    pill: 'px-ds-3 py-ds-1 gap-ds-2',
    dot: 'w-2 h-2',
    font: 'text-ds-body-sm',
  },
}

export default function StatusPill({
  variant,
  label,
  pulse,
  size = 'sm',
  className = '',
  showDot,
}: StatusPillProps) {
  const config = VARIANT_CONFIG[variant]
  const sizeConfig = SIZE_CONFIG[size]

  const displayLabel = label ?? config.defaultLabel
  const shouldPulse = pulse ?? config.defaultPulse
  const shouldShowDot = showDot ?? config.defaultShowDot

  return (
    <span
      className={`
        inline-flex items-center rounded-ds-sm font-bold uppercase tracking-wide
        ${config.bg} ${config.text}
        ${sizeConfig.pill} ${sizeConfig.font}
        ${className}
      `}
    >
      {shouldShowDot && (
        <span className="relative flex">
          {shouldPulse && (
            <span
              className={`absolute inline-flex h-full w-full rounded-full ${config.dotColor} opacity-75 animate-ping`}
            />
          )}
          <span
            className={`relative inline-flex rounded-full ${config.dotColor} ${sizeConfig.dot}`}
          />
        </span>
      )}
      {displayLabel}
    </span>
  )
}

// Helper to convert event status to variant
export function getEventStatusVariant(status: string): StatusVariant {
  switch (status) {
    case 'in_progress':
      return 'live'
    case 'upcoming':
      return 'upcoming'
    case 'finished':
      return 'finished'
    default:
      return 'neutral'
  }
}

// Helper to convert connection state to variant
export function getConnectionVariant(
  isConnected: boolean,
  isReconnecting?: boolean
): StatusVariant {
  if (isConnected) return 'connected'
  if (isReconnecting) return 'reconnecting'
  return 'disconnected'
}

// Helper to convert data age to freshness variant
export function getDataFreshnessVariant(
  lastUpdateMs: number | null,
  thresholds?: { fresh?: number; stale?: number }
): StatusVariant {
  if (lastUpdateMs === null) return 'offline'

  const age = Date.now() - lastUpdateMs
  const freshThreshold = thresholds?.fresh ?? 10000 // 10 seconds
  const staleThreshold = thresholds?.stale ?? 60000 // 60 seconds

  if (age < freshThreshold) return 'fresh'
  if (age < staleThreshold) return 'stale'
  return 'offline'
}
