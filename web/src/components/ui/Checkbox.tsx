/**
 * Design System Checkbox Component
 *
 * Styled checkbox with label support.
 * Meets 44px minimum touch target requirement.
 */
import { forwardRef, InputHTMLAttributes } from 'react'

export interface CheckboxProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> {
  label?: string
  description?: string
  error?: string
}

const Checkbox = forwardRef<HTMLInputElement, CheckboxProps>(
  ({ label, description, error, checked, disabled, className = '', id, ...props }, ref) => {
    const checkboxId = id || (label ? label.toLowerCase().replace(/\s+/g, '-') : undefined)

    return (
      <div className="ds-stack-sm">
        <label
          htmlFor={checkboxId}
          className={`
            inline-flex items-start gap-ds-3 min-h-touch cursor-pointer
            ${disabled ? 'opacity-50 cursor-not-allowed' : ''}
            ${className}
          `}
        >
          <div className="relative flex-shrink-0 mt-0.5">
            <input
              ref={ref}
              type="checkbox"
              id={checkboxId}
              checked={checked}
              disabled={disabled}
              className="sr-only peer"
              {...props}
            />
            {/* Custom checkbox */}
            <div
              className={`
                w-5 h-5 rounded-ds-sm border-2 transition-colors duration-ds-fast
                flex items-center justify-center
                ${checked
                  ? 'bg-accent-600 border-accent-600'
                  : error
                    ? 'bg-neutral-800 border-status-error'
                    : 'bg-neutral-800 border-neutral-600 hover:border-neutral-500'
                }
                peer-focus-visible:ring-2 peer-focus-visible:ring-accent-500 peer-focus-visible:ring-offset-2 peer-focus-visible:ring-offset-neutral-900
              `}
            >
              {/* Checkmark */}
              {checked && (
                <svg className="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                </svg>
              )}
            </div>
          </div>
          {(label || description) && (
            <div className="flex flex-col">
              {label && (
                <span className="text-ds-body-sm font-medium text-neutral-50">
                  {label}
                </span>
              )}
              {description && (
                <span className="text-ds-caption text-neutral-500">
                  {description}
                </span>
              )}
            </div>
          )}
        </label>
        {error && (
          <p className="text-ds-caption text-status-error ml-8">{error}</p>
        )}
      </div>
    )
  }
)

Checkbox.displayName = 'Checkbox'

export default Checkbox
