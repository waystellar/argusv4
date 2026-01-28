/**
 * Design System Card Component
 *
 * Versatile card container with variants for different contexts.
 * Supports interactive (clickable) and elevated states.
 */
import { forwardRef, HTMLAttributes, ReactNode } from 'react'

export interface CardProps extends HTMLAttributes<HTMLDivElement> {
  variant?: 'default' | 'elevated' | 'outlined'
  interactive?: boolean
  padding?: 'none' | 'sm' | 'md' | 'lg'
  children: ReactNode
}

const Card = forwardRef<HTMLDivElement, CardProps>(
  ({ variant = 'default', interactive = false, padding = 'md', children, className = '', ...props }, ref) => {
    const baseClasses = 'rounded-ds-lg transition-colors duration-ds-fast'

    const variantClasses = {
      default: 'ds-card bg-neutral-850 border border-neutral-800',
      elevated: 'ds-card-elevated bg-neutral-800 border border-neutral-700 shadow-ds-dark-md',
      outlined: 'bg-transparent border border-neutral-700',
    }

    const paddingClasses = {
      none: '',
      sm: 'p-ds-3',
      md: 'p-ds-4',
      lg: 'p-ds-6',
    }

    const interactiveClasses = interactive
      ? 'ds-card-interactive cursor-pointer hover:bg-neutral-800 hover:border-neutral-700 active:bg-neutral-750'
      : ''

    const Component = interactive ? 'button' : 'div'

    return (
      <Component
        ref={ref as any}
        className={`${baseClasses} ${variantClasses[variant]} ${paddingClasses[padding]} ${interactiveClasses} ${className}`}
        {...(props as any)}
      >
        {children}
      </Component>
    )
  }
)

Card.displayName = 'Card'

// Card Header subcomponent
export interface CardHeaderProps extends HTMLAttributes<HTMLDivElement> {
  title: string
  subtitle?: string
  action?: ReactNode
}

export function CardHeader({ title, subtitle, action, className = '', ...props }: CardHeaderProps) {
  return (
    <div className={`flex items-start justify-between gap-ds-4 ${className}`} {...props}>
      <div className="flex-1 min-w-0">
        <h3 className="text-ds-heading text-neutral-50 truncate">{title}</h3>
        {subtitle && (
          <p className="text-ds-body-sm text-neutral-400 mt-ds-1">{subtitle}</p>
        )}
      </div>
      {action && <div className="flex-shrink-0">{action}</div>}
    </div>
  )
}

// Card Content subcomponent
export interface CardContentProps extends HTMLAttributes<HTMLDivElement> {
  children: ReactNode
}

export function CardContent({ children, className = '', ...props }: CardContentProps) {
  return (
    <div className={`text-ds-body-sm text-neutral-300 ${className}`} {...props}>
      {children}
    </div>
  )
}

// Card Footer subcomponent
export interface CardFooterProps extends HTMLAttributes<HTMLDivElement> {
  children: ReactNode
}

export function CardFooter({ children, className = '', ...props }: CardFooterProps) {
  return (
    <div className={`flex items-center gap-ds-3 pt-ds-4 border-t border-neutral-800 ${className}`} {...props}>
      {children}
    </div>
  )
}

export default Card
