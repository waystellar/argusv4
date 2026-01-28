/**
 * Vehicle detail page with YouTube embed and telemetry
 *
 * UI-16: Migrated to design system tokens (neutral-*, status-*, accent-*, ds-*)
 * UI-25: Completed migration — replaced remaining non-DS font sizes and gaps
 * HIGH CONTRAST design for outdoor visibility.
 * Includes stale data detection and color-coded thresholds.
 *
 * FIXED: P2-3 - Uses SSE-driven leaderboard with polling fallback
 * FIXED: P2-6 - Shows checkpoint crossing notifications for this vehicle
 */
import { useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { useEffect, useRef, useState, useMemo, useCallback } from 'react'
import { useEventStream } from '../hooks/useEventStream'
import { useCheckpointNotifications } from '../hooks/useCheckpointNotifications'
import { useEventStore } from '../stores/eventStore'
import { api } from '../api/client'
import { PageHeader } from '../components/common'
import ConnectionStatus from '../components/common/ConnectionStatus'
import YouTubeEmbed from '../components/VehicleDetail/YouTubeEmbed'
import TelemetryTile, { TelemetryTileSkeleton } from '../components/VehicleDetail/TelemetryTile'
import { PositionBadgeSkeleton, VideoSkeleton } from '../components/common/Skeleton'
import { copyToClipboard } from '../utils/clipboard'

// PROMPT 4: Stream state interface - single source of truth for racer stream
interface RacerStreamState {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  is_live: boolean
  streaming_status: 'idle' | 'starting' | 'live' | 'error'
  active_camera: string | null
  youtube_url: string | null
  youtube_embed_url: string | null
  last_error: string | null
  streaming_started_at: number | null
  streaming_uptime_s: number | null
  updated_at: string
}

// PROMPT 5: Fan telemetry response - shows only what team has allowed for fans
interface FanTelemetryResponse {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  telemetry: Record<string, number | string | null>
  last_update_ms: number | null
}

// Format camera name for display
function formatCameraName(name: string): string {
  const names: Record<string, string> = {
    chase: 'Chase',
    pov: 'POV',
    roof: 'Roof',
    front: 'Front',
    rear: 'Rear',
    bumper: 'Bumper',
  }
  return names[name.toLowerCase()] || name.charAt(0).toUpperCase() + name.slice(1)
}

// Extended position type that may include telemetry
interface ExtendedPosition {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  lat: number
  lon: number
  speed_mps: number | null
  heading_deg: number | null
  last_checkpoint: number | null
  last_update_ms: number
  // Extended telemetry (if visible to viewer)
  rpm?: number
  gear?: number
  throttle_pct?: number
  coolant_temp?: number
  oil_pressure?: number
  fuel_pressure?: number
  heart_rate?: number
  // NOTE: Suspension fields removed - not currently in use
}

export default function VehiclePage() {
  const { eventId, vehicleId } = useParams<{ eventId: string; vehicleId: string }>()
  // FIXED: P2-3 - Get lastCheckpointMs for leaderboard refresh trigger
  const { isConnected, lastCheckpointMs } = useEventStream(eventId)

  // FIXED: P2-6 - Show checkpoint notifications for this vehicle
  useCheckpointNotifications({
    vehicleIds: vehicleId ? [vehicleId] : undefined,
    enabled: !!eventId && !!vehicleId,
  })

  // Get position from store (may include extended telemetry)
  const position = useEventStore((state) =>
    vehicleId ? state.positions.get(vehicleId) : null
  ) as ExtendedPosition | null

  // FIXED: P2-3 - Get leaderboard from store (SSE data)
  const sseLeaderboard = useEventStore((state) => state.leaderboard)
  const setLeaderboard = useEventStore((state) => state.setLeaderboard)

  // FIXED: P2-3 - Fetch leaderboard via API (reduced polling, SSE triggers refetch)
  const { data: apiLeaderboard, refetch: refetchLeaderboard } = useQuery({
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
      refetchLeaderboard()
    }
  }, [lastCheckpointMs, eventId, refetchLeaderboard])

  // FIXED: P2-3 - Use SSE leaderboard if available, fallback to API data
  const leaderboardEntries = sseLeaderboard.length > 0 ? sseLeaderboard : (apiLeaderboard?.entries || [])

  // PROMPT 4: Fetch stream state - single source of truth for this vehicle's stream
  const { data: streamState, isLoading: isLoadingStreamState } = useQuery<RacerStreamState>({
    queryKey: ['stream-state', eventId, vehicleId],
    queryFn: async () => {
      const res = await fetch(
        `${import.meta.env.VITE_API_URL || '/api/v1'}/production/events/${eventId}/vehicles/${vehicleId}/stream-state`
      )
      if (!res.ok) throw new Error('Failed to fetch stream state')
      return res.json()
    },
    enabled: !!eventId && !!vehicleId,
    refetchInterval: 5000, // Poll every 5s to meet ~10s update requirement
  })

  // PROMPT 5: Fetch fan-visible telemetry - supplements SSE data
  const { data: fanTelemetry } = useQuery<FanTelemetryResponse>({
    queryKey: ['fan-telemetry', eventId, vehicleId],
    queryFn: async () => {
      const res = await fetch(
        `${import.meta.env.VITE_API_URL || '/api/v1'}/production/events/${eventId}/vehicles/${vehicleId}/telemetry/fan`
      )
      if (!res.ok) throw new Error('Failed to fetch fan telemetry')
      return res.json()
    },
    enabled: !!eventId && !!vehicleId,
    refetchInterval: 2000, // Poll every 2s for real-time feel
  })

  // Fetch available camera feeds for this event (fallback for when stream is not live)
  const { data: cameras } = useQuery({
    queryKey: ['cameras', eventId],
    queryFn: async () => {
      const res = await fetch(`${import.meta.env.VITE_API_URL || '/api/v1'}/production/events/${eventId}/cameras`)
      if (!res.ok) return []
      return res.json()
    },
    enabled: !!eventId,
    refetchInterval: 30000, // Refresh every 30s
  })

  // Find video feeds for this vehicle
  const vehicleCameras = cameras?.filter((cam: { vehicle_id: string }) => cam.vehicle_id === vehicleId) || []

  // PROMPT 4: Determine which camera to show
  // Priority: 1. Actively streaming camera from stream state
  //           2. User-selected camera (manual override)
  //           3. Default to chase cam
  const [manualCameraOverride, setManualCameraOverride] = useState<string | null>(null)

  // Get the active camera from stream state
  const activeStreamingCamera = streamState?.is_live ? streamState.active_camera : null

  // Determine which camera index to display
  const selectedCameraIndex = useMemo(() => {
    // If user manually selected a camera, use that
    if (manualCameraOverride) {
      const overrideIndex = vehicleCameras.findIndex(
        (cam: { camera_name: string }) => cam.camera_name === manualCameraOverride
      )
      if (overrideIndex >= 0) return overrideIndex
    }

    // If stream is live, show the streaming camera
    if (activeStreamingCamera) {
      const activeIndex = vehicleCameras.findIndex(
        (cam: { camera_name: string }) => cam.camera_name === activeStreamingCamera
      )
      if (activeIndex >= 0) return activeIndex
    }

    // Default to chase cam or first available
    const chaseIndex = vehicleCameras.findIndex((cam: { camera_name: string }) => cam.camera_name === 'chase')
    return chaseIndex >= 0 ? chaseIndex : 0
  }, [vehicleCameras, manualCameraOverride, activeStreamingCamera])

  // Reset manual override when stream state changes to a new camera
  useEffect(() => {
    if (activeStreamingCamera && manualCameraOverride !== activeStreamingCamera) {
      // Stream switched cameras - clear manual override to show the new stream
      setManualCameraOverride(null)
    }
  }, [activeStreamingCamera])

  const currentCamera = vehicleCameras[selectedCameraIndex] || vehicleCameras[0]
  const hasMultipleCameras = vehicleCameras.length > 1

  // PROMPT 4 + TEAM-2: Determine video URL to display
  // Priority: stream state (live) → camera embed_url → camera youtube_url
  const videoUrl = useMemo(() => {
    // If stream is live and we have a URL, use it
    if (streamState?.is_live && streamState.youtube_url) {
      return streamState.youtube_url
    }
    // Fallback to camera feed from database
    return currentCamera?.youtube_url || ''
  }, [streamState, currentCamera])

  // TEAM-2: Use server-computed embed_url when available (from cameras endpoint)
  const serverEmbedUrl = useMemo(() => {
    if (streamState?.is_live && streamState.youtube_embed_url) {
      return streamState.youtube_embed_url
    }
    return currentCamera?.embed_url || ''
  }, [streamState, currentCamera])

  // Extract YouTube video ID from URL (client-side fallback)
  const extractVideoId = (url: string): string | null => {
    if (!url) return null
    const match = url.match(/(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=|live\/))([^?&/]+)/)
    return match ? match[1] : null
  }

  // TEAM-2: Prefer server embed URL, fall back to client extraction
  const videoId = useMemo(() => {
    if (serverEmbedUrl) {
      // Extract video ID from embed URL
      const embedMatch = serverEmbedUrl.match(/embed\/([^?&/]+)/)
      if (embedMatch) return embedMatch[1]
    }
    return extractVideoId(videoUrl)
  }, [serverEmbedUrl, videoUrl])

  // Share functionality
  const [showCopied, setShowCopied] = useState(false)
  const handleShare = useCallback(async () => {
    const shareUrl = window.location.href
    const shareTitle = `#${position?.vehicle_number || ''} - ${position?.team_name || 'Live'}`
    const shareText = `Watch ${shareTitle} live on Argus Racing!`

    if (navigator.share) {
      try {
        await navigator.share({ title: shareTitle, text: shareText, url: shareUrl })
        return
      } catch (err) {
        if ((err as Error).name === 'AbortError') return
      }
    }

    const success = await copyToClipboard(shareUrl)
    if (success) {
      setShowCopied(true)
      setTimeout(() => setShowCopied(false), 2000)
    }
  }, [position?.vehicle_number, position?.team_name])

  // FIXED: P2-3 - Find this vehicle's position using SSE/API combined leaderboard
  const leaderboardEntry = useMemo(() =>
    leaderboardEntries.find((e) => e.vehicle_id === vehicleId),
    [leaderboardEntries, vehicleId]
  )

  // Convert m/s to mph
  const speedMph = position?.speed_mps ? Math.round(position.speed_mps * 2.237) : null

  // Get last update timestamp for stale detection
  const lastUpdateMs = position?.last_update_ms

  // PROMPT 5: Check for telemetry data from both SSE position and API
  // Use fanTelemetry API response as primary source, fallback to SSE position
  const telemetryData = useMemo(() => {
    const data: Record<string, number | null> = {}

    // Start with SSE position data
    if (position) {
      if (position.rpm !== undefined) data.rpm = position.rpm
      if (position.gear !== undefined) data.gear = position.gear
      if (position.throttle_pct !== undefined) data.throttle_pct = position.throttle_pct
      if (position.coolant_temp !== undefined) data.coolant_temp_c = position.coolant_temp
      if (position.oil_pressure !== undefined) data.oil_pressure_psi = position.oil_pressure
      if (position.fuel_pressure !== undefined) data.fuel_pressure_psi = position.fuel_pressure
      if (position.heart_rate !== undefined) data.heart_rate = position.heart_rate
    }

    // Override with API data (more reliable, explicit fan-visible fields)
    if (fanTelemetry?.telemetry) {
      Object.entries(fanTelemetry.telemetry).forEach(([key, value]) => {
        if (value !== null && typeof value === 'number') {
          data[key] = value
        }
      })
    }

    return data
  }, [position, fanTelemetry])

  // Check what telemetry categories are available
  const hasEngineTelemetry = telemetryData.rpm !== undefined ||
    telemetryData.gear !== undefined ||
    telemetryData.throttle_pct !== undefined
  const hasAdvancedTelemetry = telemetryData.coolant_temp_c !== undefined ||
    telemetryData.oil_pressure_psi !== undefined ||
    telemetryData.fuel_pressure_psi !== undefined
  const hasHeartRate = telemetryData.heart_rate !== undefined

  // PROMPT 5: Check if team has shared any telemetry with fans
  const hasFanTelemetry = Object.keys(telemetryData).length > 0

  // FIXED: P1-1 - Determine if we're in initial loading state (no position data yet)
  const isInitialLoading = !position && isConnected
  // FIXED: P2-3 - Use combined leaderboard entries for loading state
  const isLoadingLeaderboard = leaderboardEntries.length === 0 && !!eventId

  // Screen Wake Lock for Pit Crew mode - keeps screen on while viewing vehicle telemetry
  const wakeLockRef = useRef<WakeLockSentinel | null>(null)
  const [wakeLockActive, setWakeLockActive] = useState(false)

  useEffect(() => {
    const requestWakeLock = async () => {
      if ('wakeLock' in navigator) {
        try {
          wakeLockRef.current = await navigator.wakeLock.request('screen')
          setWakeLockActive(true)
          console.log('[WakeLock] Screen wake lock acquired')

          wakeLockRef.current.addEventListener('release', () => {
            setWakeLockActive(false)
            console.log('[WakeLock] Screen wake lock released')
          })
        } catch (err) {
          console.warn('[WakeLock] Failed to acquire:', err)
        }
      }
    }

    // Request wake lock on mount
    requestWakeLock()

    // Re-acquire on visibility change (when user returns to tab)
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible' && !wakeLockRef.current) {
        requestWakeLock()
      }
    }
    document.addEventListener('visibilitychange', handleVisibilityChange)

    // Cleanup on unmount
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange)
      if (wakeLockRef.current) {
        wakeLockRef.current.release()
        wakeLockRef.current = null
      }
    }
  }, [])

  return (
    <div className="h-[100dvh] flex flex-col viewport-fixed">
      {/* Header with back button */}
      <PageHeader
        title={`#${position?.vehicle_number || '---'}`}
        subtitle={position?.team_name || 'Loading...'}
        backTo={`/events/${eventId}`}
        backLabel="Back to race"
      />

      {/* Connection status */}
      <ConnectionStatus isConnected={isConnected} />

      {/* Main content - scrollable */}
      <div className="flex-1 overflow-y-auto">
        {/* PROMPT 4: YouTube embed with fallback for offline streams */}
        <div className="aspect-video bg-black relative">
          {isLoadingStreamState && !cameras ? (
            <VideoSkeleton />
          ) : videoId ? (
            <YouTubeEmbed
              videoId={videoId}
              vehicleNumber={position?.vehicle_number}
            />
          ) : (
            // Fallback when no video is available
            <div className="w-full h-full flex flex-col items-center justify-center text-neutral-400">
              <svg className="w-16 h-16 mb-ds-4 text-neutral-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
              <p className="text-ds-body font-medium mb-ds-1">
                {streamState?.streaming_status === 'error' ? 'Stream Error' : 'Stream Offline'}
              </p>
              <p className="text-ds-body-sm text-neutral-500">
                {streamState?.last_error || 'This vehicle is not currently streaming'}
              </p>
              {streamState?.streaming_status === 'starting' && (
                <p className="text-ds-body-sm text-status-warning mt-ds-2 flex items-center gap-ds-2">
                  <span className="w-2 h-2 bg-status-warning rounded-full animate-pulse" />
                  Stream starting soon...
                </p>
              )}
            </div>
          )}
        </div>

        {/* PROMPT 4: Camera controls bar with live status indicator */}
        <div className="bg-neutral-900/90 px-ds-3 py-ds-2 flex items-center justify-between text-ds-caption">
          {/* Stream status + Camera switcher */}
          <div className="flex items-center gap-ds-3">
            {/* Live indicator */}
            {streamState?.is_live ? (
              <div className="flex items-center gap-1.5 px-ds-2 py-ds-1 bg-status-error/80 rounded-ds-sm">
                <span className="w-2 h-2 bg-white rounded-full animate-pulse" />
                <span className="text-white font-semibold">LIVE</span>
              </div>
            ) : streamState?.streaming_status === 'starting' ? (
              <div className="flex items-center gap-1.5 px-ds-2 py-ds-1 bg-status-warning/80 rounded-ds-sm">
                <span className="w-2 h-2 bg-white rounded-full animate-pulse" />
                <span className="text-white font-medium">Starting...</span>
              </div>
            ) : streamState?.streaming_status === 'error' ? (
              <div className="flex items-center gap-1.5 px-ds-2 py-ds-1 bg-status-error/30 rounded-ds-sm" title={streamState.last_error || 'Stream error'}>
                <span className="text-status-error font-medium">Error</span>
              </div>
            ) : (
              <div className="flex items-center gap-1.5 px-ds-2 py-ds-1 bg-neutral-700/80 rounded-ds-sm">
                <span className="text-neutral-400 font-medium">Offline</span>
              </div>
            )}

            {/* Camera switcher */}
            {hasMultipleCameras ? (
              <>
                <span className="text-neutral-500">|</span>
                <div className="flex gap-ds-1">
                  {vehicleCameras.map((cam: { camera_name: string; youtube_url: string; embed_url?: string; featured?: boolean }, index: number) => {
                    const isActive = index === selectedCameraIndex
                    const isStreaming = cam.camera_name === activeStreamingCamera
                    return (
                      <button
                        key={cam.camera_name}
                        onClick={() => setManualCameraOverride(cam.camera_name)}
                        className={`px-ds-2 py-ds-1 rounded-ds-sm text-ds-caption font-medium transition-colors duration-ds-fast relative focus:outline-none focus:ring-2 focus:ring-accent-500 ${
                          isActive
                            ? 'bg-accent-600 text-white'
                            : 'bg-neutral-700 text-neutral-300 hover:bg-neutral-600'
                        }`}
                      >
                        {formatCameraName(cam.camera_name)}
                        {cam.featured && (
                          <span className="absolute -top-1 -left-1 w-2 h-2 bg-status-warning rounded-full" title="Featured" />
                        )}
                        {isStreaming && !isActive && (
                          <span className="absolute -top-1 -right-1 w-2 h-2 bg-status-error rounded-full animate-pulse" title="Currently streaming" />
                        )}
                      </button>
                    )
                  })}
                </div>
              </>
            ) : (
              <span className="text-neutral-500">
                {currentCamera?.camera_name ? formatCameraName(currentCamera.camera_name) : 'No camera'}
              </span>
            )}
          </div>

          {/* Share button */}
          <button
            onClick={handleShare}
            className="flex items-center gap-1.5 text-neutral-400 hover:text-white transition-colors duration-ds-fast px-ds-2 py-ds-1 rounded-ds-sm hover:bg-neutral-700/50 focus:outline-none focus:ring-2 focus:ring-accent-500"
            aria-label="Share vehicle"
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

        {/* Latency notice - only show when live */}
        {streamState?.is_live && videoId && (
          <div className="bg-status-warning/20 text-status-warning text-ds-caption text-center py-ds-1">
            Video is ~20s behind live telemetry
          </div>
        )}

        {/* Position badge - HIGH CONTRAST - FIXED: P1-1 - Show skeleton while loading */}
        {isLoadingLeaderboard ? (
          <PositionBadgeSkeleton />
        ) : leaderboardEntry ? (
          <div className="bg-neutral-900/80 backdrop-blur-sm px-ds-4 py-ds-3 flex items-center justify-between border-b border-neutral-700">
            <div className="flex items-center gap-ds-3">
              <div className="text-4xl font-black text-accent-400">
                P{leaderboardEntry.position}
              </div>
              <div className="text-ds-body-sm text-neutral-200">
                {leaderboardEntry.last_checkpoint_name || `CP ${leaderboardEntry.last_checkpoint}`}
              </div>
            </div>
            <div className="text-right">
              <div className="text-xl font-mono font-bold text-neutral-100">
                {leaderboardEntry.delta_formatted}
              </div>
              <div className="text-ds-caption text-neutral-400 uppercase tracking-wide">to leader</div>
            </div>
          </div>
        ) : null}

        {/* Primary Telemetry - Large tiles for key stats - FIXED: P1-1 - Show skeletons during initial load */}
        <div className="p-ds-4 space-y-ds-4">
          {isInitialLoading ? (
            <>
              {/* Skeleton tiles for initial loading state */}
              <div className="grid grid-cols-2 gap-ds-3">
                <TelemetryTileSkeleton />
                <TelemetryTileSkeleton />
              </div>
              <div className="grid grid-cols-2 gap-ds-3">
                <TelemetryTileSkeleton small />
                <TelemetryTileSkeleton small />
              </div>
            </>
          ) : (
            <>
              <div className="grid grid-cols-2 gap-ds-3">
                <TelemetryTile
                  label="Speed"
                  value={speedMph ?? '--'}
                  unit="mph"
                  thresholdKey="speed_mph"
                  lastUpdateMs={lastUpdateMs}
                />
                <TelemetryTile
                  label="Heading"
                  value={position?.heading_deg !== null ? Math.round(position?.heading_deg || 0) : '--'}
                  unit="deg"
                  lastUpdateMs={lastUpdateMs}
                />
              </div>

              {/* GPS Coordinates - Smaller tiles */}
              <div className="grid grid-cols-2 gap-ds-3">
                <TelemetryTile
                  label="Latitude"
                  value={position?.lat ? position.lat.toFixed(5) : '--'}
                  unit=""
                  small
                  lastUpdateMs={lastUpdateMs}
                />
                <TelemetryTile
                  label="Longitude"
                  value={position?.lon ? position.lon.toFixed(5) : '--'}
                  unit=""
                  small
                  lastUpdateMs={lastUpdateMs}
                />
              </div>
            </>
          )}

          {/* PROMPT 5: Engine Telemetry - Shows only fields allowed by team's sharing policy */}
          {hasEngineTelemetry && (
            <>
              <h3 className="text-ds-caption uppercase tracking-wider text-neutral-400 font-semibold mt-ds-6 mb-ds-2">
                Engine
              </h3>
              <div className="grid grid-cols-2 gap-ds-3">
                {telemetryData.rpm !== undefined && (
                  <TelemetryTile
                    label="RPM"
                    value={telemetryData.rpm ?? '--'}
                    unit=""
                    thresholdKey="rpm"
                    lastUpdateMs={lastUpdateMs}
                  />
                )}
                {telemetryData.gear !== undefined && (
                  <TelemetryTile
                    label="Gear"
                    value={telemetryData.gear ?? '--'}
                    unit=""
                    lastUpdateMs={lastUpdateMs}
                  />
                )}
                {telemetryData.throttle_pct !== undefined && (
                  <TelemetryTile
                    label="Throttle"
                    value={telemetryData.throttle_pct ?? '--'}
                    unit="%"
                    small
                    lastUpdateMs={lastUpdateMs}
                  />
                )}
              </div>
            </>
          )}

          {/* PROMPT 5: Advanced Telemetry - Coolant, Oil, Fuel */}
          {hasAdvancedTelemetry && (
            <>
              <h3 className="text-ds-caption uppercase tracking-wider text-neutral-400 font-semibold mt-ds-6 mb-ds-2">
                Engine Vitals
              </h3>
              <div className="grid grid-cols-2 gap-ds-3">
                {telemetryData.coolant_temp_c !== undefined && (
                  <TelemetryTile
                    label="Coolant"
                    value={telemetryData.coolant_temp_c ?? '--'}
                    unit="°C"
                    thresholdKey="coolant_temp_c"
                    small
                    lastUpdateMs={lastUpdateMs}
                  />
                )}
                {telemetryData.oil_pressure_psi !== undefined && (
                  <TelemetryTile
                    label="Oil Press"
                    value={telemetryData.oil_pressure_psi ?? '--'}
                    unit="psi"
                    thresholdKey="oil_pressure_psi"
                    small
                    lastUpdateMs={lastUpdateMs}
                  />
                )}
                {telemetryData.fuel_pressure_psi !== undefined && (
                  <TelemetryTile
                    label="Fuel Press"
                    value={telemetryData.fuel_pressure_psi ?? '--'}
                    unit="psi"
                    thresholdKey="fuel_pressure_psi"
                    small
                    lastUpdateMs={lastUpdateMs}
                  />
                )}
              </div>
            </>
          )}

          {/* PROMPT 5: Driver Biometrics - Heart Rate */}
          {hasHeartRate && (
            <>
              <h3 className="text-ds-caption uppercase tracking-wider text-neutral-400 font-semibold mt-ds-6 mb-ds-2">
                Driver Biometrics
              </h3>
              <TelemetryTile
                label="Heart Rate"
                value={telemetryData.heart_rate ?? '--'}
                unit="bpm"
                thresholdKey="heart_rate"
                lastUpdateMs={lastUpdateMs}
              />
            </>
          )}

          {/* PROMPT 5: Message when no extended telemetry is shared */}
          {!isInitialLoading && !hasFanTelemetry && position && (
            <div className="mt-ds-6 bg-neutral-800/50 border border-neutral-700 rounded-ds-lg p-ds-4 text-center">
              <div className="text-neutral-400 text-ds-body-sm">
                Extended telemetry not available
              </div>
              <div className="text-neutral-500 text-ds-caption mt-ds-1">
                Team has not enabled telemetry sharing for fans
              </div>
            </div>
          )}
        </div>

        {/* Last update and Wake Lock indicator */}
        <div className="text-center text-ds-caption text-neutral-500 pb-ds-4 mb-16">
          <div>
            Last update: {lastUpdateMs
              ? new Date(lastUpdateMs).toLocaleTimeString()
              : '--'}
          </div>
          {wakeLockActive && (
            <div className="mt-ds-1 text-status-success flex items-center justify-center gap-ds-1">
              <span className="w-2 h-2 bg-status-success rounded-full animate-pulse" />
              Pit Crew Mode (screen stays on)
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
