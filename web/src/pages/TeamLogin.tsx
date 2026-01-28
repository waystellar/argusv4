/**
 * Team Login Page
 *
 * UI-10 Update: Refactored to use design system tokens
 */
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { PageHeader } from '../components/common'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

export default function TeamLogin() {
  const navigate = useNavigate()
  const [vehicleNumber, setVehicleNumber] = useState('')
  const [teamToken, setTeamToken] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setIsLoading(true)

    try {
      const response = await fetch(`${API_BASE}/team/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          vehicle_number: vehicleNumber,
          team_token: teamToken,
        }),
      })

      if (!response.ok) {
        const data = await response.json()
        throw new Error(data.detail || 'Login failed')
      }

      const data = await response.json()
      localStorage.setItem('team_token', data.access_token)
      navigate('/team/dashboard')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed')
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-neutral-950 flex flex-col">
      <PageHeader
        title="Team Login"
        subtitle="Manage your truck"
        backTo="/"
      />
      <div className="flex-1 flex items-center justify-center p-ds-4">
      <div className="w-full max-w-md">
        {/* Logo/Header */}
        <div className="text-center mb-ds-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-ds-lg bg-accent-600/20 border border-accent-500/50 mb-ds-4">
            <svg className="w-8 h-8 text-accent-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
          </div>
          <h1 className="text-ds-title text-neutral-50">Team Dashboard</h1>
          <p className="text-ds-body-sm text-neutral-400 mt-ds-1">Manage your truck</p>
        </div>

        {/* Login Form */}
        <form onSubmit={handleSubmit} className="bg-neutral-900 rounded-ds-lg p-ds-6 border border-neutral-800">
          <div className="space-y-ds-4">
            <div>
              <label htmlFor="vehicleNumber" className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-1">
                Vehicle Number
              </label>
              <input
                type="text"
                id="vehicleNumber"
                value={vehicleNumber}
                onChange={(e) => setVehicleNumber(e.target.value)}
                placeholder="420"
                className="w-full px-ds-4 py-ds-3 bg-neutral-950 border border-neutral-700 rounded-ds-md text-neutral-50 placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-accent-500 transition-colors duration-ds-fast"
                required
              />
            </div>

            <div>
              <label htmlFor="teamToken" className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-1">
                Team Token
              </label>
              <input
                type="password"
                id="teamToken"
                value={teamToken}
                onChange={(e) => setTeamToken(e.target.value)}
                placeholder="Enter your truck token"
                className="w-full px-ds-4 py-ds-3 bg-neutral-950 border border-neutral-700 rounded-ds-md text-neutral-50 placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-accent-500 transition-colors duration-ds-fast"
                required
              />
              <p className="text-ds-caption text-neutral-500 mt-ds-1">
                This is the token provided when your vehicle was registered
              </p>
            </div>

            {error && (
              <div className="bg-status-error/10 border border-status-error/30 rounded-ds-md p-ds-3 text-ds-body-sm text-status-error flex items-start gap-ds-2">
                <svg className="w-5 h-5 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={isLoading}
              className="w-full py-ds-3 bg-accent-600 hover:bg-accent-700 disabled:bg-neutral-700 disabled:text-neutral-500 rounded-ds-md font-medium text-white transition-colors duration-ds-fast flex items-center justify-center gap-ds-2"
            >
              {isLoading ? (
                <>
                  <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  Signing in...
                </>
              ) : (
                'Sign In'
              )}
            </button>
          </div>
        </form>

        {/* Watch live link */}
        <div className="text-center mt-ds-6">
          <button
            onClick={() => navigate('/events')}
            className="text-neutral-400 hover:text-neutral-200 text-ds-body-sm block mx-auto transition-colors duration-ds-fast"
          >
            Watch Live Events
          </button>
        </div>
      </div>
      </div>
    </div>
  )
}
