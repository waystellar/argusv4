/**
 * Design System Toggle/Switch Component
 *
 * iOS-style toggle switch for boolean settings.
 * Meets 44px minimum touch target requirement.
 */
import { forwardRef, InputHTMLAttributes } from 'react'

export interface ToggleProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type' | 'size'> {
  label?: string
  description?: string
  size?: 'sm' | 'md'
}

const Toggle = forwardRef<HTMLInputElement, ToggleProps>(
  ({ label, description, size = 'md', checked, disabled, className = '', id, ...props }, ref) => {
    const toggleId = id || (label ? label.toLowerCase().replace(/\s+/g, '-') : undefined)

    const sizeClasses = {
      sm: {
        track: 'w-9 h-5',
        thumb: 'w-4 h-4',
        translate: 'translate-x-4',
      },
      md: {
        track: 'w-11 h-6',
        thumb: 'w-5 h-5',
        translate: 'translate-x-5',
      },
    }

    const sizes = sizeClasses[size]

    return (
      <label
        htmlFor={toggleId}
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
            id={toggleId}
            checked={checked}
            disabled={disabled}
            className="sr-only peer"
            {...props}
          />
          {/* Track */}
          <div
            className={`
              ${sizes.track} rounded-ds-full transition-colors duration-ds-fast
              ${checked ? 'bg-accent-600' : 'bg-neutral-700'}
              peer-focus-visible:ring-2 peer-focus-visible:ring-accent-500 peer-focus-visible:ring-offset-2 peer-focus-visible:ring-offset-neutral-900
            `}
          />
          {/* Thumb */}
          <div
            className={`
              absolute top-0.5 left-0.5 ${sizes.thumb} rounded-full bg-white shadow-ds-sm
              transition-transform duration-ds-fast
              ${checked ? sizes.translate : 'translate-x-0'}
            `}
          />
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
    )
  }
)

Toggle.displayName = 'Toggle'

export default Toggle
