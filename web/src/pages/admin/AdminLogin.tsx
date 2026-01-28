/**
 * Admin Login Page
 *
 * UI-17: Migrated to design system tokens (neutral-*, status-*, accent-*, ds-*)
 * Authenticates admin users to access the admin dashboard.
 * Uses password-based authentication with JWT sessions.
 */
import { useState, useEffect } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { PageHeader } from '../../components/common'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

interface AuthStatus {
  auth_required: boolean
  authenticated: boolean
  message: string
}

export default function AdminLogin() {
  const navigate = useNavigate()
  const location = useLocation()
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [isChecking, setIsChecking] = useState(true)

  // Check if already authenticated or auth not required
  useEffect(() => {
    checkAuthStatus()
  }, [])

  async function checkAuthStatus() {
    try {
      const response = await fetch(`${API_BASE}/admin/auth/status`, {
        credentials: 'include',
      })
      const data: AuthStatus = await response.json()

      if (!data.auth_required || data.authenticated) {
        // No auth needed or already logged in - redirect to dashboard
        const from = (location.state as { from?: string })?.from || '/'
        navigate(from, { replace: true })
      }
    } catch (err) {
      // If check fails, show login form
      console.error('Auth status check failed:', err)
    } finally {
      setIsChecking(false)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setIsLoading(true)

    try {
      const response = await fetch(`${API_BASE}/admin/auth/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        credentials: 'include',
        body: JSON.stringify({ password }),
      })

      if (!response.ok) {
        const data = await response.json()
        throw new Error(data.detail || 'Login failed')
      }

      const data = await response.json()

      // Store token in localStorage as backup (cookie is primary)
      localStorage.setItem('admin_token', data.access_token)

      // Redirect to original destination or dashboard
      const from = (location.state as { from?: string })?.from || '/'
      navigate(from, { replace: true })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed')
    } finally {
      setIsLoading(false)
    }
  }

  // Show loading while checking auth status
  if (isChecking) {
    return (
      <div className="min-h-screen bg-neutral-950 flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-4 border-accent-500 border-t-transparent"></div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-neutral-950 flex flex-col">
      <PageHeader title="Admin Login" backTo="/" />
      <div className="flex-1 flex items-center justify-center p-ds-4">
      <div className="w-full max-w-md">
        {/* Logo/Header */}
        <div className="text-center mb-ds-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-accent-600 rounded-ds-xl mb-ds-4">
            <svg className="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <h1 className="text-ds-title font-bold text-neutral-50">Argus Admin</h1>
          <p className="text-neutral-400 text-ds-body-sm mt-ds-1">Sign in to manage your events</p>
        </div>

        {/* Login Form */}
        <form onSubmit={handleSubmit} className="bg-neutral-900 rounded-ds-xl p-ds-6 shadow-ds-overlay border border-neutral-700">
          <div className="mb-ds-6">
            <label htmlFor="password" className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-2">
              Admin Password
            </label>
            <input
              type="password"
              id="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter your admin password"
              className="w-full px-ds-4 py-ds-3 bg-neutral-950 border border-neutral-600 rounded-ds-lg text-neutral-50 placeholder-neutral-500 focus:outline-none focus:border-accent-500 focus:ring-2 focus:ring-accent-500 transition-colors duration-ds-fast"
              required
              autoFocus
            />
          </div>

          {error && (
            <div className="mb-ds-4 p-ds-3 bg-status-error/10 border border-status-error/30 rounded-ds-lg text-ds-body-sm text-status-error flex items-center gap-ds-2" role="alert">
              <svg className="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={isLoading || !password}
            className="w-full py-ds-3 bg-accent-600 hover:bg-accent-500 disabled:bg-neutral-700 disabled:text-neutral-400 rounded-ds-lg font-medium text-white transition-colors duration-ds-fast disabled:cursor-not-allowed flex items-center justify-center gap-ds-2 focus:outline-none focus:ring-2 focus:ring-accent-500 focus:ring-offset-2 focus:ring-offset-neutral-900"
          >
            {isLoading ? (
              <>
                <svg className="animate-spin w-5 h-5" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Signing in...
              </>
            ) : (
              <>
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 16l-4-4m0 0l4-4m-4 4h14m-5 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h7a3 3 0 013 3v1" />
                </svg>
                Sign In
              </>
            )}
          </button>
        </form>

        {/* Help text */}
        <p className="text-center text-neutral-500 text-ds-body-sm mt-ds-6">
          Password was set during initial setup.
          <br />
          Contact your system administrator if you need access.
        </p>

      </div>
      </div>
    </div>
  )
}
