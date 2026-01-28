/**
 * Theme store for managing Dark and Sunlight modes
 *
 * - Dark mode: Default, optimized for low-light viewing
 * - Sunlight mode: High contrast for outdoor visibility in bright sunlight
 *
 * Persists to localStorage and syncs with system preference.
 */
import { create } from 'zustand'
import { persist } from 'zustand/middleware'

export type Theme = 'dark' | 'sunlight' | 'system'
export type ResolvedTheme = 'dark' | 'sunlight'

interface ThemeState {
  theme: Theme
  resolvedTheme: ResolvedTheme
  setTheme: (theme: Theme) => void
}

// Resolve system preference
function getSystemTheme(): ResolvedTheme {
  if (typeof window === 'undefined') return 'dark'
  // Check for high ambient light (not a real API yet, but future-proofing)
  // For now, check time of day as a heuristic
  const hour = new Date().getHours()
  const isDaytime = hour >= 6 && hour < 18
  // Could also check prefers-color-scheme, but our app is always dark-based
  return isDaytime ? 'sunlight' : 'dark'
}

// Apply theme class to document
function applyTheme(resolvedTheme: ResolvedTheme) {
  if (typeof document === 'undefined') return

  const root = document.documentElement

  // Remove existing theme classes
  root.classList.remove('theme-dark', 'theme-sunlight')

  // Add new theme class
  root.classList.add(`theme-${resolvedTheme}`)

  // Update meta theme-color for mobile browsers
  const metaThemeColor = document.querySelector('meta[name="theme-color"]')
  if (metaThemeColor) {
    metaThemeColor.setAttribute(
      'content',
      resolvedTheme === 'sunlight' ? '#f5f5f5' : '#1a1a2e'
    )
  }
}

export const useThemeStore = create<ThemeState>()(
  persist(
    (set) => ({
      theme: 'system',
      resolvedTheme: getSystemTheme(),

      setTheme: (theme) => {
        const resolved: ResolvedTheme =
          theme === 'system' ? getSystemTheme() : theme
        applyTheme(resolved)
        set({ theme, resolvedTheme: resolved })
      },
    }),
    {
      name: 'argus-theme',
      onRehydrateStorage: () => (state) => {
        // Apply theme on rehydration
        if (state) {
          const resolved: ResolvedTheme =
            state.theme === 'system' ? getSystemTheme() : state.theme
          applyTheme(resolved)
          // Update resolved theme in case system changed
          if (state.theme === 'system') {
            state.resolvedTheme = resolved
          }
        }
      },
    }
  )
)

// Initialize theme on module load
if (typeof window !== 'undefined') {
  const stored = localStorage.getItem('argus-theme')
  if (stored) {
    try {
      const parsed = JSON.parse(stored)
      const theme = parsed.state?.theme || 'system'
      const resolved: ResolvedTheme = theme === 'system' ? getSystemTheme() : theme
      applyTheme(resolved)
    } catch {
      applyTheme(getSystemTheme())
    }
  } else {
    applyTheme(getSystemTheme())
  }
}

// Convenience functions
export const setTheme = (theme: Theme) => useThemeStore.getState().setTheme(theme)
export const getTheme = () => useThemeStore.getState().theme
export const getResolvedTheme = () => useThemeStore.getState().resolvedTheme
