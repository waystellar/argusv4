/**
 * Race Center - Main fan experience component
 *
 * F1/NASCAR-style "Race Center" with tabbed navigation:
 * - Overview: Map + Favorites + Featured + Mini Leaderboard
 * - Standings: Full leaderboard with search
 * - Watch: Video feeds
 * - Tracker: Vehicle list with GPS data
 *
 * UI-4 Update: Refactored to use design system tokens and components
 */
import { useState, useEffect, useCallback, useMemo } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useSafeBack } from '../../hooks/useSafeBack'
import TabBar from './TabBar'
import OverviewTab from './OverviewTab'
import StandingsTab from './StandingsTab'
import WatchTab from './WatchTab'
import TrackerTab from './TrackerTab'
import { useFavorites } from '../../hooks/useFavorites'
import { useEventStore } from '../../stores/eventStore'
import { useEventStream } from '../../hooks/useEventStream'
import { api } from '../../api/client'
import { Badge, EmptyState } from '../ui'
import type { RaceCenterTab } from './types'
import type { Event } from '../../api/client'

export default function RaceCenter() {
  const { eventId } = useParams<{ eventId: string }>()
  const navigate = useNavigate()
  const goBack = useSafeBack('/events')

  // Tab state
  const [activeTab, setActiveTab] = useState<RaceCenterTab>('overview')

  // Event data
  const [event, setEvent] = useState<Event | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // SSE connection (handles real-time updates automatically)
  const { isConnected, lastCheckpointMs } = useEventStream(eventId)

  // Real-time data from store (positions is a Map, convert to array)
  const positionsMap = useEventStore((s) => s.positions)
  const positions = useMemo(() => Array.from(positionsMap.values()), [positionsMap])
  const leaderboard = useEventStore((s) => s.leaderboard)

  // Favorites
  const { favorites, toggleFavorite } = useFavorites(eventId)

  // Selected vehicle state
  const [selectedVehicleId, setSelectedVehicleId] = useState<string | null>(null)

  // Fetch event details
  useEffect(() => {
    if (!eventId) {
      setError('No event ID provided')
      setIsLoading(false)
      return
    }

    async function fetchEvent() {
      try {
        setIsLoading(true)
        setError(null)
        const eventData = await api.getEvent(eventId!)
        setEvent(eventData)
      } catch (err) {
        console.error('Failed to fetch event:', err)
        setError('Failed to load event')
      } finally {
        setIsLoading(false)
      }
    }

    fetchEvent()
  }, [eventId])

  // Fetch leaderboard on initial load and on checkpoint events (SSE triggers refresh)
  // Initial fetch ensures registered entrants appear even before any checkpoint crossings
  const [initialLeaderboardLoaded, setInitialLeaderboardLoaded] = useState(false)

  useEffect(() => {
    if (!eventId) return
    // Fetch on: initial load (once), or whenever a checkpoint event arrives
    if (initialLeaderboardLoaded && !lastCheckpointMs) return

    async function fetchLeaderboard() {
      try {
        const data = await api.getLeaderboard(eventId!)
        useEventStore.getState().setLeaderboard(data.entries)
        setInitialLeaderboardLoaded(true)
      } catch (err) {
        console.error('Failed to fetch leaderboard:', err)
      }
    }

    fetchLeaderboard()
  }, [eventId, lastCheckpointMs, initialLeaderboardLoaded])

  // Handle vehicle selection - navigate to vehicle detail page
  const handleVehicleSelect = useCallback((vehicleId: string) => {
    setSelectedVehicleId(vehicleId)
    navigate(`/events/${eventId}/vehicles/${vehicleId}`)
  }, [navigate, eventId])

  // Loading state - skeleton layout
  if (isLoading) {
    return (
      <div className="min-h-screen bg-neutral-950 flex flex-col">
        {/* Header Skeleton */}
        <header className="bg-neutral-900 border-b border-neutral-800 px-ds-4 py-ds-3">
          <div className="flex items-center justify-between">
            <div className="skeleton bg-neutral-800 rounded-ds-md w-10 h-10" />
            <div className="flex-1 flex flex-col items-center gap-ds-2">
              <div className="skeleton bg-neutral-800 rounded-ds-sm h-5 w-40" />
              <div className="skeleton bg-neutral-800 rounded-ds-sm h-4 w-24" />
            </div>
            <div className="w-10" />
          </div>
        </header>

        {/* Content Skeleton */}
        <div className="flex-1 p-ds-4 space-y-ds-4">
          <div className="skeleton bg-neutral-800 rounded-ds-lg h-48 w-full" />
          <div className="skeleton bg-neutral-800 rounded-ds-md h-16 w-full" />
          <div className="space-y-ds-2">
            {[1, 2, 3, 4, 5].map((i) => (
              <div key={i} className="skeleton bg-neutral-800 rounded-ds-md h-14" />
            ))}
          </div>
        </div>

        {/* Loading indicator */}
        <div className="fixed inset-0 flex items-center justify-center pointer-events-none">
          <div className="bg-neutral-900/90 rounded-ds-lg p-ds-4 flex flex-col items-center gap-ds-3">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-accent-500" />
            <p className="text-neutral-400 text-ds-body-sm">Loading race...</p>
          </div>
        </div>
      </div>
    )
  }

  // Error state
  if (error || !event) {
    return (
      <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-ds-4">
        <EmptyState
          icon={
            <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
          }
          title={error || 'Event not found'}
          description="The event you're looking for doesn't exist or isn't available."
          action={{
            label: 'Browse Events',
            onClick: () => navigate('/events'),
            variant: 'primary',
          }}
        />
      </div>
    )
  }

  // Tab props
  const tabProps = {
    eventId: eventId!,
    event,
    positions,
    leaderboard,
    favorites,
    onToggleFavorite: toggleFavorite,
    onVehicleSelect: handleVehicleSelect,
    selectedVehicleId,
    courseGeoJSON: event.course_geojson,
    isConnected,
  }

  return (
    <div className="flex flex-col h-screen bg-neutral-950">
      {/* Header */}
      <header className="bg-neutral-900 border-b border-neutral-800 px-ds-4 py-ds-3 safe-top flex-shrink-0">
        <div className="flex items-center justify-between">
          {/* Back button */}
          <button
            onClick={goBack}
            className="min-w-[44px] min-h-[44px] -ml-ds-2 flex items-center justify-center text-neutral-400 hover:text-neutral-50 transition-colors duration-ds-fast rounded-full hover:bg-neutral-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-400"
            aria-label="Back to events"
          >
            <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>

          {/* Event title */}
          <div className="flex-1 text-center min-w-0 px-ds-2">
            <h1 className="text-ds-heading text-neutral-50 truncate">{event.name}</h1>
            <div className="flex items-center justify-center gap-ds-2 mt-ds-1">
              <StatusBadge status={event.status} />
              {isConnected ? (
                <Badge variant="success" size="sm" dot>
                  Live
                </Badge>
              ) : (
                <Badge variant="warning" size="sm" dot pulse>
                  Connecting
                </Badge>
              )}
            </div>
          </div>

          {/* Home button */}
          <button
            onClick={() => navigate('/')}
            className="min-w-[44px] min-h-[44px] flex items-center justify-center text-neutral-400 hover:text-neutral-50 transition-colors duration-ds-fast rounded-full hover:bg-neutral-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-400"
            aria-label="Home"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-4 0a1 1 0 01-1-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 01-1 1h-2z" />
            </svg>
          </button>
        </div>
      </header>

      {/* Tab content */}
      <main className="flex-1 overflow-hidden">
        {activeTab === 'overview' && <OverviewTab {...tabProps} />}
        {activeTab === 'standings' && <StandingsTab {...tabProps} />}
        {activeTab === 'watch' && <WatchTab {...tabProps} />}
        {activeTab === 'tracker' && <TrackerTab {...tabProps} />}
      </main>

      {/* Tab bar */}
      <TabBar activeTab={activeTab} onTabChange={setActiveTab} />
    </div>
  )
}

/**
 * Event status badge using design system Badge
 */
function StatusBadge({ status }: { status: Event['status'] }) {
  const variants: Record<Event['status'], 'info' | 'success' | 'neutral'> = {
    upcoming: 'info',
    in_progress: 'success',
    finished: 'neutral',
  }

  const labels: Record<Event['status'], string> = {
    upcoming: 'Upcoming',
    in_progress: 'LIVE',
    finished: 'Finished',
  }

  return (
    <Badge
      variant={variants[status]}
      size="sm"
      dot={status === 'in_progress'}
      pulse={status === 'in_progress'}
    >
      {labels[status]}
    </Badge>
  )
}
