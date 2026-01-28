/**
 * Reusable skeleton loading components
 *
 * FIXED: P1-1 - Added skeleton screens for better initial load experience
 * UPDATED: Now uses design system tokens for consistent styling
 *
 * These match the exact dimensions of the final content to prevent layout shift.
 */

interface SkeletonProps {
  className?: string
}

// Basic skeleton shapes - using design tokens
export function SkeletonRect({ className = '' }: SkeletonProps) {
  return <div className={`skeleton bg-neutral-800 rounded-ds-sm ${className}`} />
}

export function SkeletonCircle({ className = '' }: SkeletonProps) {
  return <div className={`skeleton bg-neutral-800 rounded-full ${className}`} />
}

export function SkeletonText({ className = '' }: SkeletonProps) {
  return <div className={`skeleton-text bg-neutral-800 rounded-ds-sm h-4 ${className}`} />
}

/**
 * Leaderboard row skeleton - matches LeaderboardRow layout exactly
 */
export function LeaderboardRowSkeleton() {
  return (
    <div className="w-full px-ds-2 py-ds-3 sm:py-ds-2 flex items-center gap-ds-3">
      {/* Position badge skeleton */}
      <div className="w-10 h-10 sm:w-8 sm:h-8 rounded-full skeleton bg-neutral-800 shrink-0" />

      {/* Vehicle info skeleton */}
      <div className="flex-1 min-w-0">
        <div className="flex items-baseline gap-ds-2">
          <div className="skeleton bg-neutral-800 rounded-ds-sm h-5 w-12" />
          <div className="hidden sm:block skeleton bg-neutral-800 rounded-ds-sm h-4 w-24" />
        </div>
        <div className="sm:hidden skeleton bg-neutral-800 rounded-ds-sm h-3 w-20 mt-ds-1" />
      </div>

      {/* Gap to Leader skeleton */}
      <div className="text-right shrink-0">
        <div className="skeleton bg-neutral-800 rounded-ds-sm h-5 w-16 mb-ds-1" />
        <div className="skeleton bg-neutral-800 rounded-ds-sm h-3 w-12" />
      </div>

      {/* Chevron placeholder */}
      <div className="w-4 h-4 sm:w-5 sm:h-5 shrink-0" />
    </div>
  )
}

/**
 * Full leaderboard skeleton with multiple rows
 */
export function LeaderboardSkeleton({ count = 5 }: { count?: number }) {
  return (
    <div className="divide-y divide-neutral-800">
      {Array.from({ length: count }).map((_, i) => (
        <LeaderboardRowSkeleton key={i} />
      ))}
    </div>
  )
}

/**
 * Map placeholder skeleton
 */
export function MapSkeleton() {
  return (
    <div className="absolute inset-0 bg-neutral-900 flex flex-col items-center justify-center">
      {/* Simulated map background */}
      <div className="absolute inset-0 bg-neutral-850 opacity-50" />

      {/* Loading indicator */}
      <div className="relative z-10 flex flex-col items-center gap-ds-4">
        {/* Pulsing map marker icons */}
        <div className="flex gap-ds-6">
          <div className="w-4 h-4 rounded-full bg-accent-500/50 animate-pulse" />
          <div className="w-4 h-4 rounded-full bg-status-warning/50 animate-pulse delay-100" />
          <div className="w-4 h-4 rounded-full bg-neutral-500/50 animate-pulse delay-200" />
        </div>

        <div className="text-neutral-400 text-ds-body-sm">Loading map...</div>

        {/* Simulated vehicle markers scattered */}
        <div className="absolute inset-0 pointer-events-none">
          {[
            { top: '20%', left: '30%' },
            { top: '40%', left: '60%' },
            { top: '60%', left: '25%' },
            { top: '35%', left: '75%' },
            { top: '70%', left: '50%' },
          ].map((pos, i) => (
            <div
              key={i}
              className="absolute w-3 h-3 rounded-full bg-neutral-600/30 animate-pulse"
              style={{ top: pos.top, left: pos.left, animationDelay: `${i * 150}ms` }}
            />
          ))}
        </div>
      </div>
    </div>
  )
}

/**
 * Video placeholder skeleton
 */
export function VideoSkeleton() {
  return (
    <div className="w-full h-full bg-neutral-950 flex items-center justify-center">
      <div className="flex flex-col items-center gap-ds-3">
        {/* Play button icon skeleton */}
        <div className="w-16 h-16 rounded-full bg-neutral-700/50 flex items-center justify-center animate-pulse">
          <svg className="w-8 h-8 text-neutral-500" fill="currentColor" viewBox="0 0 24 24">
            <path d="M8 5v14l11-7z" />
          </svg>
        </div>
        <div className="text-neutral-500 text-ds-body-sm">Loading video...</div>
      </div>
    </div>
  )
}

/**
 * Vehicle header skeleton
 */
