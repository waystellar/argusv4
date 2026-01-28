/**
 * Design System Badge Component
 *
 * Status indicators and labels with semantic colors.
 * Supports dot indicators for connection/status states.
 */
import { HTMLAttributes, ReactNode } from 'react'

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  variant?: 'neutral' | 'success' | 'warning' | 'error' | 'info'
  size?: 'sm' | 'md'
  dot?: boolean
  pulse?: boolean
  children: ReactNode
}

export default function Badge({
  variant = 'neutral',
  size = 'md',
  dot = false,
  pulse = false,
  children,
  className = '',
  ...props
}: BadgeProps) {
  const baseClasses = 'ds-badge inline-flex items-center font-medium rounded-ds-full'

  const variantClasses = {
    neutral: 'ds-badge-neutral bg-neutral-800 text-neutral-300',
    success: 'ds-badge-success bg-status-success/20 text-status-success',
    warning: 'ds-badge-warning bg-status-warning/20 text-status-warning',
    error: 'ds-badge-error bg-status-error/20 text-status-error',
    info: 'ds-badge-info bg-status-info/20 text-status-info',
  }

  const dotColors = {
    neutral: 'bg-neutral-500',
    success: 'bg-status-success',
    warning: 'bg-status-warning',
    error: 'bg-status-error',
    info: 'bg-status-info',
  }

  const sizeClasses = {
    sm: 'text-[10px] px-2 py-0.5 gap-1',
    md: 'text-ds-caption px-2.5 py-1 gap-1.5',
  }

  const dotSizeClasses = {
    sm: 'w-1.5 h-1.5',
    md: 'w-2 h-2',
  }

  return (
    <span
      className={`${baseClasses} ${variantClasses[variant]} ${sizeClasses[size]} ${className}`}
      {...props}
    >
      {dot && (
        <span
          className={`ds-badge-dot ${dotSizeClasses[size]} ${dotColors[variant]} rounded-full ${pulse ? 'ds-badge-dot-pulse animate-pulse' : ''}`}
        />
      )}
      {children}
    </span>
  )
}

// Preset badges for common status states
export function OnlineBadge({ className = '' }: { className?: string }) {
  return (
    <Badge variant="success" dot pulse className={className}>
      Online
    </Badge>
  )
}

export function OfflineBadge({ className = '' }: { className?: string }) {
  return (
    <Badge variant="error" dot className={className}>
      Offline
    </Badge>
  )
}

export function StreamingBadge({ className = '' }: { className?: string }) {
  return (
    <Badge variant="error" dot pulse className={className}>
      LIVE
    </Badge>
  )
}

export function StaleBadge({ className = '' }: { className?: string }) {
  return (
    <Badge variant="warning" dot className={className}>
      Stale
    </Badge>
  )
}

export function NoDataBadge({ className = '' }: { className?: string }) {
  return (
    <Badge variant="neutral" className={className}>
      No Data
    </Badge>
  )
}
