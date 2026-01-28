/**
 * App header with optional back button
 * Updated to use design system tokens
 */
interface HeaderProps {
  title: string
  subtitle?: string
  showBack?: boolean
  onBack?: () => void
}

export default function Header({ title, subtitle, showBack, onBack }: HeaderProps) {
  return (
    <header className="bg-neutral-850 border-b border-neutral-700 px-ds-4 py-ds-3 safe-area-top">
      <div className="flex items-center gap-ds-3">
        {showBack && (
          <button
            onClick={onBack}
            className="w-10 h-10 flex items-center justify-center rounded-full hover:bg-neutral-800 transition-colors duration-ds-fast"
            aria-label="Go back"
          >
            <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>
        )}
        <div className="flex-1 min-w-0">
          <h1 className="text-ds-heading text-neutral-50 truncate">{title}</h1>
          {subtitle && (
            <div className={`text-ds-caption uppercase tracking-wide ${
              subtitle === 'LIVE' ? 'text-status-error' : 'text-neutral-400'
            }`}>
              {subtitle === 'LIVE' && (
                <span className="inline-block w-2 h-2 bg-status-error rounded-full mr-1.5 animate-pulse" />
              )}
              {subtitle}
            </div>
          )}
        </div>
      </div>
    </header>
  )
}
