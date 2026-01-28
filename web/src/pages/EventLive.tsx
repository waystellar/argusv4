/**
 * Main event live page with map and leaderboard
 *
 * UI-15: Migrated to design system tokens (neutral-*, status-*, ds-*)
 * FIXED: P1-1 - Added skeleton screens for better initial load experience
 * FIXED: P2-3 - SSE-driven leaderboard with polling fallback
 * FIXED: P2-6 - Added checkpoint crossing notifications
 * PR-2 UX: Added connection quality metrics and debug panel
 */
import { useEffect, useState, useCallback, useRef } from 'react'
import { useParams, useNavigate, useLocation } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { useEventStream } from '../hooks/useEventStream'
import { useCheckpointNotifications } from '../hooks/useCheckpointNotifications'
import { useEventStore } from '../stores/eventStore'
import { api } from '../api/client'
import Map from '../components/Map/Map'
import Leaderboard from '../components/Leaderboard/Leaderboard'
import Header from '../components/common/Header'
import ConnectionStatus from '../components/common/ConnectionStatus'
import SystemHealthIndicator from '../components/common/SystemHealthIndicator'
import { EventPageSkeleton, LeaderboardSkeleton, MapSkeleton } from '../components/common/Skeleton'
import { copyToClipboard } from '../utils/clipboard'

