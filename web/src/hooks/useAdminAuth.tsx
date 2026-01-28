/**
 * Admin Authentication Hook
 *
 * Manages admin session state and provides auth utilities.
 */
import { useState, useEffect, useCallback } from 'react'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

interface AuthStatus {
  auth_required: boolean
  authenticated: boolean
  message: string
}

interface UseAdminAuth {
  isAuthenticated: boolean
  isAuthRequired: boolean
  isLoading: boolean
  error: string | null
  checkAuth: () => Promise<boolean>
  logout: () => Promise<void>
}

export function useAdminAuth(): UseAdminAuth {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isAuthRequired, setIsAuthRequired] = useState(true)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const checkAuth = useCallback(async (): Promise<boolean> => {
    try {
      setIsLoading(true)
      setError(null)

      // Get token from localStorage if exists (backup to cookie)
      const token = localStorage.getItem('admin_token')
      const headers: HeadersInit = {}
      if (token) {
        headers['Authorization'] = `Bearer ${token}`
      }

      const response = await fetch(`${API_BASE}/admin/auth/status`, {
        credentials: 'include',
        headers,
      })

      // Handle server errors gracefully - allow access on 5xx
      if (response.status >= 500) {
        console.warn(`Auth status returned ${response.status}, allowing access`)
        setIsAuthRequired(false)
        setIsAuthenticated(true)
        return true
      }

      if (!response.ok) {
        throw new Error('Failed to check auth status')
      }

      // Verify response is JSON before parsing (handles HTML error pages)
      const contentType = response.headers.get('content-type')
      if (!contentType || !contentType.includes('application/json')) {
        console.warn('Auth status returned non-JSON response, allowing access')
        setIsAuthRequired(false)
        setIsAuthenticated(true)
        return true
      }

      const data: AuthStatus = await response.json()

      setIsAuthRequired(data.auth_required)
      setIsAuthenticated(data.authenticated || !data.auth_required)

      return data.authenticated || !data.auth_required
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Auth check failed')
      // On network errors, allow access rather than blocking
      setIsAuthenticated(true)
      setIsAuthRequired(false)
      return true
    } finally {
      setIsLoading(false)
    }
  }, [])

  const logout = useCallback(async () => {
    try {
      // Get token for header
      const token = localStorage.getItem('admin_token')
      const headers: HeadersInit = {}
      if (token) {
        headers['Authorization'] = `Bearer ${token}`
      }

      await fetch(`${API_BASE}/admin/auth/logout`, {
        method: 'POST',
        credentials: 'include',
        headers,
      })
    } catch (err) {
      console.error('Logout error:', err)
    } finally {
      // Clear local storage
      localStorage.removeItem('admin_token')
      setIsAuthenticated(false)
    }
  }, [])

  // Check auth status on mount
  useEffect(() => {
    checkAuth()
  }, [checkAuth])

  return {
    isAuthenticated,
    isAuthRequired,
    isLoading,
    error,
    checkAuth,
    logout,
  }
}

/**
 * Protected Route Component
 *
 * Wraps admin routes to ensure authentication before rendering.
 */
export function RequireAdminAuth({
  children,
  fallback,
}: {
  children: React.ReactNode
  fallback?: React.ReactNode
}): React.ReactElement | null {
  const { isAuthenticated, isAuthRequired, isLoading } = useAdminAuth()

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-900 flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
          <p className="text-gray-400 text-sm">Checking authentication...</p>
        </div>
      </div>
    )
  }

  if (isAuthRequired && !isAuthenticated) {
    // Return fallback or redirect handled by parent
    return fallback ? <>{fallback}</> : null
  }

  return <>{children}</>
}
