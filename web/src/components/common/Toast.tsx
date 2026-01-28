/**
 * Toast notification component
 *
 * UI-20: Migrated to design system tokens (neutral-*, status-*, accent-*, ds-*)
 * Displays temporary notifications for success, error, warning, and info messages.
 * Auto-dismisses after a configurable duration.
 *
 * Enhanced with:
 * - Global store integration
 * - Action buttons
 * - Mobile-safe positioning
 * - 44px touch targets
 */
import { useEffect, useState } from 'react'
import { useToastStore, type ToastData, type ToastType } from '../../stores/toastStore'

// Re-export types for backwards compatibility
export type { ToastData, ToastType }

interface ToastProps {
  toast: ToastData
  onDismiss: (id: string) => void
}

const ICONS: Record<ToastType, JSX.Element> = {
  success: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
    </svg>
  ),
  error: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
    </svg>
  ),
  warning: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
    </svg>
  ),
  info: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
}

const STYLES: Record<ToastType, string> = {
  success: 'bg-status-success/15 border-status-success/30 text-neutral-100',
  error: 'bg-status-error/15 border-status-error/30 text-neutral-100',
  warning: 'bg-status-warning/15 border-status-warning/30 text-neutral-100',
  info: 'bg-status-info/15 border-status-info/30 text-neutral-100',
}

const ICON_STYLES: Record<ToastType, string> = {
  success: 'text-status-success',
  error: 'text-status-error',
  warning: 'text-status-warning',
  info: 'text-status-info',
}

export function Toast({ toast, onDismiss }: ToastProps) {
  const [isLeaving, setIsLeaving] = useState(false)

  useEffect(() => {
    const duration = toast.duration ?? 4000
    // Duration of 0 means persistent (no auto-dismiss)
    if (duration === 0) return

    const timer = setTimeout(() => {
      setIsLeaving(true)
      setTimeout(() => onDismiss(toast.id), 300) // Wait for animation
    }, duration)

    return () => clearTimeout(timer)
  }, [toast.id, toast.duration, onDismiss])

  const handleDismiss = () => {
    setIsLeaving(true)
    setTimeout(() => onDismiss(toast.id), 300)
  }

  const handleAction = () => {
    toast.action?.onClick()
    handleDismiss()
  }

  const dismissible = toast.dismissible ?? true

  return (
    <div
      className={`
        flex items-start gap-ds-3 p-ds-4 rounded-ds-lg border shadow-ds-overlay backdrop-blur-sm
        transition-all duration-ds-normal ease-out min-w-[280px] max-w-[400px]
        ${STYLES[toast.type]}
        ${isLeaving ? 'opacity-0 translate-x-4' : 'opacity-100 translate-x-0'}
      `}
      role="alert"
    >
      <span className={`flex-shrink-0 mt-0.5 ${ICON_STYLES[toast.type]}`}>
        {ICONS[toast.type]}
      </span>

      <div className="flex-1 min-w-0">
        <p className="font-medium text-ds-body-sm">{toast.title}</p>
        {toast.message && (
          <p className="text-ds-body-sm opacity-80 mt-ds-1">{toast.message}</p>
        )}
        {toast.action && (
          <button
            onClick={handleAction}
            className="mt-ds-2 text-ds-body-sm font-medium underline underline-offset-2 hover:no-underline min-h-[44px] flex items-center"
          >
            {toast.action.label}
          </button>
        )}
      </div>

      {dismissible && (
        <button
          onClick={handleDismiss}
          className="flex-shrink-0 w-11 h-11 -mr-2 -mt-2 flex items-center justify-center hover:bg-white/10 rounded-ds-md transition-colors duration-ds-fast"
          aria-label="Dismiss"
        >
          <svg className="w-4 h-4 opacity-60" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      )}
    </div>
  )
}

interface ToastContainerProps {
  toasts?: ToastData[]
  onDismiss?: (id: string) => void
}

/**
 * ToastContainer - Can be used standalone with props OR with global store
 *
 * Usage with store (recommended):
 * ```tsx
 * // In App.tsx
 * <ToastContainer />
 *
 * // Anywhere in the app
 * import { toast } from '../stores/toastStore'
 * toast.success('Saved!')
 * ```
 *
 * Usage with props (legacy):
 * ```tsx
 * <ToastContainer toasts={toasts} onDismiss={handleDismiss} />
 * ```
 */
export function ToastContainer({ toasts: propToasts, onDismiss: propOnDismiss }: ToastContainerProps) {
  // Use store if no props provided
  const storeToasts = useToastStore((state) => state.toasts)
  const storeRemove = useToastStore((state) => state.removeToast)

  const toasts = propToasts ?? storeToasts
  const onDismiss = propOnDismiss ?? storeRemove

  if (toasts.length === 0) return null

  return (
    <div
      className="fixed bottom-20 sm:bottom-4 right-4 left-4 sm:left-auto z-50 flex flex-col gap-ds-2 safe-area-bottom"
      aria-live="polite"
      aria-label="Notifications"
    >
      {toasts.map((toast) => (
        <Toast key={toast.id} toast={toast} onDismiss={onDismiss} />
      ))}
    </div>
  )
}
