/**
 * useSafeBack — navigate back safely with a fallback path.
 *
 * If the browser has real history (user navigated here from another page),
 * calls navigate(-1). Otherwise falls back to the provided path so the
 * user is never stranded on a blank tab.
 */
import { useCallback } from 'react'
import { useNavigate } from 'react-router-dom'

export function useSafeBack(fallbackPath: string): () => void {
  const navigate = useNavigate()

  return useCallback(() => {
    // React Router v6 stores an index in history state.
    // idx === 0 means this is the first entry (deep-link / new tab).
    const idx = (window.history.state as { idx?: number } | null)?.idx
    if (typeof idx === 'number' && idx > 0) {
      navigate(-1)
    } else {
      navigate(fallbackPath)
    }
  }, [navigate, fallbackPath])
}
