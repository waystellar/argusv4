/**
 * Design System Input Component
 *
 * Text input with consistent styling and states.
 * Supports error state and helper text.
 */
import { forwardRef, InputHTMLAttributes, ReactNode } from 'react'

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string
  error?: string
  hint?: string
  leftIcon?: ReactNode
  rightIcon?: ReactNode
}

const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ label, error, hint, leftIcon, rightIcon, className = '', id, ...props }, ref) => {
    const inputId = id || (label ? label.toLowerCase().replace(/\s+/g, '-') : undefined)

    return (
      <div className="ds-stack-sm">
        {label && (
          <label
            htmlFor={inputId}
            className="text-ds-body-sm font-medium text-neutral-300"
          >
            {label}
          </label>
        )}
        <div className="relative">
          {leftIcon && (
            <div className="absolute left-3 top-1/2 -translate-y-1/2 text-neutral-500">
              {leftIcon}
            </div>
          )}
          <input
            ref={ref}
            id={inputId}
            className={`
              ds-input w-full h-10 px-ds-3 bg-neutral-800 border rounded-ds-md
              text-ds-body-sm text-neutral-50 placeholder:text-neutral-500
              transition-colors duration-ds-fast
              focus:outline-none focus:ring-2 focus:ring-accent-500 focus:border-transparent
              disabled:opacity-50 disabled:cursor-not-allowed
              ${error ? 'border-status-error focus:ring-status-error' : 'border-neutral-700 hover:border-neutral-600'}
              ${leftIcon ? 'pl-10' : ''}
              ${rightIcon ? 'pr-10' : ''}
              ${className}
            `}
            {...props}
          />
          {rightIcon && (
            <div className="absolute right-3 top-1/2 -translate-y-1/2 text-neutral-500">
              {rightIcon}
            </div>
          )}
        </div>
        {error && (
          <p className="text-ds-caption text-status-error">{error}</p>
        )}
        {hint && !error && (
          <p className="text-ds-caption text-neutral-500">{hint}</p>
        )}
      </div>
    )
  }
)

Input.displayName = 'Input'

export default Input
