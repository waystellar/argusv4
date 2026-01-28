/**
 * Design System Alert Component
 *
 * Inline alert/notification for contextual messages.
 * For toast notifications (auto-dismissing), use the Toast component.
 */
import { ReactNode } from 'react'

export interface AlertProps {
  variant?: 'info' | 'success' | 'warning' | 'error'
  title?: string
  children: ReactNode
  icon?: ReactNode
  action?: {
    label: string
    onClick: () => void
  }
  onDismiss?: () => void
  className?: string
}

const defaultIcons = {
  info: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
        d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
  success: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
        d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
  warning: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
        d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
    </svg>
  ),
  error: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
        d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
}

export default function Alert({
  variant = 'info',
  title,
  children,
  icon,
  action,
  onDismiss,
  className = '',
}: AlertProps) {
  const variantClasses = {
    info: 'bg-status-info/10 border-status-info/30 text-status-info',
    success: 'bg-status-success/10 border-status-success/30 text-status-success',
    warning: 'bg-status-warning/10 border-status-warning/30 text-status-warning',
    error: 'bg-status-error/10 border-status-error/30 text-status-error',
  }

  const iconColors = {
    info: 'text-status-info',
    success: 'text-status-success',
    warning: 'text-status-warning',
    error: 'text-status-error',
  }

  return (
    <div
      role="alert"
      className={`
        flex items-start gap-ds-3 p-ds-4 rounded-ds-lg border
        ${variantClasses[variant]}
        ${className}
      `}
    >
      {/* Icon */}
      <div className={`flex-shrink-0 ${iconColors[variant]}`}>
        {icon || defaultIcons[variant]}
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        {title && (
          <h4 className="text-ds-body-sm font-semibold text-neutral-50 mb-ds-1">
            {title}
          </h4>
        )}
        <div className="text-ds-body-sm text-neutral-300">
          {children}
        </div>
        {action && (
          <button
            onClick={action.onClick}
            className="mt-ds-2 text-ds-body-sm font-medium underline hover:no-underline"
          >
            {action.label}
          </button>
        )}
      </div>

      {/* Dismiss button */}
      {onDismiss && (
        <button
          onClick={onDismiss}
          className="flex-shrink-0 p-1 rounded hover:bg-white/10 text-neutral-400 hover:text-neutral-50 transition-colors"
          aria-label="Dismiss"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      )}
    </div>
  )
}

// Convenience components for common alert types
export function InfoAlert({ children, ...props }: Omit<AlertProps, 'variant'>) {
  return <Alert variant="info" {...props}>{children}</Alert>
}

export function SuccessAlert({ children, ...props }: Omit<AlertProps, 'variant'>) {
  return <Alert variant="success" {...props}>{children}</Alert>
}

export function WarningAlert({ children, ...props }: Omit<AlertProps, 'variant'>) {
  return <Alert variant="warning" {...props}>{children}</Alert>
}

export function ErrorAlert({ children, ...props }: Omit<AlertProps, 'variant'>) {
  return <Alert variant="error" {...props}>{children}</Alert>
}
