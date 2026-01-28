/**
 * Common UI Components - PR-1: UX Foundation Components
 *
 * Export all reusable UI primitives for easy imports:
 * import { StatusPill, ConfirmModal, ThemeToggle } from '../components/common'
 */

// Status indicators
export { default as StatusPill, getEventStatusVariant, getConnectionVariant, getDataFreshnessVariant } from './StatusPill'
export { default as DataFreshnessBadge, useDataFreshness } from './DataFreshnessBadge'
export { default as ConnectionStatus } from './ConnectionStatus'
export { default as SystemHealthIndicator } from './SystemHealthIndicator'

// Modals and overlays
export { default as ConfirmModal, useConfirmModal } from './ConfirmModal'

// Notifications
export { Toast, ToastContainer } from './Toast'
export type { ToastData, ToastType } from './Toast'

// Theme
export { default as ThemeToggle, ThemeSelector } from './ThemeToggle'

// Navigation
export { default as Header } from './Header'
export { default as PageHeader } from './PageHeader'
export { default as BottomNav } from './BottomNav'

// Loading states
export * from './Skeleton'
export { default as AppLoading, Spinner, PageSkeleton } from './AppLoading'

// Error handling
export { default as ErrorBoundary, ErrorFallback } from './ErrorBoundary'
export { default as NotFound } from './NotFound'
