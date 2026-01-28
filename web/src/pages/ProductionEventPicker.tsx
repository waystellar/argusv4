/**
 * Production Event Picker
 *
 * Entry point for production directors at /production.
 * Lists available events with status indicators, then navigates
 * to the Control Room at /production/events/:eventId.
 *
 * Protected route - requires admin authentication.
 *
 * UI-24: Completed migration — fixed non-DS typography and spacing tokens
 */
import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { api, type Event } from '../api/client'
import { AppLoading, Spinner, StatusPill, getEventStatusVariant, PageHeader } from '../components/common'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

export default function ProductionEventPicker() {
  const navigate = useNavigate()

  // Auth state
  const [authState, setAuthState] = useState<'loading' | 'authenticated' | 'unauthenticated'>('loading')
  const [, setAdminToken] = useState(() => localStorage.getItem('admin_token') || '')
  const [tokenInput, setTokenInput] = useState('')
  const [error, setError] = useState<string | null>(null)

  // Check authentication on mount
  useEffect(() => {
    checkAuth()
  }, [])

  async function checkAuth() {
    try {
      const token = localStorage.getItem('admin_token')
      const headers: HeadersInit = {}
      if (token) {
        headers['Authorization'] = `Bearer ${token}`
      }

      const response = await fetch(`${API_BASE}/admin/auth/status`, {
        credentials: 'include',
        headers,
      })

      if (response.ok) {
        const data = await response.json()
        if (!data.auth_required || data.authenticated) {
          setAuthState('authenticated')
          setAdminToken(token || '')
        } else {
          setAuthState('unauthenticated')
        }
      } else if (response.status === 401 || response.status === 403) {
        setAuthState('unauthenticated')
        setError('Authentication required. Please enter your admin token.')
      } else {
        // On other errors, try to proceed (might be network issue)
        setAuthState('authenticated')
      }
    } catch (err) {
      console.error('Auth check failed:', err)
      // On error, allow access (might be network issue)
      setAuthState('authenticated')
    }
  }

  // Fetch events
  const { data: events, isLoading, error: fetchError } = useQuery({
    queryKey: ['production-events'],
    queryFn: () => api.getEvents(),
    enabled: authState === 'authenticated',
    refetchInterval: 30000, // Refresh every 30 seconds
  })

  // Login handler
  const handleLogin = async () => {
    if (!tokenInput.trim()) return

    try {
      // Call the actual login endpoint with password
      const response = await fetch(`${API_BASE}/admin/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: tokenInput }),
        credentials: 'include', // Include cookies
      })

      if (response.ok) {
        const data = await response.json()
        // Store the JWT token, not the password
        localStorage.setItem('admin_token', data.access_token)
        setAdminToken(data.access_token)
        setAuthState('authenticated')
        setError(null)
      } else if (response.status === 401) {
        setError('Invalid password. Please try again.')
      } else {
        const data = await response.json().catch(() => ({}))
        setError(data.detail || 'Login failed. Please try again.')
      }
    } catch (err) {
      console.error('Login error:', err)
      setError('Network error. Please check your connection.')
    }
  }

  // Navigate to control room
  const handleSelectEvent = (eventId: string) => {
    navigate(`/production/events/${eventId}`)
  }

  // Sort events: in_progress first, then upcoming, then finished
  const sortedEvents = [...(events || [])].sort((a, b) => {
    const order = { in_progress: 0, upcoming: 1, finished: 2 }
    return order[a.status] - order[b.status]
  })

  // Loading state
  if (authState === 'loading') {
    return <AppLoading message="Checking credentials..." />
  }

  // Login screen
  if (authState === 'unauthenticated') {
    return (
      <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-ds-4">
        <div className="w-full max-w-md bg-neutral-900 rounded-ds-lg p-ds-6 border border-neutral-800">
          <div className="flex items-center gap-ds-3 mb-ds-6">
            <div className="w-12 h-12 rounded-ds-md bg-status-error flex items-center justify-center">
              <svg className="w-7 h-7 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
            </div>
            <div>
              <h1 className="text-ds-title text-neutral-50">Production Control</h1>
              <p className="text-ds-body-sm text-neutral-400">Broadcast Director Access</p>
            </div>
          </div>

          {error && (
            <div className="mb-ds-4 p-ds-3 bg-status-error/10 border border-status-error/30 rounded-ds-md text-status-error text-ds-body-sm flex items-start gap-ds-2">
              <svg className="w-5 h-5 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              {error}
            </div>
          )}

          <input
            type="password"
            value={tokenInput}
            onChange={(e) => setTokenInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleLogin()}
            placeholder="Admin Token"
            className="w-full px-ds-4 py-ds-3 bg-neutral-800 border border-neutral-700 rounded-ds-md text-neutral-50 placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-accent-500 mb-ds-4"
            autoFocus
          />

          <button
            onClick={handleLogin}
            className="w-full py-ds-3 bg-accent-600 hover:bg-accent-700 text-white font-semibold rounded-ds-md transition-colors duration-ds-fast"
          >
            Access Control Room
          </button>

          <button
            onClick={() => navigate('/events')}
            className="w-full mt-ds-3 py-ds-2 text-neutral-400 hover:text-neutral-50 text-ds-body-sm transition-colors duration-ds-fast"
          >
            Return to Fan View
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-50 flex flex-col">
      <PageHeader
        title="Production"
        subtitle="Select an event to manage"
        backTo="/"
        rightSlot={
          <button
            onClick={() => {
              localStorage.removeItem('admin_token')
              setAuthState('unauthenticated')
              setAdminToken('')
            }}
            className="px-ds-4 py-ds-2 text-ds-body-sm bg-neutral-800 hover:bg-neutral-700 rounded-ds-md transition-colors duration-ds-fast"
          >
            Logout
          </button>
        }
      />

      {/* Content */}
      <main className="max-w-7xl mx-auto p-ds-6">
        {/* Filter Tabs */}
        <div className="flex items-center gap-ds-2 mb-ds-6">
          <span className="text-ds-body-sm text-neutral-500">Filter:</span>
          <button className="px-ds-3 py-ds-2 bg-neutral-800 hover:bg-neutral-700 rounded-ds-md text-ds-body-sm transition-colors duration-ds-fast">
            All Events
          </button>
          <button className="px-ds-3 py-ds-2 text-neutral-400 hover:bg-neutral-800 rounded-ds-md text-ds-body-sm transition-colors duration-ds-fast">
            Live Now
          </button>
          <button className="px-ds-3 py-ds-2 text-neutral-400 hover:bg-neutral-800 rounded-ds-md text-ds-body-sm transition-colors duration-ds-fast">
            Upcoming
          </button>
        </div>

        {/* Loading */}
        {isLoading && (
          <div className="flex items-center justify-center py-20">
            <Spinner size="lg" />
          </div>
        )}

        {/* Error */}
        {fetchError && (
          <div className="p-ds-4 bg-status-error/10 border border-status-error/30 rounded-ds-md text-status-error mb-ds-6 flex items-start gap-ds-3">
            <svg className="w-5 h-5 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <div>
              <p className="text-ds-body font-medium">Failed to load events</p>
              <p className="text-ds-body-sm text-neutral-400 mt-ds-1">Please check your connection and try again.</p>
            </div>
          </div>
        )}

        {/* Empty State */}
        {!isLoading && !fetchError && sortedEvents.length === 0 && (
          <div className="text-center py-20">
            <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-neutral-800 mb-ds-4">
              <svg className="w-8 h-8 text-neutral-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
            </div>
            <h3 className="text-ds-heading text-neutral-300 mb-ds-2">No Events Found</h3>
            <p className="text-ds-body-sm text-neutral-500 mb-ds-6">Create an event in the Admin Dashboard to get started.</p>
            <button
              onClick={() => navigate('/admin')}
              className="px-ds-4 py-ds-2 bg-accent-600 hover:bg-accent-700 text-white rounded-ds-md text-ds-body-sm font-medium transition-colors duration-ds-fast"
            >
              Go to Admin Dashboard
            </button>
          </div>
        )}

        {/* Events Grid */}
        {!isLoading && sortedEvents.length > 0 && (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-ds-4">
            {sortedEvents.map((event) => (
              <EventCard
                key={event.event_id}
                event={event}
                onSelect={() => handleSelectEvent(event.event_id)}
              />
            ))}
          </div>
        )}
      </main>
    </div>
  )
}

/**
 * Event card component
 */
function EventCard({ event, onSelect }: { event: Event; onSelect: () => void }) {
  const cardStyles = {
    in_progress: 'border-status-success/50 hover:border-status-success',
    upcoming: 'border-neutral-700 hover:border-neutral-600',
    finished: 'border-neutral-800 hover:border-neutral-700 opacity-75',
  }

  return (
    <button
      onClick={onSelect}
      className={`w-full text-left bg-neutral-900 rounded-ds-lg border p-ds-4 transition-all duration-ds-fast ${cardStyles[event.status]}`}
    >
      <div className="flex items-start justify-between mb-ds-3">
        <StatusPill
          label={event.status === 'in_progress' ? 'LIVE' : event.status === 'upcoming' ? 'UPCOMING' : 'FINISHED'}
          variant={getEventStatusVariant(event.status)}
          pulse={event.status === 'in_progress'}
        />
        <span className="text-ds-caption text-neutral-500 font-mono">
          {event.vehicle_count} vehicle{event.vehicle_count !== 1 ? 's' : ''}
        </span>
      </div>

      <h3 className="text-ds-body font-bold text-neutral-50 mb-ds-1 truncate">{event.name}</h3>
      <p className="text-ds-caption font-mono text-neutral-500 mb-ds-1">
        <span className="bg-neutral-800 px-1.5 py-0.5 rounded-ds-sm">{event.event_id}</span>
      </p>

      {event.scheduled_start && (
        <p className="text-ds-body-sm text-neutral-400">
          {new Date(event.scheduled_start).toLocaleDateString(undefined, {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
          })}
        </p>
      )}

      <div className="mt-ds-4 flex items-center justify-between">
        <span className="text-ds-caption text-neutral-500">
          {event.total_laps} lap{event.total_laps !== 1 ? 's' : ''}
          {event.course_distance_m && (
            <> · {(event.course_distance_m / 1609.34).toFixed(1)} mi</>
          )}
        </span>
        <span className="text-accent-400 text-ds-body-sm font-medium">
          Open Control Room →
        </span>
      </div>
    </button>
  )
}
