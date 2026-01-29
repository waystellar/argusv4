/**
 * Watch Tab - Grid of truck video tiles with thumbnails
 *
 * FAN-WATCH-1: Truck Tile Grid with 60s Thumbnail Refresh
 *
 * Features:
 * - Fetches all registered vehicles from /api/v1/production/events/{eventId}/stream-states
 * - Responsive grid: 2 cols (iPhone), 3-4 cols (iPad), 4-6 cols (Desktop)
 * - YouTube thumbnail images refreshed every ~60s
 * - Click tile → navigate to vehicle detail page
 * - Live status overlay when vehicle is streaming
 *
 * UI-4 Update: Refactored to use design system tokens and components
 */
import { useState, useEffect, useMemo, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
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

/**
 * Extract YouTube video ID from various URL formats
 */
function extractYouTubeVideoId(url: string | null): string | null {
  if (!url) return null
  const patterns = [
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]+)/,
    /youtube\.com\/live\/([a-zA-Z0-9_-]+)/,
  ]
  for (const pattern of patterns) {
    const match = url.match(pattern)
    if (match && match[1]) {
      return match[1]
    }
  }
  return null
}

/**
 * Get YouTube thumbnail URL with cache buster (refreshes every ~60s)
 */
function getYouTubeThumbnailUrl(videoId: string | null): string | null {
  if (!videoId) return null
  // Cache buster: changes every 60 seconds
  const cacheBuster = Math.floor(Date.now() / 60000)
  return `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg?t=${cacheBuster}`
}

export default function WatchTab({
  eventId,
  positions,
  favorites,
}: TabProps) {
  const navigate = useNavigate()
  const [streamStates, setStreamStates] = useState<StreamState[]>([])
  const [hasFetched, setHasFetched] = useState(false)
  // Trigger thumbnail refresh every 60s
  const [thumbnailRefreshKey, setThumbnailRefreshKey] = useState(0)

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

  // Thumbnail refresh timer (60 seconds)
  useEffect(() => {
    const interval = setInterval(() => {
      setThumbnailRefreshKey((k) => k + 1)
    }, 60000)
    return () => clearInterval(interval)
  }, [])

  // Build camera feeds by merging stream states with position data
  const cameraFeeds = useMemo(() => {
    // Build feed list from all known vehicles (stream states + positions)
    const seenVehicleIds = new Set<string>()
    const feeds: CameraFeed[] = []

    // First, add vehicles from stream states (these are all registered vehicles)
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

  // Navigate to vehicle detail page
  const handleTileClick = useCallback(
    (vehicleId: string) => {
      navigate(`/events/${eventId}/vehicles/${vehicleId}`)
    },
    [navigate, eventId]
  )

  return (
    <div className="flex flex-col h-full bg-neutral-950">
      {/* Header section */}
      <div className="flex-shrink-0">
        {/* Live count banner */}
        {liveCount > 0 && (
          <div className="px-ds-4 py-ds-2 bg-status-error/10 border-b border-status-error/20">
            <span className="text-ds-caption font-semibold text-status-error flex items-center gap-ds-1">
              <span className="w-2 h-2 rounded-full bg-status-error animate-pulse" />
              {liveCount} {liveCount === 1 ? 'truck' : 'trucks'} streaming live
            </span>
          </div>
        )}
      </div>

      {/* Grid of truck tiles */}
      <div className="flex-1 overflow-y-auto bg-neutral-950 pb-safe">
        <div className="px-ds-3 py-ds-3">
          {cameraFeeds.length === 0 && hasFetched ? (
            <DSEmptyState
              icon={
                <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                    d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
                </svg>
              }
              title="No trucks registered"
              description="Trucks will appear here once they're registered for this event."
            />
          ) : (
            /* Responsive grid: 2 cols mobile, 3-4 tablet, 4-6 desktop */
            <div
              id="watchGrid"
              className="grid gap-ds-3"
              style={{
                gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))',
              }}
            >
              {cameraFeeds.map((feed) => (
                <TruckTile
                  key={feed.vehicle_id}
                  feed={feed}
                  isFavorite={favorites.has(feed.vehicle_id)}
                  onClick={() => handleTileClick(feed.vehicle_id)}
                  refreshKey={thumbnailRefreshKey}
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
 * Truck tile with thumbnail and banner
 * FAN-WATCH-1: Shows YouTube thumbnail with 60s refresh
 */
function TruckTile({
  feed,
  isFavorite,
  onClick,
  refreshKey,
}: {
  feed: CameraFeed
  isFavorite: boolean
  onClick: () => void
  refreshKey: number
}) {
  const [imgError, setImgError] = useState(false)

  // Extract video ID and get thumbnail URL
  const videoId = extractYouTubeVideoId(feed.youtube_url)
  // Include refreshKey in dependency to force re-render with new cache buster
  const thumbnailUrl = useMemo(
    () => getYouTubeThumbnailUrl(videoId),
    [videoId, refreshKey]
  )

  // Reset error state when thumbnail URL changes
  useEffect(() => {
    setImgError(false)
  }, [thumbnailUrl])

  return (
    <button
      onClick={onClick}
      data-testid="truck-tile"
      className={`relative rounded-ds-lg overflow-hidden text-left transition-all duration-ds-fast hover:ring-2 hover:ring-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500 ${
        feed.is_live
          ? 'ring-1 ring-status-error/50'
          : isFavorite
            ? 'ring-1 ring-status-warning/30'
            : ''
      }`}
    >
      {/* Thumbnail area - 16:9 aspect ratio */}
      <div className="relative aspect-video bg-neutral-800">
        {thumbnailUrl && !imgError ? (
          <img
            src={thumbnailUrl}
            alt={`#${feed.vehicle_number} ${feed.team_name}`}
            className="absolute inset-0 w-full h-full object-cover"
            onError={() => setImgError(true)}
            loading="lazy"
          />
        ) : (
          /* Placeholder when no video linked */
          <div className="absolute inset-0 flex flex-col items-center justify-center text-neutral-600">
            <svg className="w-10 h-10 mb-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
            </svg>
            <span className="text-ds-caption">No video linked</span>
          </div>
        )}

        {/* Live badge overlay */}
        {feed.is_live && (
          <div className="absolute top-ds-2 left-ds-2">
            <Badge variant="error" size="sm" dot pulse>LIVE</Badge>
          </div>
        )}

        {/* Favorite star overlay */}
        {isFavorite && (
          <div className="absolute top-ds-2 right-ds-2">
            <svg className="w-5 h-5 text-status-warning drop-shadow-md" fill="currentColor" viewBox="0 0 24 24">
              <path d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
            </svg>
          </div>
        )}
      </div>

      {/* Banner: #number — teamName */}
      <div
        className={`px-ds-2 py-ds-2 ${
          feed.is_live
            ? 'bg-status-error/20'
            : 'bg-neutral-800'
        }`}
        data-testid="truck-tile-banner"
      >
        <div className="text-ds-body-sm font-bold text-neutral-50 truncate">
          #{feed.vehicle_number}
        </div>
        <div className="text-ds-caption text-neutral-400 truncate">
          {feed.team_name}
        </div>
      </div>
    </button>
  )
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1)
}
