/**
 * Design System EmptyState Component
 *
 * Placeholder for empty lists, no-data states, and error recovery.
 * Provides consistent messaging and optional action buttons.
 */
import { ReactNode } from 'react'
import Button from './Button'

export interface EmptyStateProps {
  icon?: ReactNode
  title: string
  description?: string
  action?: {
    label: string
    onClick: () => void
    variant?: 'primary' | 'secondary'
  }
  secondaryAction?: {
    label: string
    onClick: () => void
  }
  className?: string
}

export default function EmptyState({
  icon,
  title,
  description,
  action,
  secondaryAction,
  className = '',
}: EmptyStateProps) {
  return (
    <div className={`flex flex-col items-center justify-center text-center p-ds-8 ${className}`}>
      {icon && (
        <div className="mb-ds-4 text-neutral-600">
          {icon}
        </div>
      )}
      <h3 className="text-ds-heading text-neutral-50 mb-ds-2">
        {title}
      </h3>
      {description && (
        <p className="text-ds-body-sm text-neutral-400 max-w-sm mb-ds-6">
          {description}
        </p>
      )}
      {(action || secondaryAction) && (
        <div className="flex items-center gap-ds-3">
          {action && (
            <Button
              variant={action.variant || 'primary'}
              onClick={action.onClick}
            >
              {action.label}
            </Button>
          )}
          {secondaryAction && (
            <Button
              variant="ghost"
              onClick={secondaryAction.onClick}
            >
              {secondaryAction.label}
            </Button>
          )}
        </div>
      )}
    </div>
  )
}

// Common preset empty states
export function NoEventsState({ onCreateEvent }: { onCreateEvent?: () => void }) {
  return (
    <EmptyState
      icon={
        <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
            d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
        </svg>
      }
      title="No events found"
      description="Create your first event to start tracking vehicles and times."
      action={onCreateEvent ? { label: 'Create Event', onClick: onCreateEvent } : undefined}
    />
  )
}

export function NoVehiclesState({ onAddVehicle }: { onAddVehicle?: () => void }) {
  return (
    <EmptyState
      icon={
        <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
            d="M9 17a2 2 0 11-4 0 2 2 0 014 0zM19 17a2 2 0 11-4 0 2 2 0 014 0z" />
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
            d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h1m8-1a1 1 0 01-1 1H9m4-1V8a1 1 0 011-1h2.586a1 1 0 01.707.293l3.414 3.414a1 1 0 01.293.707V16a1 1 0 01-1 1h-1m-6-1a1 1 0 001 1h1M5 17a2 2 0 104 0m-4 0a2 2 0 114 0m6 0a2 2 0 104 0m-4 0a2 2 0 114 0" />
        </svg>
      }
      title="No vehicles registered"
      description="Register vehicles to see them on the map and track their times."
      action={onAddVehicle ? { label: 'Add Vehicle', onClick: onAddVehicle } : undefined}
    />
  )
}

export function NoDataState({ onRetry }: { onRetry?: () => void }) {
  return (
    <EmptyState
      icon={
        <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
            d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M12 12h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      }
      title="No data available"
      description="We couldn't load the data. Check your connection and try again."
      action={onRetry ? { label: 'Try Again', onClick: onRetry } : undefined}
    />
  )
}

export function ConnectionErrorState({ onRetry }: { onRetry?: () => void }) {
  return (
    <EmptyState
      icon={
        <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
            d="M18.364 5.636a9 9 0 010 12.728m0 0l-2.829-2.829m2.829 2.829L21 21M15.536 8.464a5 5 0 010 7.072m0 0l-2.829-2.829m-4.243 2.829a4.978 4.978 0 01-1.414-2.83m-1.414 5.658a9 9 0 01-2.167-9.238m7.824 2.167a1 1 0 111.414 1.414m-1.414-1.414L3 3m8.293 8.293l1.414 1.414" />
        </svg>
      }
      title="Connection lost"
      description="Unable to connect to the server. Please check your internet connection."
      action={onRetry ? { label: 'Reconnect', onClick: onRetry } : undefined}
    />
  )
}
