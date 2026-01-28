/**
 * Design System UI Components
 *
 * All reusable UI components following the Argus design system.
 * Import from here for consistent component usage.
 */

// Button
export { default as Button } from './Button'
export type { ButtonProps } from './Button'

// Form Controls
export { default as Input } from './Input'
export type { InputProps } from './Input'

export { default as Select } from './Select'
export type { SelectProps, SelectOption } from './Select'

export { default as Toggle } from './Toggle'
export type { ToggleProps } from './Toggle'

export { default as Checkbox } from './Checkbox'
export type { CheckboxProps } from './Checkbox'

// Layout
export { default as Card, CardHeader, CardContent, CardFooter } from './Card'
export type { CardProps, CardHeaderProps, CardContentProps, CardFooterProps } from './Card'

// Feedback
export { default as Badge, OnlineBadge, OfflineBadge, StreamingBadge, StaleBadge, NoDataBadge } from './Badge'
export type { BadgeProps } from './Badge'

export { default as Alert, InfoAlert, SuccessAlert, WarningAlert, ErrorAlert } from './Alert'
export type { AlertProps } from './Alert'

export {
  default as EmptyState,
  NoEventsState,
  NoVehiclesState,
  NoDataState,
  ConnectionErrorState,
} from './EmptyState'
export type { EmptyStateProps } from './EmptyState'