export default function EventLive() {
  const { eventId } = useParams<{ eventId: string }>()
  const navigate = useNavigate()
  const location = useLocation()
  const leaderboardRef = useRef<HTMLDivElement>(null)
  // FIXED: P2-3 - Get lastCheckpointMs to trigger leaderboard refresh on checkpoint events
  // PR-2 UX: Get connection metrics for quality monitoring
  const { isConnected, lastCheckpointMs, metrics } = useEventStream(eventId)

  // Handle #leaderboard hash navigation (from BottomNav "Standings" button)
  useEffect(() => {
    if (location.hash === '#leaderboard' && leaderboardRef.current) {
      // Small delay to ensure DOM is ready
      setTimeout(() => {
        leaderboardRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
      }, 100)
    }
  }, [location.hash])
  const positions = useEventStore((state) => state.getVisiblePositions())
  const setSelectedVehicle = useEventStore((state) => state.setSelectedVehicle)
  // FIXED: P2-1 - Get selected vehicle for map highlighting
  const selectedVehicleId = useEventStore((state) => state.selectedVehicleId)
  // FIXED: P2-3 - Get leaderboard from store (populated by SSE)
  const sseLeaderboard = useEventStore((state) => state.leaderboard)
  const setLeaderboard = useEventStore((state) => state.setLeaderboard)

  // Fetch event details
  const { data: event, isLoading: isLoadingEvent } = useQuery({
    queryKey: ['event', eventId],
    queryFn: () => api.getEvent(eventId!),
    enabled: !!eventId,
  })

  // FIXED: P2-3 - Fetch leaderboard via API (reduced polling, SSE triggers refetch)
  const { data: apiLeaderboard, isLoading: isLoadingLeaderboard, refetch: refetchLeaderboard } = useQuery({
    queryKey: ['leaderboard', eventId],
    queryFn: async () => {
      const data = await api.getLeaderboard(eventId!)
      // Populate store with API data
      const ts = data.ts ? new Date(data.ts).getTime() : Date.now()
      setLeaderboard(data.entries, ts)
      return data
    },
    enabled: !!eventId,
    refetchInterval: 30000, // FIXED: P2-3 - Reduced to 30s since SSE handles real-time
  })

  // FIXED: P2-3 - Refetch leaderboard when checkpoint event occurs
  useEffect(() => {
    if (lastCheckpointMs && eventId) {
      console.log('[EventLive] Checkpoint detected, refreshing leaderboard')
      refetchLeaderboard()
    }
  }, [lastCheckpointMs, eventId, refetchLeaderboard])

  // FIXED: P2-3 - Use SSE leaderboard if available, fallback to API data
  const leaderboardEntries = sseLeaderboard.length > 0 ? sseLeaderboard : (apiLeaderboard?.entries || [])

  // FIXED: P2-6 - Show checkpoint crossing notifications for selected vehicle
  useCheckpointNotifications({ enabled: !!eventId })

  // Share functionality
  const [showCopied, setShowCopied] = useState(false)

  const handleShare = useCallback(async () => {
    const shareUrl = window.location.href
    const shareTitle = event?.name || 'Live Race'
    const shareText = `Watch ${shareTitle} live on Argus Racing!`

    // Try Web Share API first (mobile)
    if (navigator.share) {
      try {
        await navigator.share({
          title: shareTitle,
          text: shareText,
          url: shareUrl,
        })
        return
      } catch (err) {
        // User cancelled or share failed, fall through to clipboard
        if ((err as Error).name === 'AbortError') return
      }
    }

    // Fallback: copy to clipboard
    const success = await copyToClipboard(shareUrl)
    if (success) {
      setShowCopied(true)
      setTimeout(() => setShowCopied(false), 2000)
    }
  }, [event?.name])

  const handleVehicleSelect = (vehicleId: string) => {
    setSelectedVehicle(vehicleId)
    navigate(`/events/${eventId}/vehicles/${vehicleId}`)
  }

  // FIXED: Show full page skeleton during initial event load
  if (isLoadingEvent) {
    return <EventPageSkeleton />
  }

  // Check if we're still waiting for initial position data from SSE
  const hasPositions = positions.length > 0
  const isInitializing = !hasPositions && isConnected

  // Format distance for display (in miles for US audiences)
  const formatDistance = (meters: number | null | undefined) => {
    if (!meters) return null
    const miles = meters / 1609.344
    if (miles >= 1) {
      return `${miles.toFixed(1)} mi`
    }
    // Show feet for short distances
    const feet = meters * 3.28084
    return `${Math.round(feet)} ft`
  }

  return (
    <div className="h-[100dvh] flex flex-col viewport-fixed">
      {/* Header */}
      <Header
        title={event?.name || 'Live Event'}
        subtitle={event?.status === 'in_progress' ? 'LIVE' : event?.status?.toUpperCase()}
      />

      {/* Event info bar - shows key metadata */}
      {event && (event.course_distance_m || event.total_laps > 1 || event.vehicle_count > 0) && (
        <div className="bg-neutral-900 px-ds-4 py-ds-2 flex items-center gap-ds-4 text-ds-caption text-neutral-400 border-b border-neutral-800 overflow-x-auto">
          {event.course_distance_m && (
            <div className="flex items-center gap-1.5 shrink-0">
              <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
              </svg>
              <span>{formatDistance(event.course_distance_m)}</span>
            </div>
          )}
          {event.total_laps > 1 && (
            <div className="flex items-center gap-1.5 shrink-0">
              <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              <span>{event.total_laps} laps</span>
            </div>
          )}
          {event.vehicle_count > 0 && (
            <div className="flex items-center gap-1.5 shrink-0">
              <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
              <span>{event.vehicle_count} vehicles</span>
            </div>
          )}
          {positions.length > 0 && positions.length !== event.vehicle_count && (
            <div className="flex items-center gap-1.5 shrink-0 text-status-success">
              <span className="w-2 h-2 bg-status-success rounded-full animate-pulse" />
              <span>{positions.length} active</span>
            </div>
          )}

          {/* Share button - pushed to the right */}
          <div className="flex-1" />
          <button
            onClick={handleShare}
            className="flex items-center gap-1.5 shrink-0 text-neutral-400 hover:text-white transition-colors duration-ds-fast px-ds-2 py-ds-1 rounded-ds-sm hover:bg-neutral-700/50 focus:outline-none focus:ring-2 focus:ring-accent-500"
            aria-label="Share event"
          >
            {showCopied ? (
              <>
                <svg className="w-3.5 h-3.5 text-status-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
                <span className="text-status-success">Copied!</span>
              </>
            ) : (
              <>
                <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" />
                </svg>
                <span>Share</span>
              </>
            )}
          </button>
        </div>
      )}

      {/* Connection status - PR-2 UX: Pass metrics for enhanced display */}
      <ConnectionStatus isConnected={isConnected} metrics={metrics} />

      {/* Map (takes remaining space) */}
      <div className="flex-1 relative">
        {/* FIXED: Show map skeleton while waiting for initial positions */}
        {isInitializing && (
          <div className="absolute inset-0 z-10">
            <MapSkeleton />
          </div>
        )}
        {/* FIXED: P2-1 - Pass selectedVehicleId for map highlighting */}
        {/* Pass course GeoJSON to display course line on map */}
        <Map
          positions={positions}
          onVehicleClick={handleVehicleSelect}
          selectedVehicleId={selectedVehicleId}
          courseGeoJSON={event?.course_geojson}
        />
      </div>

      {/* Leaderboard (bottom sheet) - pb-[60px] for bottom nav on mobile */}
      {/* id="leaderboard" enables hash navigation from BottomNav Standings button */}
      <div
        ref={leaderboardRef}
        id="leaderboard"
        className="bg-neutral-850 border-t border-neutral-700 max-h-[40vh] overflow-y-auto pb-[60px] md:pb-0 safe-area-bottom"
      >
        <div className="p-ds-2">
          <h2 className="text-ds-body-sm font-semibold text-neutral-400 uppercase tracking-wide px-ds-2 py-ds-1">
            Leaderboard
          </h2>
          {/* FIXED: Show skeleton while leaderboard is loading */}
          {/* FIXED: P2-3 - Use SSE leaderboard data with API fallback */}
          {isLoadingLeaderboard && leaderboardEntries.length === 0 ? (
            <LeaderboardSkeleton count={5} />
          ) : (
            <Leaderboard
              entries={leaderboardEntries}
              onVehicleClick={handleVehicleSelect}
            />
          )}
        </div>
      </div>

      {/* PR-2 UX: System health indicator for debugging (only shows when VITE_ENABLE_DEBUG_PANEL=true) */}
      <SystemHealthIndicator isConnected={isConnected} metrics={metrics} />
    </div>
  )
}
