/**
 * Admin Dashboard - Main control center for race organizers
 *
 * This is the primary entry point for series administrators.
 * Provides system health overview, event management, and quick actions.
 *
 * UI-7: Refactored with design system tokens
 * UI-23: Completed migration — removed gradients, space-y, legacy heading sizing
 */
import { useState, useMemo } from 'react'
import { Link, useParams, useNavigate } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import VehicleBulkUpload from '../../components/admin/VehicleBulkUpload'
import { useToast } from '../../hooks/useToast'
import { SkeletonHealthPanel, SkeletonEventItem } from '../../components/common/Skeleton'
import { PageHeader } from '../../components/common'
import Badge from '../../components/ui/Badge'
import EmptyState from '../../components/ui/EmptyState'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

// Helper to get auth headers for admin API calls
function getAdminHeaders(): HeadersInit {
  const token = localStorage.getItem('admin_token')
  return token ? { Authorization: `Bearer ${token}` } : {}
}

interface SystemHealth {
  database: { status: string; latency_ms: number }
  redis: { status: string; latency_ms: number }
  active_connections: number
  trucks_online: number
  last_telemetry_age_s: number | null
}

interface EventSummary {
  event_id: string
  name: string
  status: 'upcoming' | 'in_progress' | 'finished'
  scheduled_start: string | null
  vehicle_count: number
  created_at: string
}

// Helper to get status badge variant
function getStatusBadgeVariant(status: string): 'error' | 'info' | 'neutral' {
  switch (status) {
    case 'in_progress':
      return 'error'
    case 'upcoming':
      return 'info'
    default:
      return 'neutral'
  }
}

// Helper to get health status color class
function getHealthStatusColor(status: string): string {
  switch (status) {
    case 'healthy':
    case 'ok':
      return 'bg-status-success'
    case 'degraded':
      return 'bg-status-warning'
    default:
      return 'bg-status-error'
  }
}

