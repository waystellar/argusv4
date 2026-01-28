/**
 * Toast notification context and hook
 *
 * Provides a global toast notification system accessible from any component.
 *
 * Usage:
 *   const toast = useToast()
 *   toast.success('Event created!')
 *   toast.error('Failed to save', 'Please try again')
 */
import { createContext, useContext, useState, useCallback, ReactNode } from 'react'
import { ToastContainer, ToastData, ToastType } from '../components/common/Toast'

interface ToastContextValue {
  /** Show a success toast */
  success: (title: string, message?: string) => void
  /** Show an error toast */
  error: (title: string, message?: string) => void
  /** Show a warning toast */
  warning: (title: string, message?: string) => void
  /** Show an info toast */
  info: (title: string, message?: string) => void
  /** Show a custom toast */
  show: (type: ToastType, title: string, message?: string, duration?: number) => void
  /** Dismiss a specific toast */
  dismiss: (id: string) => void
  /** Dismiss all toasts */
  dismissAll: () => void
}

const ToastContext = createContext<ToastContextValue | null>(null)

let toastIdCounter = 0

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastData[]>([])

  const dismiss = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id))
  }, [])

  const dismissAll = useCallback(() => {
    setToasts([])
  }, [])

  const show = useCallback(
    (type: ToastType, title: string, message?: string, duration?: number) => {
      const id = `toast-${++toastIdCounter}`
      const toast: ToastData = { id, type, title, message, duration }

      setToasts((prev) => {
        // Limit to 5 toasts max to prevent overflow
        const newToasts = [...prev, toast]
        if (newToasts.length > 5) {
          return newToasts.slice(-5)
        }
        return newToasts
      })

      return id
    },
    []
  )

  const success = useCallback(
    (title: string, message?: string) => show('success', title, message),
    [show]
  )

  const error = useCallback(
    (title: string, message?: string) => show('error', title, message, 6000), // Errors show longer
    [show]
  )

  const warning = useCallback(
    (title: string, message?: string) => show('warning', title, message, 5000),
    [show]
  )

  const info = useCallback(
    (title: string, message?: string) => show('info', title, message),
    [show]
  )

  const value: ToastContextValue = {
    success,
    error,
    warning,
    info,
    show,
    dismiss,
    dismissAll,
  }

  return (
    <ToastContext.Provider value={value}>
      {children}
      <ToastContainer toasts={toasts} onDismiss={dismiss} />
    </ToastContext.Provider>
  )
}

export function useToast(): ToastContextValue {
  const context = useContext(ToastContext)
  if (!context) {
    throw new Error('useToast must be used within a ToastProvider')
  }
  return context
}
