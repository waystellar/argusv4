/**
 * ConfirmModal - Reusable confirmation dialog
 *
 * UI-20: Migrated to design system tokens (neutral-*, status-*, accent-*, ds-*)
 * For destructive or important actions that need user confirmation.
 * Features:
 * - Accessible (focus trap, escape key, aria labels)
 * - Mobile-friendly with 44px touch targets
 * - Supports different variants (danger, warning, info)
 * - Optional loading state for async actions
 */
import { useState, useEffect, useRef, useCallback } from 'react'

type ModalVariant = 'danger' | 'warning' | 'info'

interface ConfirmModalProps {
  /** Whether the modal is open */
  isOpen: boolean
  /** Called when modal should close */
  onClose: () => void
  /** Called when confirmed */
  onConfirm: () => void | Promise<void>
  /** Modal title */
  title: string
  /** Modal message/description */
  message: string | React.ReactNode
  /** Confirm button text (default: "Confirm") */
  confirmText?: string
  /** Cancel button text (default: "Cancel") */
  cancelText?: string
  /** Variant affects button color (default: "danger") */
  variant?: ModalVariant
  /** Show loading state on confirm button */
  isLoading?: boolean
  /** Disable confirm button */
  disabled?: boolean
}

const VARIANT_STYLES: Record<ModalVariant, { button: string; icon: JSX.Element }> = {
  danger: {
    button: 'bg-status-error hover:bg-status-error/90 focus:ring-status-error',
    icon: (
      <svg className="w-6 h-6 text-status-error" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
      </svg>
    ),
  },
  warning: {
    button: 'bg-status-warning hover:bg-status-warning/90 focus:ring-status-warning',
    icon: (
      <svg className="w-6 h-6 text-status-warning" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
      </svg>
    ),
  },
  info: {
    button: 'bg-accent-600 hover:bg-accent-500 focus:ring-accent-500',
    icon: (
      <svg className="w-6 h-6 text-accent-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    ),
  },
}

export default function ConfirmModal({
  isOpen,
  onClose,
  onConfirm,
  title,
  message,
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  variant = 'danger',
  isLoading = false,
  disabled = false,
}: ConfirmModalProps) {
  const modalRef = useRef<HTMLDivElement>(null)
  const cancelRef = useRef<HTMLButtonElement>(null)

  // Focus trap - focus cancel button on open
  useEffect(() => {
    if (isOpen) {
      cancelRef.current?.focus()
    }
  }, [isOpen])

  // Handle escape key
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !isLoading) {
        onClose()
      }
    },
    [onClose, isLoading]
  )

  useEffect(() => {
    if (isOpen) {
      document.addEventListener('keydown', handleKeyDown)
      // Prevent body scroll
      document.body.style.overflow = 'hidden'
    }
    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      document.body.style.overflow = ''
    }
  }, [isOpen, handleKeyDown])

  // Handle backdrop click
  const handleBackdropClick = (e: React.MouseEvent) => {
    if (e.target === e.currentTarget && !isLoading) {
      onClose()
    }
  }

  // Handle confirm
  const handleConfirm = async () => {
    await onConfirm()
  }

  if (!isOpen) return null

  const variantStyle = VARIANT_STYLES[variant]

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-ds-4 bg-black/70 backdrop-blur-sm"
      onClick={handleBackdropClick}
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
      aria-describedby="modal-description"
    >
      <div
        ref={modalRef}
        className="bg-neutral-900 rounded-ds-xl shadow-ds-overlay max-w-md w-full border border-neutral-700 animate-in fade-in zoom-in-95 duration-ds-normal"
      >
        {/* Header */}
        <div className="flex items-start gap-ds-4 p-ds-6 pb-ds-4">
          <div className="flex-shrink-0 p-ds-2 bg-neutral-800 rounded-full">
            {variantStyle.icon}
          </div>
          <div className="flex-1 min-w-0 pt-ds-1">
            <h2
              id="modal-title"
              className="text-ds-heading font-bold text-neutral-50"
            >
              {title}
            </h2>
          </div>
        </div>

        {/* Content */}
        <div
          id="modal-description"
          className="px-ds-6 pb-ds-6 text-neutral-300 text-ds-body-sm leading-relaxed"
        >
          {message}
        </div>

        {/* Actions - 44px touch targets */}
        <div className="flex flex-col-reverse sm:flex-row gap-ds-3 p-ds-6 pt-0">
          <button
            ref={cancelRef}
            onClick={onClose}
            disabled={isLoading}
            className="flex-1 min-h-[44px] px-ds-4 py-ds-3 text-ds-body-sm font-medium text-neutral-300 bg-neutral-800 hover:bg-neutral-700 rounded-ds-lg border border-neutral-600 transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-neutral-500 focus:ring-offset-2 focus:ring-offset-neutral-900 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {cancelText}
          </button>
          <button
            onClick={handleConfirm}
            disabled={isLoading || disabled}
            className={`flex-1 min-h-[44px] px-ds-4 py-ds-3 text-ds-body-sm font-medium text-white rounded-ds-lg transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-neutral-900 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-ds-2 ${variantStyle.button}`}
          >
            {isLoading && (
              <svg className="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
              </svg>
            )}
            {confirmText}
          </button>
        </div>
      </div>
    </div>
  )
}

/**
 * Hook for easily managing confirm modal state
 *
 * Usage:
 * ```tsx
 * const { isOpen, show, hide, props } = useConfirmModal({
 *   title: 'Delete item?',
 *   message: 'This cannot be undone.',
 *   onConfirm: async () => await deleteItem(),
 * })
 *
 * return (
 *   <>
 *     <button onClick={show}>Delete</button>
 *     <ConfirmModal {...props} />
 *   </>
 * )
 * ```
 */
export function useConfirmModal(config: Omit<ConfirmModalProps, 'isOpen' | 'onClose'>) {
  const [isOpen, setIsOpen] = useState(false)

  const show = () => setIsOpen(true)
  const hide = () => setIsOpen(false)

  const props: ConfirmModalProps = {
    ...config,
    isOpen,
    onClose: hide,
  }

  return { isOpen, show, hide, props }
}