export default function AdminDashboard() {
  // eventId is available from route params for future event-specific views
  const { eventId: _eventId } = useParams<{ eventId: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const toast = useToast()
  const [healthCheckRunning, setHealthCheckRunning] = useState(false)
  const [showBulkUpload, setShowBulkUpload] = useState(false)
  const [selectedEventForUpload, setSelectedEventForUpload] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'upcoming' | 'in_progress' | 'finished'>('all')

  // Fetch system health
  const { data: health, refetch: refetchHealth, isLoading: healthLoading, error: healthError } = useQuery({
    queryKey: ['admin', 'health'],
    queryFn: async () => {
      console.log('[AdminDashboard] Fetching health from:', `${API_BASE}/admin/health`)
      const res = await fetch(`${API_BASE}/admin/health`, {
        credentials: 'include',
        headers: getAdminHeaders(),
      })
      console.log('[AdminDashboard] Health response:', res.status, res.statusText)
      if (!res.ok) {
        const text = await res.text()
        console.error('[AdminDashboard] Health error response:', text)
        throw new Error(`Health check failed: ${res.status} ${res.statusText}`)
      }
      const data = await res.json()
      console.log('[AdminDashboard] Health data:', data)
      return data as SystemHealth
    },
    refetchInterval: 30000, // Auto-refresh every 30s
    retry: 1, // Only retry once
  })

  // Fetch events
  const { data: events, isLoading: eventsLoading } = useQuery({
    queryKey: ['admin', 'events'],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/admin/events`, {
        credentials: 'include',
        headers: getAdminHeaders(),
      })
      if (!res.ok) throw new Error('Failed to fetch events')
      return res.json() as Promise<EventSummary[]>
    },
  })

  // Run full health check
  const runHealthCheck = async () => {
    setHealthCheckRunning(true)
    await refetchHealth()
    setHealthCheckRunning(false)
  }

  // Filter events based on search and status
  const filteredEvents = useMemo(() => {
    if (!events) return []
    return events.filter((event) => {
      const matchesSearch = event.name.toLowerCase().includes(searchQuery.toLowerCase())
      const matchesStatus = statusFilter === 'all' || event.status === statusFilter
      return matchesSearch && matchesStatus
    })
  }, [events, searchQuery, statusFilter])

  return (
    <div className="h-full overflow-y-auto bg-neutral-950">
      <PageHeader
        title="Admin"
        subtitle="Race Operations Dashboard"
        backTo="/"
        rightSlot={
          <span className="text-ds-caption text-neutral-500">
            Last updated: {new Date().toLocaleTimeString()}
          </span>
        }
      />

      <main className="max-w-7xl mx-auto px-ds-4 py-ds-8 sm:px-ds-6 lg:px-ds-8">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-ds-6">
          {/* Main Content - Left 2 columns */}
          <div className="lg:col-span-2 flex flex-col gap-ds-6">
            {/* System Health Panel */}
            <section className="bg-neutral-900 rounded-ds-lg border border-neutral-800 overflow-hidden">
              <div className="px-ds-6 py-ds-4 border-b border-neutral-800 flex items-center justify-between">
                <h2 className="text-ds-heading text-neutral-50 flex items-center gap-ds-2">
                  <span className="text-xl">🔧</span>
                  System Health
                </h2>
                <button
                  onClick={runHealthCheck}
                  disabled={healthCheckRunning}
                  className="px-ds-4 py-ds-2 bg-accent-500 hover:bg-accent-600 disabled:bg-accent-700 disabled:cursor-wait text-white text-ds-body-sm font-medium rounded-ds-md transition-colors"
                >
                  {healthCheckRunning ? 'Checking...' : 'Run Health Check'}
                </button>
              </div>

              <div className="p-ds-6">
                {healthLoading ? (
                  <SkeletonHealthPanel />
                ) : health ? (
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-ds-4">
                    {/* Database */}
                    <div className="bg-neutral-800/50 rounded-ds-md p-ds-4">
                      <div className="flex items-center gap-ds-2 mb-ds-2">
                        <span className={`w-2.5 h-2.5 rounded-full ${getHealthStatusColor(health.database.status)}`}></span>
                        <span className="text-ds-body-sm font-medium text-neutral-300">Database</span>
                      </div>
                      <div className="text-ds-title font-bold text-neutral-50">
                        {health.database.latency_ms}ms
                      </div>
                      <div className="text-ds-caption text-neutral-500 mt-ds-1">Response time</div>
                    </div>

                    {/* Redis */}
                    <div className="bg-neutral-800/50 rounded-ds-md p-ds-4">
                      <div className="flex items-center gap-ds-2 mb-ds-2">
                        <span className={`w-2.5 h-2.5 rounded-full ${getHealthStatusColor(health.redis.status)}`}></span>
                        <span className="text-ds-body-sm font-medium text-neutral-300">Redis</span>
                      </div>
                      <div className="text-ds-title font-bold text-neutral-50">
                        {health.redis.latency_ms}ms
                      </div>
                      <div className="text-ds-caption text-neutral-500 mt-ds-1">Response time</div>
                    </div>

                    {/* Active Trucks */}
                    <div className="bg-neutral-800/50 rounded-ds-md p-ds-4">
                      <div className="flex items-center gap-ds-2 mb-ds-2">
                        <span className={`w-2.5 h-2.5 rounded-full ${health.trucks_online > 0 ? 'bg-status-success' : 'bg-neutral-500'}`}></span>
                        <span className="text-ds-body-sm font-medium text-neutral-300">Trucks Online</span>
                      </div>
                      <div className="text-ds-title font-bold text-neutral-50">
                        {health.trucks_online}
                      </div>
                      <div className="text-ds-caption text-neutral-500 mt-ds-1">Active uplinks</div>
                    </div>

                    {/* Last Telemetry */}
                    <div className="bg-neutral-800/50 rounded-ds-md p-ds-4">
                      <div className="flex items-center gap-ds-2 mb-ds-2">
                        <span className={`w-2.5 h-2.5 rounded-full ${
                          health.last_telemetry_age_s === null ? 'bg-neutral-500' :
                          health.last_telemetry_age_s < 10 ? 'bg-status-success' :
                          health.last_telemetry_age_s < 60 ? 'bg-status-warning' : 'bg-status-error'
                        }`}></span>
                        <span className="text-ds-body-sm font-medium text-neutral-300">Last Data</span>
                      </div>
                      <div className="text-ds-title font-bold text-neutral-50">
                        {health.last_telemetry_age_s === null ? '—' : `${health.last_telemetry_age_s}s`}
                      </div>
                      <div className="text-ds-caption text-neutral-500 mt-ds-1">Time since last</div>
                    </div>
                  </div>
                ) : (
                  <div className="text-center py-ds-8">
                    <p className="text-ds-body-sm text-neutral-400 mb-ds-2">Unable to fetch system health</p>
                    {healthError && (
                      <p className="text-ds-body-sm text-status-error mb-ds-4">
                        {(healthError as Error).message}
                      </p>
                    )}
                    <button
                      onClick={runHealthCheck}
                      className="px-ds-4 py-ds-2 bg-neutral-800 hover:bg-neutral-700 text-neutral-50 text-ds-body-sm rounded-ds-md transition-colors"
                    >
                      Retry
                    </button>
                  </div>
                )}
              </div>
            </section>

            {/* Events Section */}
            <section className="bg-neutral-900 rounded-ds-lg border border-neutral-800 overflow-hidden">
              <div className="px-ds-6 py-ds-4 border-b border-neutral-800">
                <div className="flex items-center justify-between mb-ds-4">
                  <h2 className="text-ds-heading text-neutral-50 flex items-center gap-ds-2">
                    <span className="text-xl">🏁</span>
                    Events
                  </h2>
                  <Link
                    to="/admin/events/new"
                    className="px-ds-4 py-ds-2 bg-status-success hover:bg-status-success/90 text-white text-ds-body-sm font-medium rounded-ds-md transition-colors flex items-center gap-ds-2"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                    </svg>
                    New Event
                  </Link>
                </div>

                {/* Search and Filter */}
                {events && events.length > 0 && (
                  <div className="flex flex-col sm:flex-row gap-ds-3">
                    {/* Search Input */}
                    <div className="relative flex-1">
                      <svg
                        className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-500"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                      </svg>
                      <input
                        type="text"
                        placeholder="Search events..."
                        value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                        className="w-full pl-10 pr-ds-4 py-ds-2 bg-neutral-800 border border-neutral-700 rounded-ds-md text-neutral-50 placeholder-neutral-500 text-ds-body-sm focus:outline-none focus:ring-2 focus:ring-accent-500 focus:border-transparent"
                      />
                      {searchQuery && (
                        <button
                          onClick={() => setSearchQuery('')}
                          className="absolute right-3 top-1/2 -translate-y-1/2 text-neutral-500 hover:text-neutral-300"
                        >
                          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                          </svg>
                        </button>
                      )}
                    </div>

                    {/* Status Filter */}
                    <select
                      value={statusFilter}
                      onChange={(e) => setStatusFilter(e.target.value as typeof statusFilter)}
                      className="px-ds-4 py-ds-2 bg-neutral-800 border border-neutral-700 rounded-ds-md text-neutral-50 text-ds-body-sm focus:outline-none focus:ring-2 focus:ring-accent-500 focus:border-transparent"
                    >
                      <option value="all">All Status</option>
                      <option value="in_progress">Live</option>
                      <option value="upcoming">Upcoming</option>
                      <option value="finished">Finished</option>
                    </select>
                  </div>
                )}
              </div>

              <div className="p-ds-6">
                {eventsLoading ? (
                  <div className="flex flex-col gap-ds-3">
                    <SkeletonEventItem />
                    <SkeletonEventItem />
                    <SkeletonEventItem />
                  </div>
                ) : events && events.length > 0 ? (
                  filteredEvents.length > 0 ? (
                  <div className="flex flex-col gap-ds-3">
                    {filteredEvents.map((event) => (
                      <Link
                        key={event.event_id}
                        to={`/admin/events/${event.event_id}`}
                        className="block bg-neutral-800/50 hover:bg-neutral-800 rounded-ds-md p-ds-4 transition-colors"
                      >
                        <div className="flex items-center justify-between">
                          <div>
                            <div className="flex items-center gap-ds-3">
                              <h3 className="font-semibold text-neutral-50">{event.name}</h3>
                              <Badge
                                variant={getStatusBadgeVariant(event.status)}
                                dot={event.status === 'in_progress'}
                                pulse={event.status === 'in_progress'}
                                size="sm"
                              >
                                {event.status === 'in_progress' ? 'LIVE' : event.status.toUpperCase()}
                              </Badge>
                            </div>
                            <div className="text-ds-body-sm text-neutral-400 mt-ds-1 flex items-center gap-ds-2">
                              <span className="font-mono text-ds-caption bg-neutral-700/50 px-1.5 py-0.5 rounded-ds-sm text-neutral-500">
                                {event.event_id}
                              </span>
                              <span className="text-neutral-600">·</span>
                              {event.scheduled_start
                                ? new Date(event.scheduled_start).toLocaleDateString('en-US', {
                                    weekday: 'short',
                                    month: 'short',
                                    day: 'numeric',
                                    year: 'numeric',
                                  })
                                : 'Date TBD'}
                              {' · '}
                              {event.vehicle_count} vehicles registered
                            </div>
                          </div>
                          <svg className="w-5 h-5 text-neutral-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                          </svg>
                        </div>
                      </Link>
                    ))}
                  </div>
                  ) : (
                    <EmptyState
                      icon={<span className="text-5xl">🔍</span>}
                      title="No events match your search"
                      description="Try adjusting your search terms or filters."
                      action={{
                        label: 'Clear filters',
                        onClick: () => {
                          setSearchQuery('')
                          setStatusFilter('all')
                        },
                        variant: 'secondary',
                      }}
                    />
                  )
                ) : (
                  <EmptyState
                    icon={<span className="text-6xl">🏜️</span>}
                    title="No Events Yet"
                    description="Create your first event to get started with race timing."
                    action={{
                      label: 'Create Your First Event',
                      onClick: () => navigate('/admin/events/new'),
                    }}
                  />
                )}
              </div>
            </section>
          </div>

          {/* Sidebar - Right column */}
          <div className="flex flex-col gap-ds-6">
            {/* Quick Actions */}
            <section className="bg-neutral-900 rounded-ds-lg border border-neutral-800 overflow-hidden">
              <div className="px-ds-6 py-ds-4 border-b border-neutral-800">
                <h2 className="text-ds-heading text-neutral-50">Quick Actions</h2>
              </div>
              <div className="p-ds-4 flex flex-col gap-ds-2">
                <Link
                  to="/admin/events/new"
                  className="flex items-center gap-ds-3 w-full p-ds-3 bg-neutral-800/50 hover:bg-neutral-800 rounded-ds-md transition-colors text-left"
                >
                  <span className="text-xl">➕</span>
                  <div>
                    <div className="font-medium text-neutral-50">Start New Event</div>
                    <div className="text-ds-caption text-neutral-500">Create and configure a race</div>
                  </div>
                </Link>

                {events && events.find(e => e.status === 'in_progress') && (
                  <Link
                    to={`/events/${events.find(e => e.status === 'in_progress')?.event_id}`}
                    className="flex items-center gap-ds-3 w-full p-ds-3 bg-status-error/10 hover:bg-status-error/20 border border-status-error/30 rounded-ds-md transition-colors text-left"
                  >
                    <span className="text-xl">🔴</span>
                    <div>
                      <div className="font-medium text-neutral-50">View Live Event</div>
                      <div className="text-ds-caption text-status-error">Currently in progress</div>
                    </div>
                  </Link>
                )}

                <Link
                  to="/team/login"
                  className="flex items-center gap-ds-3 w-full p-ds-3 bg-neutral-800/50 hover:bg-neutral-800 rounded-ds-md transition-colors text-left"
                >
                  <span className="text-xl">👥</span>
                  <div>
                    <div className="font-medium text-neutral-50">Team Dashboard</div>
                    <div className="text-ds-caption text-neutral-500">Team login & management</div>
                  </div>
                </Link>

                <a
                  href="/docs"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-ds-3 w-full p-ds-3 bg-neutral-800/50 hover:bg-neutral-800 rounded-ds-md transition-colors text-left"
                >
                  <span className="text-xl">📚</span>
                  <div>
                    <div className="font-medium text-neutral-50">API Documentation</div>
                    <div className="text-ds-caption text-neutral-500">OpenAPI / Swagger</div>
                  </div>
                </a>

                {/* Bulk Import - show if events exist */}
                {events && events.length > 0 && (
                  <button
                    onClick={() => {
                      setSelectedEventForUpload(events[0].event_id)
                      setShowBulkUpload(true)
                    }}
                    className="flex items-center gap-ds-3 w-full p-ds-3 bg-accent-500/10 hover:bg-accent-500/20 border border-accent-500/30 rounded-ds-md transition-colors text-left"
                  >
                    <span className="text-xl">📥</span>
                    <div>
                      <div className="font-medium text-neutral-50">Bulk Import Vehicles</div>
                      <div className="text-ds-caption text-accent-400">Upload CSV file</div>
                    </div>
                  </button>
                )}
              </div>
            </section>

            {/* Getting Started Guide */}
            <section className="bg-accent-900/20 rounded-ds-lg border border-accent-800/30 overflow-hidden">
              <div className="px-ds-6 py-ds-4 border-b border-accent-800/30">
                <h2 className="text-ds-heading text-neutral-50">Getting Started</h2>
              </div>
              <div className="p-ds-6">
                <ol className="flex flex-col gap-ds-4 text-ds-body-sm">
                  <li className="flex gap-ds-3">
                    <span className="flex-shrink-0 w-6 h-6 bg-accent-500 text-white text-ds-caption font-bold rounded-full flex items-center justify-center">1</span>
                    <div>
                      <div className="font-medium text-neutral-50">Create an Event</div>
                      <div className="text-neutral-400">Set up race details, dates, and classes</div>
                    </div>
                  </li>
                  <li className="flex gap-ds-3">
                    <span className="flex-shrink-0 w-6 h-6 bg-accent-500 text-white text-ds-caption font-bold rounded-full flex items-center justify-center">2</span>
                    <div>
                      <div className="font-medium text-neutral-50">Register Vehicles</div>
                      <div className="text-neutral-400">Add trucks and generate auth tokens</div>
                    </div>
                  </li>
                  <li className="flex gap-ds-3">
                    <span className="flex-shrink-0 w-6 h-6 bg-accent-500 text-white text-ds-caption font-bold rounded-full flex items-center justify-center">3</span>
                    <div>
                      <div className="font-medium text-neutral-50">Install Edge Software</div>
                      <div className="text-neutral-400">Set up trucks with their tokens</div>
                    </div>
                  </li>
                  <li className="flex gap-ds-3">
                    <span className="flex-shrink-0 w-6 h-6 bg-accent-500 text-white text-ds-caption font-bold rounded-full flex items-center justify-center">4</span>
                    <div>
                      <div className="font-medium text-neutral-50">Go Live!</div>
                      <div className="text-neutral-400">Start the event and watch real-time data</div>
                    </div>
                  </li>
                </ol>
              </div>
            </section>

            {/* System Info */}
            <section className="bg-neutral-900 rounded-ds-lg border border-neutral-800 overflow-hidden">
              <div className="px-ds-6 py-ds-4 border-b border-neutral-800">
                <h2 className="text-ds-body-sm font-medium text-neutral-400">System Info</h2>
              </div>
              <div className="p-ds-4 text-ds-caption text-neutral-500 flex flex-col gap-ds-1">
                <div className="flex justify-between">
                  <span>Version</span>
                  <span className="text-neutral-400">4.0.0</span>
                </div>
                <div className="flex justify-between">
                  <span>API</span>
                  <span className="text-neutral-400">{API_BASE}</span>
                </div>
              </div>
            </section>
          </div>
        </div>
      </main>

      {/* Bulk Upload Modal */}
      {showBulkUpload && selectedEventForUpload && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-ds-4">
          {/* Backdrop */}
          <div
            className="absolute inset-0 bg-black/70"
            onClick={() => setShowBulkUpload(false)}
          />

          {/* Modal */}
          <div className="relative w-full max-w-2xl max-h-[90vh] overflow-y-auto">
            {/* Event selector if multiple events */}
            {events && events.length > 1 && (
              <div className="mb-ds-4 bg-neutral-900 rounded-ds-lg border border-neutral-800 p-ds-4">
                <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-2">
                  Select Event for Import
                </label>
                <select
                  value={selectedEventForUpload}
                  onChange={(e) => setSelectedEventForUpload(e.target.value)}
                  className="w-full px-ds-4 py-ds-2 bg-neutral-800 border border-neutral-700 rounded-ds-md text-neutral-50 focus:outline-none focus:ring-2 focus:ring-accent-500"
                >
                  {events.map((event) => (
                    <option key={event.event_id} value={event.event_id}>
                      {event.name} ({event.vehicle_count} vehicles)
                    </option>
                  ))}
                </select>
              </div>
            )}

            <VehicleBulkUpload
              eventId={selectedEventForUpload}
              onSuccess={(result) => {
                toast.success('Bulk import complete', `${result.added} vehicle${result.added !== 1 ? 's' : ''} imported`)
                queryClient.invalidateQueries({ queryKey: ['admin', 'events'] })
                setShowBulkUpload(false)
              }}
              onClose={() => setShowBulkUpload(false)}
            />
          </div>
        </div>
      )}
    </div>
  )
}
