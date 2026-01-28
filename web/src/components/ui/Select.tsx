/**
 * Design System Select Component
 *
 * Styled select dropdown with consistent appearance.
 */
import { forwardRef, SelectHTMLAttributes } from 'react'

export interface SelectOption {
  value: string
  label: string
  disabled?: boolean
}

export interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label?: string
  error?: string
  hint?: string
  options: SelectOption[]
  placeholder?: string
}

const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ label, error, hint, options, placeholder, className = '', id, ...props }, ref) => {
    const selectId = id || (label ? label.toLowerCase().replace(/\s+/g, '-') : undefined)

    return (
      <div className="ds-stack-sm">
        {label && (
          <label
            htmlFor={selectId}
            className="text-ds-body-sm font-medium text-neutral-300"
          >
            {label}
          </label>
        )}
        <div className="relative">
          <select
            ref={ref}
            id={selectId}
            className={`
              ds-input w-full h-10 px-ds-3 pr-10 bg-neutral-800 border rounded-ds-md
              text-ds-body-sm text-neutral-50 appearance-none cursor-pointer
              transition-colors duration-ds-fast
              focus:outline-none focus:ring-2 focus:ring-accent-500 focus:border-transparent
              disabled:opacity-50 disabled:cursor-not-allowed
              ${error ? 'border-status-error focus:ring-status-error' : 'border-neutral-700 hover:border-neutral-600'}
              ${className}
            `}
            {...props}
          >
            {placeholder && (
              <option value="" disabled>
                {placeholder}
              </option>
            )}
            {options.map((option) => (
              <option
                key={option.value}
                value={option.value}
                disabled={option.disabled}
              >
                {option.label}
              </option>
            ))}
          </select>
          {/* Dropdown arrow */}
          <div className="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-neutral-500">
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          </div>
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

Select.displayName = 'Select'

export default Select
