/**
 * ThemeToggle - Switch between Dark and Sunlight modes
 *
 * UI-20: Migrated to design system tokens (neutral-*, status-*, accent-*, ds-*)
 * Sunlight mode provides high contrast for outdoor visibility
 * in bright sunlight conditions (e.g., desert racing events).
 */
import { useThemeStore, type Theme } from '../../stores/themeStore'

interface ThemeToggleProps {
  /** Show text labels */
  showLabels?: boolean
  /** Size variant */
  size?: 'sm' | 'md'
  /** Additional CSS classes */
  className?: string
}

export default function ThemeToggle({
  showLabels = false,
  size = 'md',
  className = '',
}: ThemeToggleProps) {
  const theme = useThemeStore((state) => state.theme)
  const setTheme = useThemeStore((state) => state.setTheme)

  const handleToggle = () => {
    // Cycle through: dark -> sunlight -> dark
    // (system mode available but not in toggle cycle for simplicity)
    const nextTheme: Theme = theme === 'dark' ? 'sunlight' : 'dark'
    setTheme(nextTheme)
  }

  const isSunlight = theme === 'sunlight'

  const sizeClasses = {
    sm: 'w-10 h-10 text-ds-body-sm',
    md: 'w-11 h-11 text-ds-body',
  }

  return (
    <button
      onClick={handleToggle}
      className={`
        ${sizeClasses[size]}
        flex items-center justify-center gap-ds-2
        rounded-ds-lg transition-all duration-ds-fast
        ${isSunlight
          ? 'bg-status-warning text-neutral-950 hover:bg-status-warning/90'
          : 'bg-neutral-800 hover:bg-neutral-700 text-neutral-400 hover:text-white'
        }
        border border-neutral-600
        ${className}
      `}
      aria-label={isSunlight ? 'Switch to dark mode' : 'Switch to sunlight mode'}
      title={isSunlight ? 'Switch to dark mode' : 'Switch to sunlight mode (high contrast)'}
    >
      {isSunlight ? (
        <SunIcon className="w-5 h-5" />
      ) : (
        <MoonIcon className="w-5 h-5" />
      )}
      {showLabels && (
        <span className="font-medium">
          {isSunlight ? 'Sunlight' : 'Dark'}
        </span>
      )}
    </button>
  )
}

function SunIcon({ className }: { className?: string }) {
  return (
    <svg className={className} fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"
      />
    </svg>
  )
}

function MoonIcon({ className }: { className?: string }) {
  return (
    <svg className={className} fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"
      />
    </svg>
  )
}

/**
 * ThemeSelector - Full theme selector with all options
 *
 * Shows Dark, Sunlight, and System options in a dropdown or row.
 */
export function ThemeSelector({ className = '' }: { className?: string }) {
  const theme = useThemeStore((state) => state.theme)
  const setTheme = useThemeStore((state) => state.setTheme)

  const options: { value: Theme; label: string; icon: JSX.Element }[] = [
    {
      value: 'dark',
      label: 'Dark',
      icon: <MoonIcon className="w-4 h-4" />,
    },
    {
      value: 'sunlight',
      label: 'Sunlight',
      icon: <SunIcon className="w-4 h-4" />,
    },
    {
      value: 'system',
      label: 'Auto',
      icon: (
        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
        </svg>
      ),
    },
  ]

  return (
    <div className={`flex gap-ds-1 p-ds-1 bg-neutral-800 rounded-ds-lg ${className}`}>
      {options.map((option) => (
        <button
          key={option.value}
          onClick={() => setTheme(option.value)}
          className={`
            min-h-[44px] min-w-[44px] px-ds-3 flex items-center justify-center gap-ds-2 rounded-ds-md transition-colors duration-ds-fast
            ${theme === option.value
              ? 'bg-accent-600 text-white'
              : 'text-neutral-400 hover:text-white hover:bg-neutral-700'
            }
          `}
          aria-pressed={theme === option.value}
        >
          {option.icon}
          <span className="text-ds-body-sm font-medium hidden sm:inline">{option.label}</span>
        </button>
      ))}
    </div>
  )
}
