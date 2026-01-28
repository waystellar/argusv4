/**
 * Design System Button Component
 *
 * Variants: primary, secondary, ghost, danger
 * Sizes: sm, md, lg
 * States: loading, disabled
 *
 * Uses design tokens from tailwind.config.js and index.css
 */
import { forwardRef, ButtonHTMLAttributes, ReactNode } from 'react'

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  size?: 'sm' | 'md' | 'lg'
  loading?: boolean
  children: ReactNode
}

const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ variant = 'primary', size = 'md', loading = false, disabled, children, className = '', ...props }, ref) => {
    const baseClasses = 'ds-btn inline-flex items-center justify-center font-medium transition-colors duration-ds-fast focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent-500 focus-visible:ring-offset-2 focus-visible:ring-offset-neutral-900 disabled:opacity-50 disabled:pointer-events-none'

    const variantClasses = {
      primary: 'ds-btn-primary bg-accent-600 text-white hover:bg-accent-700 active:bg-accent-800',
      secondary: 'ds-btn-secondary bg-neutral-800 text-neutral-50 border border-neutral-700 hover:bg-neutral-750 active:bg-neutral-700',
      ghost: 'bg-transparent text-neutral-400 hover:text-neutral-50 hover:bg-neutral-800 active:bg-neutral-750',
      danger: 'ds-btn-danger bg-status-error text-white hover:bg-red-600 active:bg-red-700',
    }

    const sizeClasses = {
      sm: 'ds-btn-sm h-8 px-3 text-ds-body-sm rounded-ds-sm gap-ds-1',
      md: 'h-10 px-ds-4 text-ds-body-sm rounded-ds-md gap-ds-2',
      lg: 'ds-btn-lg h-12 px-ds-6 text-ds-body rounded-ds-md gap-ds-2',
    }

    const isDisabled = disabled || loading

    return (
      <button
        ref={ref}
        disabled={isDisabled}
        className={`${baseClasses} ${variantClasses[variant]} ${sizeClasses[size]} ${className}`}
        {...props}
      >
        {loading && (
          <svg
            className="animate-spin -ml-1 mr-2 h-4 w-4"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
          >
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            />
          </svg>
        )}
        {children}
      </button>
    )
  }
)

Button.displayName = 'Button'

export default Button