export function VehicleHeaderSkeleton() {
  return (
    <div className="flex items-center gap-ds-3 p-ds-4">
      <div className="skeleton bg-neutral-800 rounded-ds-sm w-16 h-8" /> {/* Vehicle number */}
      <div className="skeleton bg-neutral-800 rounded-ds-sm w-32 h-4" /> {/* Team name */}
    </div>
  )
}

/**
 * Position badge skeleton
 */
export function PositionBadgeSkeleton() {
  return (
    <div className="glass px-ds-4 py-ds-3 flex items-center justify-between border-b border-neutral-700">
      <div className="flex items-center gap-ds-3">
        <div className="skeleton bg-neutral-800 rounded-ds-sm w-14 h-10" /> {/* Position */}
        <div className="skeleton bg-neutral-800 rounded-ds-sm w-20 h-4" /> {/* Checkpoint */}
      </div>
      <div className="text-right">
        <div className="skeleton bg-neutral-800 rounded-ds-sm w-20 h-6 mb-ds-1" /> {/* Delta */}
        <div className="skeleton bg-neutral-800 rounded-ds-sm w-14 h-3" /> {/* Label */}
      </div>
    </div>
  )
}

/**
 * Full event page skeleton (combines map + leaderboard)
 */
export function EventPageSkeleton() {
  return (
    <div className="h-full flex flex-col viewport-fixed">
      {/* Header skeleton */}
      <div className="h-14 bg-neutral-850 border-b border-neutral-700 flex items-center px-ds-4">
        <div className="skeleton bg-neutral-800 rounded-ds-sm w-40 h-6" />
      </div>

      {/* Map skeleton */}
      <div className="flex-1 relative">
        <MapSkeleton />
      </div>

      {/* Leaderboard skeleton */}
      <div className="bg-neutral-850 border-t border-neutral-700 max-h-[40vh] overflow-hidden safe-area-bottom">
        <div className="p-ds-2">
          <div className="skeleton bg-neutral-800 rounded-ds-sm h-4 w-24 mx-ds-2 my-ds-2" />
          <LeaderboardSkeleton count={4} />
        </div>
      </div>
    </div>
  )
}

/**
 * Admin health panel skeleton
 */
export function SkeletonHealthPanel() {
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-ds-4">
      {Array.from({ length: 4 }).map((_, i) => (
        <div key={i} className="bg-neutral-800/50 rounded-ds-lg p-ds-4">
          <div className="flex items-center gap-ds-2 mb-ds-2">
            <div className="skeleton bg-neutral-700 w-2.5 h-2.5 rounded-full" />
            <div className="skeleton bg-neutral-700 rounded-ds-sm h-4 w-16" />
          </div>
          <div className="skeleton bg-neutral-700 rounded-ds-sm h-8 w-12 mb-ds-1" />
          <div className="skeleton bg-neutral-700 rounded-ds-sm h-3 w-20" />
        </div>
      ))}
    </div>
  )
}

/**
 * Admin event list item skeleton
 */
export function SkeletonEventItem() {
  return (
    <div className="bg-neutral-800/50 rounded-ds-lg p-ds-4">
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-ds-3">
            <div className="skeleton bg-neutral-700 rounded-ds-sm h-5 w-40" />
            <div className="skeleton bg-neutral-700 h-5 w-16 rounded-full" />
          </div>
          <div className="skeleton bg-neutral-700 rounded-ds-sm h-4 w-56 mt-ds-2" />
        </div>
        <div className="skeleton bg-neutral-700 rounded-ds-sm w-5 h-5" />
      </div>
    </div>
  )
}

/**
 * Admin vehicle card skeleton
 */
export function SkeletonVehicleCard() {
  return (
    <div className="p-ds-4">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-ds-2">
            <div className="skeleton bg-neutral-700 rounded-ds-sm h-6 w-12" />
            <div className="skeleton bg-neutral-700 h-5 w-20 rounded-ds-md" />
          </div>
          <div className="skeleton bg-neutral-700 rounded-ds-sm h-4 w-32 mt-ds-2" />
          <div className="skeleton bg-neutral-700 rounded-ds-sm h-3 w-24 mt-ds-1" />
        </div>
      </div>
      <div className="mt-ds-3 p-ds-2 bg-neutral-900 rounded-ds-md">
        <div className="flex items-center justify-between mb-ds-1">
          <div className="skeleton bg-neutral-700 rounded-ds-sm h-3 w-16" />
          <div className="flex gap-ds-2">
            <div className="skeleton bg-neutral-700 rounded-ds-sm h-3 w-10" />
            <div className="skeleton bg-neutral-700 rounded-ds-sm h-3 w-10" />
            <div className="skeleton bg-neutral-700 rounded-ds-sm h-3 w-16" />
          </div>
        </div>
        <div className="skeleton bg-neutral-700 rounded-ds-sm h-3 w-full" />
      </div>
    </div>
  )
}
