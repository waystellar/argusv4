/**
 * Event Discovery Page - Mobile fan entry point
 *
 * FIXED: P1-2 - Added event discovery page for mobile fans
 * UI-12: Refactored to use design system tokens
 *
 * Shows live, upcoming, and past events for fans to browse.
 * Mobile-first design with high contrast for outdoor visibility.
 */
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Event } from '../api/client'
import { StatusPill, getEventStatusVariant, PageHeader, Spinner, SkeletonRect } from '../components/common'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

function EventCard({ event, onClick }: { event: Event; onClick: () => void }) {
  const isLive = event.status === 'in_progress'
  const isFinished = event.status === 'finished'

  // Format date for display
  const formatDate = (dateStr: string | null) => {
    if (!dateStr) return null
    const date = new Date(dateStr)
    return date.toLocaleDateString(undefined, {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
    })
  }

  // Format distance for display (in miles for US audiences)
  const formatDistance = (meters: number | null) => {
    if (!meters) return null
    const miles = meters / 1609.344
    if (miles >= 1) {
      return `${miles.toFixed(1)} mi`
    }
    // Show feet for short distances
    const feet = meters * 3.28084
    return `${Math.round(feet)} ft`
  }

  // Card styles based on status
  const cardStyles = isLive
    ? 'bg-status-success/10 border-status-success/50 hover:border-status-success'
    : isFinished
    ? 'bg-neutral-900 border-neutral-800 hover:border-neutral-700 opacity-80'
    : 'bg-neutral-900 border-neutral-700 hover:border-neutral-600'

  return (
    <button
      onClick={onClick}
      className={`w-full text-left p-ds-4 rounded-ds-lg border transition-all duration-ds-fast ${cardStyles}`}
    >
      <div className="flex items-start justify-between gap-ds-3">
        <div className="flex-1 min-w-0">
          {/* Event name */}
          <h3 className="text-ds-body font-bold text-neutral-50 truncate">{event.name}</h3>

          {/* Event details */}
          <div className="mt-ds-1 flex flex-wrap items-center gap-ds-2 text-ds-body-sm text-neutral-400">
            {event.scheduled_start && (
              <span>{formatDate(event.scheduled_start)}</span>
            )}
            {event.course_distance_m && (
              <>
                <span className="text-neutral-600">•</span>
                <span>{formatDistance(event.course_distance_m)}</span>
              </>
            )}
            {event.total_laps > 1 && (
              <>
                <span className="text-neutral-600">•</span>
                <span>{event.total_laps} laps</span>
              </>
            )}
            {event.vehicle_count > 0 && (
              <>
                <span className="text-neutral-600">•</span>
                <span>{event.vehicle_count} vehicle{event.vehicle_count !== 1 ? 's' : ''}</span>
              </>
            )}
          </div>
        </div>

        {/* Status badge */}
        <StatusPill
          label={isLive ? 'LIVE' : event.status === 'upcoming' ? 'UPCOMING' : 'FINISHED'}
          variant={getEventStatusVariant(event.status)}
          pulse={isLive}
        />
      </div>

      {/* Live indicator with CTA */}
      {isLive && (
        <div className="mt-ds-3 flex items-center gap-ds-2 text-status-success text-ds-body-sm">
          <span className="relative flex h-2 w-2">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-status-success opacity-75"></span>
            <span className="relative inline-flex rounded-full h-2 w-2 bg-status-success"></span>
          </span>
          Watch live now →
        </div>
      )}

      {/* View event CTA for non-live */}
      {!isLive && (
        <div className="mt-ds-3 text-accent-400 text-ds-body-sm">
          View Event →
        </div>
      )}
    </button>
  )
}

function EventSection({
  title,
  events,
  emptyMessage,
  onEventClick,
}: {
  title: string
  events: Event[]
  emptyMessage: string
  onEventClick: (eventId: string) => void
}) {
  if (events.length === 0) {
    return (
      <div className="mb-ds-6">
        <h2 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wide mb-ds-3">
          {title}
        </h2>
        <p className="text-neutral-500 text-ds-body-sm italic">{emptyMessage}</p>
      </div>
    )
  }

  return (
    <div className="mb-ds-6">
      <h2 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wide mb-ds-3">
        {title}
      </h2>
      <div className="space-y-ds-3">
        {events.map((event) => (
          <EventCard
            key={event.event_id}
            event={event}
            onClick={() => onEventClick(event.event_id)}
          />
        ))}
      </div>
    </div>
  )
}

