/**
 * AppLoading - Global loading component for app shell
 *
 * UI-8: Professional loading screen with branded but subtle appearance.
 * Used for:
 * - Initial app load
 * - Route transitions (Suspense fallback)
 * - Auth verification
 *
 * Design: Neutral background, subtle spinner, minimal branding
 */

interface AppLoadingProps {
  /** Optional loading message */
  message?: string
  /** Show full screen overlay (default: true) */
  fullScreen?: boolean
  /** Show compact inline version */
  inline?: boolean
}

export default function AppLoading({
  message = 'Loading...',
  fullScreen = true,
  inline = false,
}: AppLoadingProps) {
  // Inline version for smaller contexts
  if (inline) {
    return (
      <div className="flex items-center justify-center gap-ds-3 py-ds-8">
        <Spinner size="sm" />
        <span className="text-ds-body-sm text-neutral-400">{message}</span>
      </div>
    )
  }

  // Full screen loading
  return (
    <div
      className={`${
        fullScreen ? 'min-h-screen' : 'h-full'
      } bg-neutral-950 flex items-center justify-center`}
    >
      <div className="flex flex-col items-center gap-ds-4">
        {/* Logo placeholder - subtle branding */}
        <div className="w-12 h-12 rounded-ds-lg bg-neutral-900 border border-neutral-800 flex items-center justify-center">
          <svg
            className="w-6 h-6 text-accent-500"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M13 10V3L4 14h7v7l9-11h-7z"
            />
          </svg>
        </div>

        {/* Spinner */}
        <Spinner size="md" />

        {/* Message */}
        <p className="text-ds-body-sm text-neutral-400">{message}</p>
      </div>
    </div>
  )
}

/**
 * Spinner - Subtle loading indicator
 */
interface SpinnerProps {
  size?: 'sm' | 'md' | 'lg'
  className?: string
}

export function Spinner({ size = 'md', className = '' }: SpinnerProps) {
  const sizeClasses = {
    sm: 'h-5 w-5 border-2',
    md: 'h-8 w-8 border-2',
    lg: 'h-12 w-12 border-3',
  }

  return (
    <div
      className={`animate-spin rounded-full border-neutral-700 border-t-accent-500 ${sizeClasses[size]} ${className}`}
      role="status"
      aria-label="Loading"
    />
  )
}

/**
 * PageSkeleton - Generic page skeleton for route transitions
 */
export function PageSkeleton() {
  return (
    <div className="min-h-screen bg-neutral-950 animate-fade-in">
      {/* Header skeleton */}
      <header className="h-14 bg-neutral-900 border-b border-neutral-800 flex items-center px-ds-4">
        <div className="skeleton bg-neutral-800 rounded-ds-sm h-6 w-32" />
        <div className="flex-1" />
        <div className="skeleton bg-neutral-800 rounded-ds-sm h-8 w-8" />
      </header>

      {/* Content skeleton */}
      <div className="p-ds-4 space-y-ds-4">
        {/* Title area */}
        <div className="skeleton bg-neutral-800 rounded-ds-sm h-8 w-48" />
        <div className="skeleton bg-neutral-800 rounded-ds-sm h-4 w-64" />

        {/* Card skeletons */}
        <div className="grid gap-ds-4 md:grid-cols-2 lg:grid-cols-3 mt-ds-6">
          {[1, 2, 3].map((i) => (
            <div
              key={i}
              className="bg-neutral-900 rounded-ds-lg p-ds-4 border border-neutral-800"
            >
              <div className="skeleton bg-neutral-800 rounded-ds-sm h-5 w-24 mb-ds-3" />
              <div className="skeleton bg-neutral-800 rounded-ds-sm h-12 w-full mb-ds-2" />
              <div className="skeleton bg-neutral-800 rounded-ds-sm h-4 w-32" />
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
