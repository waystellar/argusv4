/**
 * Favorites Hook - Persist fan's favorite vehicles
 *
 * Stores favorites in localStorage per event for persistence across sessions.
 * Provides add/remove/toggle operations and checks for favorite status.
 */
import { useState, useEffect, useCallback } from 'react'

const STORAGE_KEY_PREFIX = 'argus_favorites_'

export interface UseFavoritesReturn {
  favorites: Set<string>
  isFavorite: (vehicleId: string) => boolean
  toggleFavorite: (vehicleId: string) => void
  addFavorite: (vehicleId: string) => void
  removeFavorite: (vehicleId: string) => void
  clearFavorites: () => void
}

/**
 * Hook to manage favorite vehicles for an event
 * @param eventId - The event ID to scope favorites to
 */
export function useFavorites(eventId: string | undefined): UseFavoritesReturn {
  const [favorites, setFavorites] = useState<Set<string>>(new Set())

  // Load favorites from localStorage on mount or eventId change
  useEffect(() => {
    if (!eventId) {
      setFavorites(new Set())
      return
    }

    const storageKey = `${STORAGE_KEY_PREFIX}${eventId}`
    try {
      const stored = localStorage.getItem(storageKey)
      if (stored) {
        const parsed = JSON.parse(stored)
        if (Array.isArray(parsed)) {
          setFavorites(new Set(parsed))
        }
      }
    } catch (err) {
      console.warn('[useFavorites] Failed to load favorites:', err)
    }
  }, [eventId])

  // Save favorites to localStorage whenever they change
  const saveFavorites = useCallback((newFavorites: Set<string>) => {
    if (!eventId) return
    const storageKey = `${STORAGE_KEY_PREFIX}${eventId}`
    try {
      localStorage.setItem(storageKey, JSON.stringify(Array.from(newFavorites)))
    } catch (err) {
      console.warn('[useFavorites] Failed to save favorites:', err)
    }
  }, [eventId])

  const isFavorite = useCallback((vehicleId: string) => {
    return favorites.has(vehicleId)
  }, [favorites])

  const toggleFavorite = useCallback((vehicleId: string) => {
    setFavorites(prev => {
      const newFavorites = new Set(prev)
      if (newFavorites.has(vehicleId)) {
        newFavorites.delete(vehicleId)
      } else {
        newFavorites.add(vehicleId)
      }
      saveFavorites(newFavorites)
      return newFavorites
    })
  }, [saveFavorites])

  const addFavorite = useCallback((vehicleId: string) => {
    setFavorites(prev => {
      if (prev.has(vehicleId)) return prev
      const newFavorites = new Set(prev)
      newFavorites.add(vehicleId)
      saveFavorites(newFavorites)
      return newFavorites
    })
  }, [saveFavorites])

  const removeFavorite = useCallback((vehicleId: string) => {
    setFavorites(prev => {
      if (!prev.has(vehicleId)) return prev
      const newFavorites = new Set(prev)
      newFavorites.delete(vehicleId)
      saveFavorites(newFavorites)
      return newFavorites
    })
  }, [saveFavorites])

  const clearFavorites = useCallback(() => {
    setFavorites(new Set())
    if (eventId) {
      localStorage.removeItem(`${STORAGE_KEY_PREFIX}${eventId}`)
    }
  }, [eventId])

  return {
    favorites,
    isFavorite,
    toggleFavorite,
    addFavorite,
    removeFavorite,
    clearFavorites,
  }
}

/**
 * Star button component for favoriting vehicles
 */
export function FavoriteButton({
  vehicleId,
  isFavorite,
  onToggle,
  size = 'md',
  className = '',
}: {
  vehicleId: string
  isFavorite: boolean
  onToggle: (vehicleId: string) => void
  size?: 'sm' | 'md' | 'lg'
  className?: string
}) {
  const sizeClasses = {
    sm: 'w-6 h-6 min-w-[24px] min-h-[24px]',
    md: 'w-10 h-10 min-w-[40px] min-h-[40px]',
    lg: 'w-12 h-12 min-w-[48px] min-h-[48px]',
  }

  const iconSizes = {
    sm: 'w-4 h-4',
    md: 'w-5 h-5',
    lg: 'w-6 h-6',
  }

  return (
    <button
      onClick={(e) => {
        e.stopPropagation()
        e.preventDefault()
        onToggle(vehicleId)
      }}
      className={`${sizeClasses[size]} flex items-center justify-center rounded-full transition-all active:scale-90 ${
        isFavorite
          ? 'text-yellow-400 bg-yellow-400/20'
          : 'text-gray-500 hover:text-yellow-400 hover:bg-yellow-400/10'
      } ${className}`}
      aria-label={isFavorite ? 'Remove from favorites' : 'Add to favorites'}
    >
      <svg
        className={iconSizes[size]}
        fill={isFavorite ? 'currentColor' : 'none'}
        viewBox="0 0 24 24"
        stroke="currentColor"
        strokeWidth={2}
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"
        />
      </svg>
    </button>
  )
}
