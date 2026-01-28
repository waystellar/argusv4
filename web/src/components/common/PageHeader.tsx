/**
 * PageHeader — reusable page header with Back, Title, and Home controls.
 *
 * Matches existing Header.tsx design tokens (neutral-850, border-neutral-700,
 * ds-* spacing, safe-area-top) but adds:
 *  - Back button via useSafeBack (left side)
 *  - Home icon linking to "/" (right side)
 *  - Optional rightSlot for extra controls
 */
import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { useSafeBack } from '../../hooks/useSafeBack'

interface PageHeaderProps {
  title: string
  subtitle?: string
  /** Fallback path for the Back button. Omit to hide Back. */
  backTo?: string
  /** Accessible label for the back button. */
  backLabel?: string
  /** Show Home icon linking to "/" (default true). */
  showHome?: boolean
  /** Optional content rendered on the right side, before Home. */
  rightSlot?: ReactNode
}

export default function PageHeader({
  title,
  subtitle,
  backTo,
  backLabel = 'Back',
  showHome = true,
  rightSlot,
}: PageHeaderProps) {
  const navigate = useNavigate()
  // Always call the hook (rules of hooks) — only used when backTo is provided.
  const goBack = useSafeBack(backTo ?? '/')

  return (
    <header className="bg-neutral-850 border-b border-neutral-700 px-ds-4 py-ds-3 safe-area-top flex-shrink-0">
      <div className="flex items-center gap-ds-3">
        {/* Back button (left) */}
        {backTo != null && (
          <button
            onClick={goBack}
            className="min-w-[44px] min-h-[44px] -ml-ds-2 flex items-center justify-center rounded-full text-neutral-400 hover:text-neutral-50 hover:bg-neutral-800 transition-colors duration-ds-fast focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-400"
            aria-label={backLabel}
          >
            <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>
        )}

        {/* Title (center / fill) */}
        <div className="flex-1 min-w-0">
          <h1 className="text-ds-heading text-neutral-50 truncate">{title}</h1>
          {subtitle && (
            <div className="text-ds-caption text-neutral-400 truncate mt-ds-0.5">
              {subtitle}
            </div>
          )}
        </div>

        {/* Right slot */}
        {rightSlot}

        {/* Home button (right) */}
        {showHome && (
          <button
            onClick={() => navigate('/')}
            className="min-w-[44px] min-h-[44px] flex items-center justify-center rounded-full text-neutral-400 hover:text-neutral-50 hover:bg-neutral-800 transition-colors duration-ds-fast focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-400"
            aria-label="Home"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-4 0a1 1 0 01-1-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 01-1 1h-2z" />
            </svg>
          </button>
        )}
      </div>
    </header>
  )
}