function EventDiscoverySkeleton() {
  return (
    <div className="min-h-screen bg-neutral-950">
      {/* Header skeleton */}
      <div className="p-ds-4 border-b border-neutral-800 bg-neutral-900">
        <SkeletonRect className="h-8 w-48 mb-ds-2" />
        <SkeletonRect className="h-4 w-32" />
      </div>

      {/* Search bar skeleton */}
      <div className="p-ds-4 pb-ds-2">
        <SkeletonRect className="h-10 w-full rounded-ds-lg" />
      </div>

      {/* Section skeletons */}
      <div className="p-ds-4 pt-ds-2 space-y-ds-6">
        {[1, 2, 3].map((section) => (
          <div key={section} className="space-y-ds-3">
            <SkeletonRect className="h-4 w-24 mb-ds-3" />
            <SkeletonRect className="h-24 w-full rounded-ds-lg" />
            {section === 2 && <SkeletonRect className="h-24 w-full rounded-ds-lg" />}
          </div>
        ))}
      </div>
    </div>
  )
}

const INITIAL_RECENT_COUNT = 5
const LOAD_MORE_COUNT = 10

export default function EventDiscovery() {
  const navigate = useNavigate()
  const [recentEventsLimit, setRecentEventsLimit] = useState(INITIAL_RECENT_COUNT)
  const [searchQuery, setSearchQuery] = useState('')

  // Fetch all events
  const {
    data: events,
    isLoading,
    error,
    dataUpdatedAt,
    refetch,
    isFetching,
  } = useQuery({
    queryKey: ['events'],
    queryFn: async () => {
      const response = await fetch(`${API_BASE}/events`)
      if (!response.ok) throw new Error('Failed to fetch events')
      return response.json() as Promise<Event[]>
    },
    refetchInterval: 30000, // Refresh every 30s to catch new events
  })

  // Format last update time
  const formatLastUpdate = () => {
    if (!dataUpdatedAt) return null
    const seconds = Math.floor((Date.now() - dataUpdatedAt) / 1000)
    if (seconds < 5) return 'Just now'
    if (seconds < 60) return `${seconds}s ago`
    const minutes = Math.floor(seconds / 60)
    return `${minutes}m ago`
  }

  const handleEventClick = (eventId: string) => {
    navigate(`/events/${eventId}`)
  }

  const handleShowMore = () => {
    setRecentEventsLimit((prev) => prev + LOAD_MORE_COUNT)
  }

  // Filter events by search query
  const filteredEvents = events?.filter((e) => {
    if (!searchQuery.trim()) return true
    const query = searchQuery.toLowerCase()
    return e.name.toLowerCase().includes(query)
  }) || []

  // Categorize filtered events by status
  const liveEvents = filteredEvents.filter((e) => e.status === 'in_progress')
  const upcomingEvents = filteredEvents.filter((e) => e.status === 'upcoming')
  const finishedEvents = filteredEvents.filter((e) => e.status === 'finished')
  const hasMoreRecent = finishedEvents.length > recentEventsLimit

  // Reset recent limit when search changes
  const handleSearchChange = (value: string) => {
    setSearchQuery(value)
    setRecentEventsLimit(INITIAL_RECENT_COUNT)
  }

  if (isLoading) {
    return <EventDiscoverySkeleton />
  }

  if (error) {
    return (
      <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-ds-4">
        <div className="text-center max-w-sm">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-status-error/10 mb-ds-4">
            <svg className="w-8 h-8 text-status-error" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
          </div>
          <h2 className="text-ds-headline text-neutral-50 mb-ds-2">Unable to Load Events</h2>
          <p className="text-neutral-400 text-ds-body-sm mb-ds-6">
            Please check your connection and try again.
          </p>
          <button
            onClick={() => refetch()}
            className="px-ds-6 py-ds-3 bg-accent-600 hover:bg-accent-700 text-white rounded-ds-lg font-medium transition-colors duration-ds-fast"
          >
            Retry
          </button>
        </div>
      </div>
    )
  }

  const hasNoFilteredEvents = liveEvents.length === 0 && upcomingEvents.length === 0 && finishedEvents.length === 0
  const hasNoEventsAtAll = !events || events.length === 0
  const isSearchActive = searchQuery.trim().length > 0

  return (
    <div className="min-h-screen bg-neutral-950 safe-area-top has-bottom-nav">
      {/* Header */}
      <PageHeader
        title="Watch Live"
        subtitle={dataUpdatedAt ? `Updated ${formatLastUpdate()}` : 'Off-road racing events'}
        backTo="/"
        rightSlot={
          <button
            onClick={() => refetch()}
            disabled={isFetching}
            className="min-w-[44px] min-h-[44px] flex items-center justify-center text-neutral-400 hover:text-neutral-50 transition-colors duration-ds-fast disabled:opacity-50 rounded-full hover:bg-neutral-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-400"
            aria-label="Refresh events"
          >
            {isFetching ? (
              <Spinner size="sm" />
            ) : (
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
            )}
          </button>
        }
      />

      {/* Search bar */}
      <div className="p-ds-4 pb-ds-2">
        <div className="relative">
          <svg
            className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-500"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
          <input
            type="text"
            placeholder="Search events..."
            value={searchQuery}
            onChange={(e) => handleSearchChange(e.target.value)}
            className="w-full pl-10 pr-10 py-ds-3 bg-neutral-900 border border-neutral-700 rounded-ds-lg text-neutral-50 placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-accent-500 transition-colors duration-ds-fast"
          />
          {searchQuery && (
            <button
              onClick={() => handleSearchChange('')}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-neutral-400 hover:text-neutral-50 transition-colors duration-ds-fast"
              aria-label="Clear search"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          )}
        </div>
      </div>

      {/* Content */}
      <div className="p-ds-4 pt-ds-2">
        {hasNoEventsAtAll ? (
          <div className="text-center py-16">
            <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-neutral-800 mb-ds-4">
              <svg className="w-8 h-8 text-neutral-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
            </div>
            <h2 className="text-ds-headline text-neutral-50 mb-ds-2">No Events Yet</h2>
            <p className="text-neutral-400 text-ds-body-sm max-w-xs mx-auto">
              Check back soon for live racing events!
            </p>
          </div>
        ) : hasNoFilteredEvents && isSearchActive ? (
          <div className="text-center py-16">
            <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-neutral-800 mb-ds-4">
              <svg className="w-8 h-8 text-neutral-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </div>
            <h2 className="text-ds-headline text-neutral-50 mb-ds-2">No Matching Events</h2>
            <p className="text-neutral-400 text-ds-body-sm mb-ds-6">
              No events found for "{searchQuery}"
            </p>
            <button
              onClick={() => handleSearchChange('')}
              className="px-ds-4 py-ds-2 bg-neutral-800 hover:bg-neutral-700 text-neutral-200 rounded-ds-md transition-colors duration-ds-fast"
            >
              Clear Search
            </button>
          </div>
        ) : (
          <>
            {/* Live events first (most important) */}
            <EventSection
              title="Live Now"
              events={liveEvents}
              emptyMessage="No races currently in progress"
              onEventClick={handleEventClick}
            />

            {/* Upcoming events */}
            <EventSection
              title="Upcoming"
              events={upcomingEvents}
              emptyMessage="No upcoming races scheduled"
              onEventClick={handleEventClick}
            />

            {/* Past events */}
            <EventSection
              title="Recent"
              events={finishedEvents.slice(0, recentEventsLimit)}
              emptyMessage="No recent races"
              onEventClick={handleEventClick}
            />

            {/* Show More button for recent events */}
            {hasMoreRecent && (
              <div className="text-center mb-ds-6">
                <button
                  onClick={handleShowMore}
                  className="px-ds-6 py-ds-2 bg-neutral-800 hover:bg-neutral-700 text-neutral-200 text-ds-body-sm font-medium rounded-ds-lg transition-colors duration-ds-fast"
                >
                  Show More ({finishedEvents.length - recentEventsLimit} remaining)
                </button>
              </div>
            )}
          </>
        )}
      </div>

      {/* PWA Install hint */}
      <div className="p-ds-4 text-center border-t border-neutral-800 bg-neutral-900">
        <p className="text-neutral-500 text-ds-caption">
          Add to your home screen for the best experience
        </p>
      </div>
    </div>
  )
}
