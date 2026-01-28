/**
 * Global toast store for app-wide notifications
 *
 * Provides easy access to show toasts from anywhere in the app:
 * - showToast({ type: 'success', title: 'Done!' })
 * - toast.success('Saved!')
 * - toast.error('Failed', 'Check your connection')
 */
import { create } from 'zustand'

export type ToastType = 'success' | 'error' | 'warning' | 'info'

export interface ToastAction {
  label: string
  onClick: () => void
}

export interface ToastData {
  id: string
  type: ToastType
  title: string
  message?: string
  duration?: number // ms, default 4000, set to 0 for persistent
  action?: ToastAction
  dismissible?: boolean // default true
}

interface ToastState {
  toasts: ToastData[]
  addToast: (toast: Omit<ToastData, 'id'>) => string
  removeToast: (id: string) => void
  clearAll: () => void
}

let toastCounter = 0

export const useToastStore = create<ToastState>((set) => ({
  toasts: [],

  addToast: (toast) => {
    const id = `toast-${++toastCounter}-${Date.now()}`
    const newToast: ToastData = {
      ...toast,
      id,
      dismissible: toast.dismissible ?? true,
    }

    set((state) => ({
      toasts: [...state.toasts, newToast],
    }))

    return id
  },

  removeToast: (id) => {
    set((state) => ({
      toasts: state.toasts.filter((t) => t.id !== id),
    }))
  },

  clearAll: () => {
    set({ toasts: [] })
  },
}))

// Convenience helper for showing toasts from anywhere
export const toast = {
  show: (options: Omit<ToastData, 'id'>): string => {
    return useToastStore.getState().addToast(options)
  },

  success: (title: string, message?: string, options?: Partial<ToastData>): string => {
    return useToastStore.getState().addToast({
      type: 'success',
      title,
      message,
      ...options,
    })
  },

  error: (title: string, message?: string, options?: Partial<ToastData>): string => {
    return useToastStore.getState().addToast({
      type: 'error',
      title,
      message,
      duration: 6000, // Errors stay longer by default
      ...options,
    })
  },

  warning: (title: string, message?: string, options?: Partial<ToastData>): string => {
    return useToastStore.getState().addToast({
      type: 'warning',
      title,
      message,
      duration: 5000,
      ...options,
    })
  },

  info: (title: string, message?: string, options?: Partial<ToastData>): string => {
    return useToastStore.getState().addToast({
      type: 'info',
      title,
      message,
      ...options,
    })
  },

  dismiss: (id: string): void => {
    useToastStore.getState().removeToast(id)
  },

  clearAll: (): void => {
    useToastStore.getState().clearAll()
  },
}
