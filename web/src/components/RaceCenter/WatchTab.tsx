/**
 * Watch Tab - Video feeds from vehicles and race production
 *
 * Features:
 * - Fetches real stream states from /api/v1/production/events/{eventId}/stream-states
 * - Grid of available camera feeds with Live/Offline badges
 * - YouTube embed support
 * - Favorite vehicles' feeds highlighted
 * - Clear empty state when no feeds are configured
 *
 * UI-4 Update: Refactored to use design system tokens and components
 */
import { useState, useEffect, useMemo, useCallback } from 'react'
import { Badge, EmptyState as DSEmptyState } from '../ui'
import type { TabProps, CameraFeed } from './types'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

interface StreamState {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  is_live: boolean
  streaming_status: string
  active_camera: string | null
  youtube_url: string | null
  youtube_embed_url: string | null
  streaming_uptime_s: number | null
}

interface StreamStatesResponse {
  event_id: string
  vehicles: StreamState[]
  live_count: number
}

export default function WatchTab({
  eventId,
  positions,
  favorites,
}: TabProps) {
  const [selectedFeed, setSelectedFeed] = useState<CameraFeed | null>(null)
  const [streamStates, setStreamStates] = useState<StreamState[]>([])
  const [hasFetched, setHasFetched] = useState(false)

  // Fetch stream states from the production API (public, no auth required)
  const fetchStreamStates = useCallback(async () => {
    try {
      const response = await fetch(
        `${API_BASE}/production/events/${eventId}/stream-states`
      )
      if (response.ok) {
        const data: StreamStatesResponse = await response.json()
        setStreamStates(data.vehicles)
      }
    } catch (err) {
      console.warn('Failed to fetch stream states:', err)
    } finally {
      setHasFetched(true)
    }
  }, [eventId])

  // Fetch on mount and poll every 10 seconds
  useEffect(() => {
    fetchStreamStates()
    const interval = setInterval(fetchStreamStates, 10000)
    return () => clearInterval(interval)
  }, [fetchStreamStates])

  // Build camera feeds by merging stream states with position data
  const cameraFeeds = useMemo(() => {
    // Index stream states by vehicle_id for fast lookup
    const streamMap = new Map<string, StreamState>()
    for (const s of streamStates) {
      streamMap.set(s.vehicle_id, s)
    }

    // Build feed list from all known vehicles (positions + stream states)
    const seenVehicleIds = new Set<string>()
    const feeds: CameraFeed[] = []

    // First, add vehicles from stream states (these have feed data)
    for (const s of streamStates) {
      seenVehicleIds.add(s.vehicle_id)
      feeds.push({
        vehicle_id: s.vehicle_id,
        vehicle_number: s.vehicle_number,
        team_name: s.team_name,
        camera_name: s.active_camera
          ? `#${s.vehicle_number} ${capitalize(s.active_camera)}`
          : `#${s.vehicle_number} Onboard`,
        youtube_url: s.youtube_url,
        is_live: s.is_live,
      })
    }

    // Then add vehicles from positions that don't have stream state entries
    for (const p of positions) {
      if (!seenVehicleIds.has(p.vehicle_id)) {
        seenVehicleIds.add(p.vehicle_id)
        feeds.push({
          vehicle_id: p.vehicle_id,
          vehicle_number: p.vehicle_number,
          team_name: p.team_name,
          camera_name: `#${p.vehicle_number} Onboard`,
          youtube_url: null,
          is_live: false,
        })
      }
    }

    // Sort: live first, then favorites, then by vehicle number
    feeds.sort((a, b) => {
      // Live feeds first
      if (a.is_live !== b.is_live) return a.is_live ? -1 : 1
      // Then favorites
      const aFav = favorites.has(a.vehicle_id) ? 0 : 1
      const bFav = favorites.has(b.vehicle_id) ? 0 : 1
      if (aFav !== bFav) return aFav - bFav
      // Then by number
      return parseInt(a.vehicle_number) - parseInt(b.vehicle_number)
    })

    return feeds
  }, [streamStates, positions, favorites])

  const liveCount = useMemo(
    () => cameraFeeds.filter((f) => f.is_live).length,
    [cameraFeeds]
  )

  const favoriteFeedsCount = useMemo(
    () => cameraFeeds.filter((f) => favorites.has(f.vehicle_id)).length,
    [cameraFeeds, favorites]
  )

  // Auto-select first live feed if nothing selected
  useEffect(() => {
    if (!selectedFeed && cameraFeeds.length > 0) {
      const firstLive = cameraFeeds.find((f) => f.is_live && f.youtube_url)
      if (firstLive) {
        setSelectedFeed(firstLive)
      }
    }
  }, [cameraFeeds, selectedFeed])

  return (
    <div className="flex flex-col h-full bg-neutral-950">
      {/* Video player area - focal point */}
      <div className="relative bg-neutral-950 aspect-video w-full flex-shrink-0 border-b border-neutral-800">
        {selectedFeed && selectedFeed.youtube_url ? (
          <iframe
            src={getYouTubeEmbedUrl(selectedFeed.youtube_url)}
            className="absolute inset-0 w-full h-full"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowFullScreen
          />
        ) : (
          <div className="absolute inset-0 flex flex-col items-center justify-center">
            <svg className="w-16 h-16 mb-ds-3 text-neutral-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
            </svg>
            <p className="text-ds-body font-medium text-neutral-400">
              {selectedFeed ? 'Stream not available' : 'Select a camera feed'}
            </p>
            <p className="text-ds-body-sm text-neutral-600 mt-ds-1">
              {selectedFeed
                ? 'This feed is not currently streaming'
                : liveCount > 0
                  ? 'Choose from the live feeds below'
                  : 'Choose from the feeds below'}
            </p>
          </div>
        )}

        {/* Live indicator */}
        {selectedFeed?.is_live && (
          <div className="absolute top-ds-3 left-ds-3">
            <Badge variant="error" dot pulse>LIVE</Badge>
          </div>
        )}
      </div>

      {/* Feed selection */}
      <div className="flex-1 overflow-y-auto bg-neutral-950 pb-safe">
        {/* Live count banner */}
        {liveCount > 0 && (
          <div className="px-ds-4 py-ds-2 bg-status-error/10 border-b border-status-error/20">
            <span className="text-ds-caption font-semibold text-status-error flex items-center gap-ds-1">
              <span className="w-2 h-2 rounded-full bg-status-error animate-pulse" />
              {liveCount} {liveCount === 1 ? 'feed' : 'feeds'} live now
            </span>
          </div>
        )}

        {/* Section: Favorites */}
        {favoriteFeedsCount > 0 && (
          <div className="px-ds-4 py-ds-3 border-b border-neutral-800">
            <h3 className="text-ds-caption font-semibold text-status-warning uppercase tracking-wide mb-ds-2 flex items-center gap-ds-1">
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                <path d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
              </svg>
              Your Favorites
            </h3>
            <div className="grid grid-cols-2 gap-ds-2">
              {cameraFeeds
                .filter((f) => favorites.has(f.vehicle_id))
                .map((feed) => (
                  <FeedCard
                    key={feed.vehicle_id}
                    feed={feed}
                    isSelected={selectedFeed?.vehicle_id === feed.vehicle_id}
                    isFavorite={true}
                    onSelect={() => setSelectedFeed(feed)}
                  />
                ))}
            </div>
          </div>
        )}

        {/* Section: All Feeds */}
        <div className="px-ds-4 py-ds-3">
          <h3 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wide mb-ds-2">
            {favoriteFeedsCount > 0 ? 'All Cameras' : 'Available Cameras'}
          </h3>

          {cameraFeeds.length === 0 && hasFetched ? (
            <DSEmptyState
              icon={
                <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                    d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
                </svg>
              }
              title="No video feeds yet"
              description="Feeds will appear here when teams start streaming. Check back when the race is live."
            />
          ) : (
            <div className="grid grid-cols-2 gap-ds-2">
              {cameraFeeds
                .filter((f) => !favorites.has(f.vehicle_id))
                .map((feed) => (
                  <FeedCard
                    key={feed.vehicle_id}
                    feed={feed}
                    isSelected={selectedFeed?.vehicle_id === feed.vehicle_id}
                    isFavorite={false}
                    onSelect={() => setSelectedFeed(feed)}
                  />
                ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

/**
 * Camera feed card - using design system tokens
 */
function FeedCard({
  feed,
  isSelected,
  isFavorite,
  onSelect,
}: {
  feed: CameraFeed
  isSelected: boolean
  isFavorite: boolean
  onSelect: () => void
}) {
  return (
    <button
      onClick={onSelect}
      data-testid="feed-card"
      className={`relative min-h-[72px] p-ds-3 rounded-ds-lg text-left transition-all duration-ds-fast ${
        isSelected
          ? 'bg-accent-600/30 ring-2 ring-accent-500'
          : feed.is_live
            ? 'bg-neutral-800/80 hover:bg-neutral-800 ring-1 ring-status-error/30'
            : 'bg-neutral-800/50 hover:bg-neutral-800'
      }`}
    >
      {/* Live badge */}
      {feed.is_live && (
        <div className="absolute top-ds-2 right-ds-2">
          <Badge variant="error" size="sm" dot pulse>LIVE</Badge>
        </div>
      )}

      {/* Offline indicator */}
      {!feed.is_live && feed.youtube_url && (
        <div className="absolute top-ds-2 right-ds-2">
          <Badge variant="neutral" size="sm">OFFLINE</Badge>
        </div>
      )}

      {/* Content */}
      <div className="flex items-center gap-ds-2">
        {/* Icon or number */}
        <div
          className={`w-10 h-10 rounded-ds-md flex items-center justify-center shrink-0 ${
            feed.is_live
              ? 'bg-status-error'
              : isFavorite
              ? 'bg-status-warning'
              : 'bg-neutral-700'
          }`}
        >
          <span className="text-ds-body-sm font-bold text-white">#{feed.vehicle_number}</span>
        </div>

        {/* Text */}
        <div className="flex-1 min-w-0">
          <div className="text-ds-body-sm font-medium text-neutral-50 truncate">
            {feed.camera_name}
          </div>
          <div className="text-ds-caption text-neutral-500 truncate">
            {feed.team_name}
          </div>
        </div>
      </div>
    </button>
  )
}

/**
 * Convert YouTube URL to embed URL
 */
function getYouTubeEmbedUrl(url: string): string {
  // Handle various YouTube URL formats
  const patterns = [
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]+)/,
    /youtube\.com\/live\/([a-zA-Z0-9_-]+)/,
  ]

  for (const pattern of patterns) {
    const match = url.match(pattern)
    if (match && match[1]) {
      return `https://www.youtube.com/embed/${match[1]}?autoplay=1&modestbranding=1`
    }
  }

  // Fallback: assume it's already an embed URL or return as-is
  return url
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1)
}
