/**
 * Production Control Room
 *
 * 3-column broadcast control interface for production directors:
 * - Left: Program (On Air) preview with current broadcast
 * - Center: Camera grid with health indicators
 * - Right: Race context (leaderboard, alerts, timing)
 *
 * Features:
 * - Keyboard shortcuts (1-9) for quick camera switching
 * - Visual confirmation on camera switch ("LIVE: Truck 12 - Onboard")
 * - Real-time truck connectivity status
 * - Leaderboard integration for race context
 *
 * Route: /production/events/:eventId
 * Requires admin authentication.
 *
 * UI-3 Update: Refactored to use design system tokens and components
 */
import { useState, useEffect, useCallback, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useSafeBack } from '../hooks/useSafeBack'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { copyToClipboard } from '../utils/clipboard'
import { api, type LeaderboardEntry } from '../api/client'
import { StreamControlPanel, DiagnosticsModal, type StreamState, type EdgeStatusInfo } from '../components/StreamControl'
import { Button, Card, Badge, Alert, EmptyState } from '../components/ui'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

// Types matching backend schemas
interface CameraFeed {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  camera_name: string
  youtube_url: string
  is_live: boolean
}

interface BroadcastState {
  event_id: string
  featured_vehicle_id: string | null
  featured_camera: string | null
  active_feeds: CameraFeed[]
  updated_at: string
}

interface TruckStatus {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  status: 'online' | 'stale' | 'offline' | 'never_connected'
  last_heartbeat_ms: number | null
  last_heartbeat_ago_s: number | null
  data_rate_hz: number
  has_video_feed: boolean
}

interface TruckStatusList {
  event_id: string
  trucks: TruckStatus[]
  online_count: number
  total_count: number
  checked_at: string
}

// New edge status types with streaming info
interface EdgeCameraInfo {
  name: string
  device: string | null
  status: string
}

interface EdgeStatus {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  connection_status: 'online' | 'stale' | 'offline' | 'never_connected'
  last_heartbeat_ms: number | null
  last_heartbeat_ago_s: number | null
  data_rate_hz: number
  edge_online: boolean
  streaming_status: 'idle' | 'starting' | 'live' | 'error' | 'unknown'
  streaming_camera: string | null
  streaming_uptime_s: number | null
  streaming_error: string | null
  cameras: EdgeCameraInfo[]
  last_can_ts: number | null
  last_gps_ts: number | null
  youtube_configured: boolean
  youtube_url: string | null
  edge_heartbeat_ms: number | null
}

interface EdgeStatusList {
  event_id: string
  edges: EdgeStatus[]
  streaming_count: number
  online_count: number
  total_count: number
  checked_at: string
}

interface SwitchConfirmation {
  vehicleNumber: string
  cameraName: string
  timestamp: number
}

// PIT-NOTES-1: Pit notes from edge devices
interface PitNote {
  note_id: string
  event_id: string
  vehicle_id: string
  vehicle_number: string | null
  team_name: string | null
  message: string
  timestamp_ms: number
  created_at: string
}

interface PitNotesResponse {
  event_id: string
  notes: PitNote[]
  total: number
}

// PROD-2: Per-vehicle featured camera state from cloud
interface FeaturedCameraStatus {
  vehicle_id: string
  event_id: string
  desired_camera: string | null
  active_camera: string | null
  request_id: string | null
  status: 'idle' | 'pending' | 'success' | 'failed' | 'timeout'
  last_error: string | null
  updated_at: string
}

// STREAM-3: Per-vehicle stream profile state from cloud
interface StreamProfileStatus {
  vehicle_id: string
  event_id: string
  desired_profile: string | null
  active_profile: string | null
  request_id: string | null
  status: 'idle' | 'pending' | 'success' | 'failed' | 'timeout'
  last_error: string | null
  updated_at: string
}

// CAM-CONTRACT-1B: Canonical 4-camera slots
const CAMERA_LABELS: Record<string, string> = {
  main: 'Main Cam',
  cockpit: 'Cockpit',
  chase: 'Chase Cam',
  suspension: 'Suspension',
}

// STREAM-3: Stream profile labels for display
const STREAM_PROFILE_LABELS: Record<string, string> = {
  '1080p30': '1080p',
  '720p30': '720p',
  '480p30': '480p',
  '360p30': '360p',
}

const STREAM_PROFILE_OPTIONS = ['1080p30', '720p30', '480p30', '360p30'] as const

export default function ControlRoom() {
  const { eventId } = useParams<{ eventId: string }>()
  const navigate = useNavigate()
  const goBack = useSafeBack('/production')
  const queryClient = useQueryClient()

  // Debug: Log when component mounts
  useEffect(() => {
    console.log('[ControlRoom] Mounted with eventId:', eventId)
    return () => console.log('[ControlRoom] Unmounted')
  }, [eventId])

  // Auth state
  const [adminToken] = useState(() => localStorage.getItem('admin_token') || '')
  const [isAuthenticated] = useState(!!adminToken)
  const [error, setError] = useState<string | null>(null)
  const [copiedEventId, setCopiedEventId] = useState(false)

  // Debug: Log auth state
  useEffect(() => {
    console.log('[ControlRoom] Auth state:', { adminToken: !!adminToken, isAuthenticated })
  }, [adminToken, isAuthenticated])

  // Switch confirmation feedback
  const [switchConfirmation, setSwitchConfirmation] = useState<SwitchConfirmation | null>(null)
  const confirmationTimeoutRef = useRef<ReturnType<typeof setTimeout>>()

  // Show switch confirmation feedback
  const showSwitchConfirmation = useCallback((vehicleNumber: string, cameraName: string) => {
    if (confirmationTimeoutRef.current) {
      clearTimeout(confirmationTimeoutRef.current)
    }
    setSwitchConfirmation({
      vehicleNumber,
      cameraName,
      timestamp: Date.now(),
    })
    confirmationTimeoutRef.current = setTimeout(() => {
      setSwitchConfirmation(null)
    }, 3000)
  }, [])

  // Fetch event details
  const { data: event } = useQuery({
    queryKey: ['event', eventId],
    queryFn: async () => {
      try {
        return await api.getEvent(eventId!)
      } catch (err) {
        console.warn('[ControlRoom] Failed to fetch event:', err)
        return null
      }
    },
    enabled: !!eventId && isAuthenticated,
    retry: false,
  })

  // Fetch broadcast state
  // Note: This endpoint may not exist yet - gracefully handle 404
  const { data: broadcastState, isLoading } = useQuery({
    queryKey: ['broadcast', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/broadcast`)
      if (!res.ok) {
        if (res.status === 404) {
          // Endpoint doesn't exist yet - return empty state
          return {
            event_id: eventId!,
            featured_vehicle_id: null,
            featured_camera: null,
            active_feeds: [],
            updated_at: new Date().toISOString(),
          } as BroadcastState
        }
        throw new Error('Failed to fetch broadcast state')
      }
      return res.json() as Promise<BroadcastState>
    },
    enabled: !!eventId && isAuthenticated,
    refetchInterval: 3000,
    retry: false,
  })

  // Fetch all available cameras
  // Note: This endpoint may not exist yet - gracefully handle 404
  const { data: cameras } = useQuery({
    queryKey: ['cameras', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/cameras`)
      if (!res.ok) {
        if (res.status === 404) {
          // Endpoint doesn't exist yet - return empty array
          return [] as CameraFeed[]
        }
        throw new Error('Failed to fetch cameras')
      }
      return res.json() as Promise<CameraFeed[]>
    },
    enabled: !!eventId && isAuthenticated,
    refetchInterval: 10000,
    retry: false,
  })

  // Fetch truck connectivity status
  // Note: This endpoint may not exist yet - gracefully handle 404
  const { data: truckStatus } = useQuery({
    queryKey: ['truck-status', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/truck-status`, {
        headers: { Authorization: `Bearer ${adminToken}` },
      })
      if (!res.ok) {
        // Don't log out on 404 - endpoint may not exist yet
        if (res.status === 404) {
          return null
        }
        // Only logout on explicit auth failure from a verified endpoint
        if (res.status === 401 || res.status === 403) {
          console.warn('Truck status endpoint returned auth error:', res.status)
          // Don't auto-logout - the endpoint may just not exist
        }
        throw new Error('Failed to fetch truck status')
      }
      return res.json() as Promise<TruckStatusList>
    },
    enabled: !!eventId && isAuthenticated,
    refetchInterval: 5000,
    retry: false, // Don't retry on failure
  })

  // Fetch edge status with streaming info
  const { data: edgeStatus } = useQuery({
    queryKey: ['edge-status', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/edge-status`, {
        headers: { Authorization: `Bearer ${adminToken}` },
      })
      if (!res.ok) {
        if (res.status === 404) {
          return null
        }
        throw new Error('Failed to fetch edge status')
      }
      return res.json() as Promise<EdgeStatusList>
    },
    enabled: !!eventId && isAuthenticated,
    refetchInterval: 5000,
    retry: false,
  })

  // Selected vehicle for drill-down modal
  const [selectedVehicle, setSelectedVehicle] = useState<EdgeStatus | null>(null)

  // Fetch leaderboard for race context
  const { data: leaderboard } = useQuery({
    queryKey: ['leaderboard', eventId],
    queryFn: async () => {
      try {
        const data = await api.getLeaderboard(eventId!)
        return Array.isArray(data.entries) ? data.entries : []
      } catch (err) {
        console.warn('[ControlRoom] Failed to fetch leaderboard:', err)
        return []
      }
    },
    enabled: !!eventId && isAuthenticated,
    refetchInterval: 5000,
    retry: false,
  })

  // PIT-NOTES-1: Fetch pit notes for race control
  const { data: pitNotes } = useQuery({
    queryKey: ['pit-notes', eventId],
    queryFn: async () => {
      try {
        const res = await fetch(`${API_BASE}/events/${eventId}/pit-notes?limit=20`)
        if (!res.ok) {
          console.warn('[ControlRoom] Failed to fetch pit notes:', res.status)
          return null
        }
        return res.json() as Promise<PitNotesResponse>
      } catch (err) {
        console.warn('[ControlRoom] Failed to fetch pit notes:', err)
        return null
      }
    },
    enabled: !!eventId,
    refetchInterval: 10000,  // Poll every 10s
    retry: false,
  })

  // NOTE: Legacy switch-camera mutation removed from UI (PROD-2).
  // Backend endpoint POST /production/events/{eid}/switch-camera still exists.
  // Camera switching now uses per-vehicle featured-camera API (setFeaturedCamera below).

  // Set featured vehicle mutation
  const setFeatured = useMutation({
    mutationFn: async ({ vehicleId }: { vehicleId: string }) => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/featured-vehicle`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${adminToken}`,
        },
        body: JSON.stringify({ vehicle_id: vehicleId }),
      })
      if (!res.ok) throw new Error('Failed to set featured vehicle')
      return res.json()
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['broadcast', eventId] })
    },
  })

  // Clear featured vehicle
  const clearFeatured = useMutation({
    mutationFn: async () => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/featured-vehicle`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${adminToken}` },
      })
      if (!res.ok) throw new Error('Failed to clear featured')
      return res.json()
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['broadcast', eventId] })
    },
  })

  // PROD-2: Per-vehicle featured camera state tracking
  const [featuredCameraStates, setFeaturedCameraStates] = useState<Record<string, FeaturedCameraStatus>>({})

  // PROD-2: Set featured camera for a specific vehicle
  const setFeaturedCamera = useMutation({
    mutationFn: async ({ vehicleId, cameraId }: { vehicleId: string; cameraId: string }) => {
      const res = await fetch(
        `${API_BASE}/production/events/${eventId}/vehicles/${vehicleId}/featured-camera`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${adminToken}`,
          },
          body: JSON.stringify({ camera_id: cameraId }),
        }
      )
      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || 'Failed to set featured camera')
      }
      return res.json()
    },
    onMutate: ({ vehicleId, cameraId }) => {
      // Optimistic: show pending state immediately
      setFeaturedCameraStates(prev => ({
        ...prev,
        [vehicleId]: {
          ...prev[vehicleId],
          vehicle_id: vehicleId,
          event_id: eventId || '',
          desired_camera: cameraId,
          status: 'pending',
          last_error: null,
          updated_at: new Date().toISOString(),
        } as FeaturedCameraStatus,
      }))
    },
    onSuccess: (data, variables) => {
      // Also set featured vehicle + update broadcast
      setFeatured.mutate({ vehicleId: variables.vehicleId })
      queryClient.invalidateQueries({ queryKey: ['broadcast', eventId] })
      // Update local state with response
      setFeaturedCameraStates(prev => ({
        ...prev,
        [variables.vehicleId]: {
          ...prev[variables.vehicleId],
          request_id: data.request_id,
          status: data.status || 'pending',
        } as FeaturedCameraStatus,
      }))
      // Show switch confirmation toast
      const vehicle = cameras?.find(c => c.vehicle_id === variables.vehicleId)
      if (vehicle) {
        showSwitchConfirmation(vehicle.vehicle_number, variables.cameraId)
      }
    },
    onError: (err: Error, variables) => {
      setFeaturedCameraStates(prev => ({
        ...prev,
        [variables.vehicleId]: {
          ...prev[variables.vehicleId],
          status: 'failed',
          last_error: err.message,
        } as FeaturedCameraStatus,
      }))
      setError(err.message)
    },
  })

  // STREAM-3: Per-vehicle stream profile state tracking
  const [streamProfileStates, setStreamProfileStates] = useState<Record<string, StreamProfileStatus>>({})

  // STREAM-3: Set stream profile for a specific vehicle
  const setStreamProfile = useMutation({
    mutationFn: async ({ vehicleId, profile }: { vehicleId: string; profile: string }) => {
      const res = await fetch(
        `${API_BASE}/production/events/${eventId}/vehicles/${vehicleId}/stream-profile`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${adminToken}`,
          },
          body: JSON.stringify({ profile }),
        }
      )
      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || 'Failed to set stream profile')
      }
      return res.json()
    },
    onMutate: ({ vehicleId, profile }) => {
      setStreamProfileStates(prev => ({
        ...prev,
        [vehicleId]: {
          ...prev[vehicleId],
          vehicle_id: vehicleId,
          event_id: eventId || '',
          desired_profile: profile,
          status: 'pending',
          last_error: null,
          updated_at: new Date().toISOString(),
        } as StreamProfileStatus,
      }))
    },
    onSuccess: (data, variables) => {
      setStreamProfileStates(prev => ({
        ...prev,
        [variables.vehicleId]: {
          ...prev[variables.vehicleId],
          request_id: data.request_id,
          status: data.status || 'pending',
        } as StreamProfileStatus,
      }))
    },
    onError: (err: Error, variables) => {
      setStreamProfileStates(prev => ({
        ...prev,
        [variables.vehicleId]: {
          ...prev[variables.vehicleId],
          status: 'failed',
          last_error: err.message,
        } as StreamProfileStatus,
      }))
    },
  })

  // PROD-2: Poll featured camera state for vehicles with pending requests
  useEffect(() => {
    const pendingVehicles = Object.entries(featuredCameraStates)
      .filter(([, state]) => state.status === 'pending')
      .map(([vehicleId]) => vehicleId)

    if (pendingVehicles.length === 0) return

    const interval = setInterval(async () => {
      for (const vehicleId of pendingVehicles) {
        try {
          const res = await fetch(
            `${API_BASE}/production/events/${eventId}/vehicles/${vehicleId}/featured-camera`
          )
          if (!res.ok) continue
          const state: FeaturedCameraStatus = await res.json()
          setFeaturedCameraStates(prev => ({
            ...prev,
            [vehicleId]: state,
          }))
        } catch {
          // Silently ignore polling errors
        }
      }
    }, 2000) // Poll every 2 seconds while pending

    return () => clearInterval(interval)
  }, [featuredCameraStates, eventId])

  // PROD-2: Auto-clear success/failed/timeout states after 5 seconds
  useEffect(() => {
    const transientStates = Object.entries(featuredCameraStates)
      .filter(([, state]) => state.status === 'success' || state.status === 'failed' || state.status === 'timeout')
    if (transientStates.length === 0) return

    const timer = setTimeout(() => {
      setFeaturedCameraStates(prev => {
        const next = { ...prev }
        for (const [vehicleId, state] of transientStates) {
          if (state.status === 'success') {
            next[vehicleId] = { ...state, status: 'idle' }
          }
          // Keep failed/timeout visible longer but mark as idle eventually
          if (state.status === 'failed' || state.status === 'timeout') {
            next[vehicleId] = { ...state, status: 'idle' }
          }
        }
        return next
      })
    }, 5000)

    return () => clearTimeout(timer)
  }, [featuredCameraStates])

  // STREAM-3: Poll stream profile state for vehicles with pending requests
  useEffect(() => {
    const pendingVehicles = Object.entries(streamProfileStates)
      .filter(([, state]) => state.status === 'pending')
      .map(([vehicleId]) => vehicleId)

    if (pendingVehicles.length === 0) return

    const interval = setInterval(async () => {
      for (const vehicleId of pendingVehicles) {
        try {
          const res = await fetch(
            `${API_BASE}/production/events/${eventId}/vehicles/${vehicleId}/stream-profile`
          )
          if (!res.ok) continue
          const state: StreamProfileStatus = await res.json()
          setStreamProfileStates(prev => ({
            ...prev,
            [vehicleId]: state,
          }))
        } catch {
          // Silently ignore polling errors
        }
      }
    }, 2000)

    return () => clearInterval(interval)
  }, [streamProfileStates, eventId])

  // STREAM-3: Auto-clear success/failed/timeout states after 5 seconds
  useEffect(() => {
    const transientStates = Object.entries(streamProfileStates)
      .filter(([, state]) => state.status === 'success' || state.status === 'failed' || state.status === 'timeout')
    if (transientStates.length === 0) return

    const timer = setTimeout(() => {
      setStreamProfileStates(prev => {
        const next = { ...prev }
        for (const [vehicleId, state] of transientStates) {
          next[vehicleId] = { ...state, status: 'idle' }
        }
        return next
      })
    }, 5000)

    return () => clearTimeout(timer)
  }, [streamProfileStates])

  // Group cameras by vehicle
  const camerasByVehicle = cameras?.reduce((acc, cam) => {
    if (!acc[cam.vehicle_id]) {
      acc[cam.vehicle_id] = {
        vehicle_id: cam.vehicle_id,
        vehicle_number: cam.vehicle_number,
        team_name: cam.team_name,
        cameras: [],
      }
    }
    acc[cam.vehicle_id].cameras.push(cam)
    return acc
  }, {} as Record<string, { vehicle_id: string; vehicle_number: string; team_name: string; cameras: CameraFeed[] }>)

  // Get numbered list for keyboard shortcuts
  const vehicleList = Object.values(camerasByVehicle || {}).slice(0, 9)

  // Keyboard shortcuts (1-9)
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      // Ignore if typing in input
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return

      const num = parseInt(e.key)
      if (num >= 1 && num <= 9) {
        const vehicle = vehicleList[num - 1]
        if (vehicle && vehicle.cameras.length > 0) {
          // PROD-2: Use featured-camera API per vehicle
          setFeaturedCamera.mutate({
            vehicleId: vehicle.vehicle_id,
            cameraId: vehicle.cameras[0].camera_name,
          })
        }
      }

      // Escape to clear featured
      if (e.key === 'Escape') {
        clearFeatured.mutate()
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [vehicleList, setFeaturedCamera, clearFeatured])

  // Clean up timeout on unmount
  useEffect(() => {
    return () => {
      if (confirmationTimeoutRef.current) {
        clearTimeout(confirmationTimeoutRef.current)
      }
    }
  }, [])

  // Redirect if not authenticated
  if (!isAuthenticated) {
    return (
      <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-ds-4">
        <EmptyState
          icon={
            <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 15v2m0 0v2m0-2h2m-2 0H10m9-9V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4" />
            </svg>
          }
          title="Session Expired"
          description="Your authentication has expired. Please log in again."
          action={{
            label: 'Return to Login',
            onClick: () => navigate('/production'),
            variant: 'primary',
          }}
        />
      </div>
    )
  }

  // Show loading skeleton
  if (isLoading && !broadcastState) {
    return (
      <div className="min-h-screen bg-neutral-950 flex flex-col">
        {/* Header Skeleton */}
        <header className="bg-neutral-900 border-b border-neutral-800 px-ds-4 py-ds-3 flex items-center justify-between">
          <div className="flex items-center gap-ds-4">
            <div className="skeleton bg-neutral-800 rounded-ds-md w-10 h-10" />
            <div>
              <div className="skeleton bg-neutral-800 rounded-ds-sm h-5 w-32 mb-ds-2" />
              <div className="skeleton bg-neutral-800 rounded-ds-sm h-4 w-48" />
            </div>
          </div>
          <div className="flex items-center gap-ds-4">
            <div className="skeleton bg-neutral-800 rounded-ds-md h-8 w-24" />
            <div className="skeleton bg-neutral-800 rounded-ds-md h-8 w-20" />
          </div>
        </header>

        {/* Content Skeleton */}
        <div className="flex-1 p-ds-4 grid grid-cols-1 lg:grid-cols-12 gap-ds-4">
          {/* Left Panel Skeleton */}
          <div className="lg:col-span-4">
            <div className="bg-neutral-900 rounded-ds-lg border border-neutral-800 h-96">
              <div className="px-ds-4 py-ds-3 border-b border-neutral-800">
                <div className="skeleton bg-neutral-800 rounded-ds-sm h-5 w-20" />
              </div>
              <div className="p-ds-4">
                <div className="skeleton bg-neutral-800 rounded-ds-md h-48 w-full mb-ds-4" />
                <div className="skeleton bg-neutral-800 rounded-ds-sm h-6 w-24 mb-ds-2" />
                <div className="skeleton bg-neutral-800 rounded-ds-sm h-4 w-32" />
              </div>
            </div>
          </div>

          {/* Center Panel Skeleton */}
          <div className="lg:col-span-5">
            <div className="bg-neutral-900 rounded-ds-lg border border-neutral-800 h-96">
              <div className="px-ds-4 py-ds-3 border-b border-neutral-800">
                <div className="skeleton bg-neutral-800 rounded-ds-sm h-5 w-28" />
              </div>
              <div className="p-ds-4 grid grid-cols-2 gap-ds-3">
                {[1, 2, 3, 4].map((i) => (
                  <div key={i} className="skeleton bg-neutral-800 rounded-ds-md h-24" />
                ))}
              </div>
            </div>
          </div>

          {/* Right Panel Skeleton */}
          <div className="lg:col-span-3 space-y-ds-4">
            <div className="bg-neutral-900 rounded-ds-lg border border-neutral-800 h-48">
              <div className="px-ds-4 py-ds-3 border-b border-neutral-800">
                <div className="skeleton bg-neutral-800 rounded-ds-sm h-5 w-24" />
              </div>
              <div className="p-ds-4 space-y-ds-2">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="skeleton bg-neutral-800 rounded-ds-sm h-10" />
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Loading indicator */}
        <div className="fixed inset-0 flex items-center justify-center pointer-events-none">
          <div className="bg-neutral-900/90 rounded-ds-lg p-ds-4 flex flex-col items-center gap-ds-3">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-accent-500" />
            <p className="text-neutral-400 text-ds-body-sm">Loading Control Room...</p>
            <p className="text-ds-caption text-neutral-600 font-mono">Event: {eventId}</p>
          </div>
        </div>
      </div>
    )
  }

  const featuredVehicle = cameras?.find(c => c.vehicle_id === broadcastState?.featured_vehicle_id)
  const featuredFeed = broadcastState?.active_feeds.find(
    f => f.vehicle_id === broadcastState.featured_vehicle_id && f.camera_name === broadcastState.featured_camera
  )

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-50 flex flex-col">
      {/* Switch Confirmation Toast */}
      {switchConfirmation && (
        <div className="fixed top-ds-4 left-1/2 -translate-x-1/2 z-50 animate-fade-in">
          <div className="bg-status-error px-ds-6 py-ds-3 rounded-ds-lg shadow-ds-overlay flex items-center gap-ds-3">
            <span className="w-3 h-3 rounded-full bg-white animate-pulse" />
            <span className="font-bold text-ds-body">
              LIVE: Truck #{switchConfirmation.vehicleNumber} - {CAMERA_LABELS[switchConfirmation.cameraName] || switchConfirmation.cameraName}
            </span>
          </div>
        </div>
      )}

      {/* Header */}
      <header className="bg-neutral-900 border-b border-neutral-800 px-ds-4 py-ds-3 flex items-center justify-between flex-shrink-0">
        <div className="flex items-center gap-ds-4">
          <button
            onClick={goBack}
            className="min-w-[44px] min-h-[44px] -ml-ds-2 flex items-center justify-center rounded-full text-neutral-400 hover:text-neutral-50 hover:bg-neutral-800 transition-colors duration-ds-fast focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-400"
            aria-label="Back to events"
          >
            <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <div>
            <h1 className="text-ds-heading text-neutral-50 flex items-center gap-ds-2">
              <span className="w-2 h-2 rounded-full bg-status-error animate-pulse" />
              Control Room
            </h1>
            <div className="flex items-center gap-ds-2">
              <p className="text-ds-body-sm text-neutral-400">{event?.name || 'Loading...'}</p>
              <span className="text-neutral-600">·</span>
              <button
                onClick={async () => {
                  if (eventId) {
                    await copyToClipboard(eventId)
                    setCopiedEventId(true)
                    setTimeout(() => setCopiedEventId(false), 2000)
                  }
                }}
                className="flex items-center gap-ds-1 text-ds-caption font-mono text-neutral-500 hover:text-neutral-300 transition-colors duration-ds-fast"
                title="Click to copy Event ID"
              >
                <span className="bg-neutral-800 px-ds-1 py-0.5 rounded-ds-sm">{eventId}</span>
                {copiedEventId ? (
                  <svg className="w-3.5 h-3.5 text-status-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                  </svg>
                ) : (
                  <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                  </svg>
                )}
              </button>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-ds-4">
          {/* Edge Status Summary */}
          {edgeStatus && (
            <div className="flex items-center gap-ds-2">
              <Badge
                variant={
                  edgeStatus.online_count === edgeStatus.total_count ? 'success' :
                  edgeStatus.online_count > 0 ? 'warning' : 'error'
                }
                dot
              >
                {edgeStatus.online_count}/{edgeStatus.total_count} online
              </Badge>
              {edgeStatus.streaming_count > 0 && (
                <Badge variant="error" dot pulse>
                  {edgeStatus.streaming_count} streaming
                </Badge>
              )}
            </div>
          )}
          {/* Fallback to old truckStatus if edgeStatus not available */}
          {!edgeStatus && truckStatus && (
            <Badge
              variant={
                truckStatus.online_count === truckStatus.total_count ? 'success' :
                truckStatus.online_count > 0 ? 'warning' : 'error'
              }
              dot
            >
              {truckStatus.online_count}/{truckStatus.total_count} trucks online
            </Badge>
          )}

          <span className="text-ds-caption text-neutral-500">
            Press <kbd className="px-ds-1 py-0.5 bg-neutral-800 rounded-ds-sm text-neutral-300">1-9</kbd> to switch
          </span>

          <Button
            variant="secondary"
            size="sm"
            onClick={() => {
              localStorage.removeItem('admin_token')
              navigate('/production')
            }}
          >
            Logout
          </Button>

          <button
            onClick={() => navigate('/')}
            className="min-w-[44px] min-h-[44px] flex items-center justify-center rounded-full text-neutral-400 hover:text-neutral-50 hover:bg-neutral-800 transition-colors duration-ds-fast focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-400"
            aria-label="Home"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-4 0a1 1 0 01-1-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 01-1 1h-2z" />
            </svg>
          </button>
        </div>
      </header>

      {/* Error Banner */}
      {error && (
        <div className="mx-ds-4 mt-ds-4">
          <Alert
            variant="error"
            title="Error"
            onDismiss={() => setError(null)}
          >
            {error}
          </Alert>
        </div>
      )}

      {/* 3-Column Layout */}
      <div className="flex-1 p-ds-4 grid grid-cols-1 lg:grid-cols-12 gap-ds-4 overflow-hidden">
        {/* Left Column: Program (On Air) Preview */}
        <div className="lg:col-span-4 flex flex-col">
          <Card variant="default" padding="none" className="flex-1 flex flex-col overflow-hidden">
            <div className="px-ds-4 py-ds-3 border-b border-neutral-800 flex items-center justify-between">
              <h2 className="text-ds-heading text-neutral-50 flex items-center gap-ds-2">
                <span className="w-3 h-3 rounded-full bg-status-error animate-pulse" />
                ON AIR
              </h2>
              {broadcastState?.featured_vehicle_id && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => clearFeatured.mutate()}
                >
                  Auto Mode
                </Button>
              )}
            </div>

            <div className="flex-1 p-ds-4">
              {broadcastState?.featured_vehicle_id ? (
                <div className="h-full flex flex-col">
                  <div className="flex-1 bg-neutral-950 rounded-ds-md overflow-hidden relative min-h-[200px]">
                    {featuredFeed?.youtube_url ? (
                      <iframe
                        src={`https://www.youtube.com/embed/${extractYouTubeId(featuredFeed.youtube_url)}?autoplay=1&mute=1`}
                        className="w-full h-full"
                        allow="autoplay; encrypted-media"
                        allowFullScreen
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-neutral-500">
                        {broadcastState.featured_camera ? 'No Video Feed' : 'Streaming (camera unknown)'}
                      </div>
                    )}
                    {/* PROD-2: Show pending/live badge based on featured camera state */}
                    {(() => {
                      const fcState = featuredCameraStates[broadcastState.featured_vehicle_id || '']
                      if (fcState?.status === 'pending') {
                        return (
                          <Badge variant="warning" className="absolute top-ds-2 left-ds-2 animate-pulse">
                            SWITCHING…
                          </Badge>
                        )
                      }
                      return (
                        <Badge variant="error" className="absolute top-ds-2 left-ds-2">
                          LIVE
                        </Badge>
                      )
                    })()}
                    <div className="absolute bottom-ds-2 left-ds-2 px-ds-2 py-ds-1 bg-neutral-950/70 rounded-ds-sm text-ds-body-sm font-mono">
                      {CAMERA_LABELS[broadcastState.featured_camera || ''] || broadcastState.featured_camera || 'unknown'}
                    </div>
                  </div>

                  <div className="mt-ds-3 flex items-center justify-between">
                    <div>
                      <div className="text-ds-title text-neutral-50">#{featuredVehicle?.vehicle_number}</div>
                      <div className="text-ds-body-sm text-neutral-400">{featuredVehicle?.team_name}</div>
                    </div>
                    <TruckStatusBadge
                      status={truckStatus?.trucks.find(t => t.vehicle_id === broadcastState.featured_vehicle_id)?.status}
                    />
                  </div>
                </div>
              ) : (
                <div className="h-full flex items-center justify-center min-h-[200px]">
                  <EmptyState
                    title="Auto Mode"
                    description="No featured camera selected. Select a camera or press 1-9."
                  />
                </div>
              )}
            </div>
          </Card>
        </div>

        {/* Center Column: Camera Grid */}
        <div className="lg:col-span-5 flex flex-col overflow-hidden">
          <Card variant="default" padding="none" className="flex-1 flex flex-col overflow-hidden">
            <div className="px-ds-4 py-ds-3 border-b border-neutral-800 flex items-center justify-between flex-shrink-0">
              <h2 className="text-ds-heading text-neutral-50">Camera Grid</h2>
              <span className="text-ds-caption text-neutral-500">{cameras?.length || 0} feeds available</span>
            </div>

            <div className="flex-1 overflow-y-auto p-ds-4">
              {vehicleList.length === 0 ? (
                <EmptyState
                  icon={
                    <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                        d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
                    </svg>
                  }
                  title="No feeds yet"
                  description="Teams need to configure video feeds to appear here. Check the Edge Devices panel for connectivity status."
                />
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-ds-3">
                  {vehicleList.map((vehicle, index) => {
                    const truckInfo = truckStatus?.trucks.find(t => t.vehicle_id === vehicle.vehicle_id)
                    const isSelected = broadcastState?.featured_vehicle_id === vehicle.vehicle_id

                    return (
                      <div
                        key={vehicle.vehicle_id}
                        className={`bg-neutral-800 rounded-ds-md border transition-all duration-ds-fast ${
                          isSelected
                            ? 'border-status-error ring-2 ring-status-error/30'
                            : 'border-neutral-700 hover:border-neutral-600'
                        }`}
                      >
                        {/* Vehicle Header */}
                        <div className="p-ds-3 border-b border-neutral-700 flex items-center justify-between">
                          <div className="flex items-center gap-ds-2">
                            <kbd className="w-6 h-6 flex items-center justify-center bg-neutral-700 rounded-ds-sm text-ds-caption font-bold">
                              {index + 1}
                            </kbd>
                            <span className="text-ds-body-sm font-bold">#{vehicle.vehicle_number}</span>
                            <TruckStatusBadge status={truckInfo?.status} small />
                          </div>
                          <Button
                            variant={isSelected ? 'danger' : 'secondary'}
                            size="sm"
                            onClick={() => setFeatured.mutate({ vehicleId: vehicle.vehicle_id })}
                          >
                            {isSelected ? 'LIVE' : 'Feature'}
                          </Button>
                        </div>

                        {/* Camera Buttons — PROD-2: per-vehicle featured camera switching */}
                        <div className="p-ds-2 grid grid-cols-2 gap-ds-1">
                          {vehicle.cameras.map((cam) => {
                            const vehicleFcState = featuredCameraStates[vehicle.vehicle_id]
                            const isActive = isSelected && broadcastState?.featured_camera === cam.camera_name
                            const isPendingThis = vehicleFcState?.status === 'pending' && vehicleFcState?.desired_camera === cam.camera_name
                            const isFailedThis = (vehicleFcState?.status === 'failed' || vehicleFcState?.status === 'timeout') && vehicleFcState?.desired_camera === cam.camera_name
                            const isPendingAny = vehicleFcState?.status === 'pending'

                            return (
                              <button
                                key={cam.camera_name}
                                onClick={() => setFeaturedCamera.mutate({
                                  vehicleId: cam.vehicle_id,
                                  cameraId: cam.camera_name,
                                })}
                                disabled={isPendingAny || setFeaturedCamera.isPending}
                                className={`px-ds-2 py-ds-2 rounded-ds-sm text-left text-ds-body-sm transition-all duration-ds-fast ${
                                  isPendingThis
                                    ? 'bg-accent-600/40 text-white ring-1 ring-accent-400/50 animate-pulse'
                                    : isFailedThis
                                    ? 'bg-status-error/20 text-status-error ring-1 ring-status-error/40'
                                    : isActive
                                    ? 'bg-status-error text-white ring-2 ring-status-error/50'
                                    : 'bg-neutral-700/50 hover:bg-neutral-700 text-neutral-300'
                                }`}
                              >
                                <div className="font-medium truncate flex items-center gap-ds-1">
                                  {CAMERA_LABELS[cam.camera_name] || cam.camera_name}
                                  {isActive && (
                                    <span className="text-ds-caption bg-white/20 px-1 rounded">Featured</span>
                                  )}
                                </div>
                                <div className="flex items-center gap-ds-1 mt-0.5">
                                  {isPendingThis ? (
                                    <>
                                      <span className="w-1.5 h-1.5 rounded-full bg-accent-400 animate-pulse" />
                                      <span className="text-ds-caption opacity-70">Switching…</span>
                                    </>
                                  ) : isFailedThis ? (
                                    <>
                                      <span className="w-1.5 h-1.5 rounded-full bg-status-error" />
                                      <span className="text-ds-caption opacity-70">
                                        {vehicleFcState?.status === 'timeout' ? 'Timed out' : 'Failed'}
                                      </span>
                                    </>
                                  ) : (
                                    <>
                                      <span className={`w-1.5 h-1.5 rounded-full ${
                                        cam.is_live ? 'bg-status-success' : 'bg-neutral-500'
                                      }`} />
                                      <span className="text-ds-caption opacity-70">
                                        {cam.is_live ? 'Live' : 'Offline'}
                                      </span>
                                    </>
                                  )}
                                </div>
                              </button>
                            )
                          })}
                        </div>
                        {/* STREAM-3: Per-vehicle stream quality dropdown */}
                        <div className="px-ds-2 py-ds-1 border-t border-neutral-700/50 flex items-center gap-ds-2">
                          <span className="text-ds-caption text-neutral-500">Quality:</span>
                          <select
                            className="bg-neutral-700 text-neutral-200 text-ds-caption rounded-ds-sm px-ds-1 py-0.5 border border-neutral-600 focus:outline-none focus:ring-1 focus:ring-accent-400 cursor-pointer"
                            value={streamProfileStates[vehicle.vehicle_id]?.active_profile || streamProfileStates[vehicle.vehicle_id]?.desired_profile || '1080p30'}
                            onChange={(e) => setStreamProfile.mutate({ vehicleId: vehicle.vehicle_id, profile: e.target.value })}
                            disabled={streamProfileStates[vehicle.vehicle_id]?.status === 'pending' || !truckInfo || truckInfo.status === 'offline' || truckInfo.status === 'never_connected'}
                          >
                            {STREAM_PROFILE_OPTIONS.map((p) => (
                              <option key={p} value={p}>{STREAM_PROFILE_LABELS[p]}</option>
                            ))}
                          </select>
                          {streamProfileStates[vehicle.vehicle_id]?.status === 'pending' && (
                            <span className="w-1.5 h-1.5 rounded-full bg-accent-400 animate-pulse" title="Applying..." />
                          )}
                          {streamProfileStates[vehicle.vehicle_id]?.status === 'success' && (
                            <span className="text-ds-caption text-status-success">Applied</span>
                          )}
                          {(streamProfileStates[vehicle.vehicle_id]?.status === 'failed' || streamProfileStates[vehicle.vehicle_id]?.status === 'timeout') && (
                            <span className="text-ds-caption text-status-error" title={streamProfileStates[vehicle.vehicle_id]?.last_error || ''}>
                              {streamProfileStates[vehicle.vehicle_id]?.status === 'timeout' ? 'Timed out' : 'Failed'}
                            </span>
                          )}
                        </div>
                        {/* PROD-2: Per-vehicle error message */}
                        {featuredCameraStates[vehicle.vehicle_id]?.last_error && (featuredCameraStates[vehicle.vehicle_id]?.status === 'failed' || featuredCameraStates[vehicle.vehicle_id]?.status === 'timeout') && (
                          <div className="px-ds-2 pb-ds-2">
                            <div className="flex items-center gap-ds-1 text-ds-caption text-status-error bg-status-error/10 rounded-ds-sm px-ds-2 py-ds-1">
                              <span>{featuredCameraStates[vehicle.vehicle_id]?.last_error}</span>
                              <button
                                className="ml-auto text-ds-caption underline hover:no-underline"
                                onClick={() => {
                                  const state = featuredCameraStates[vehicle.vehicle_id]
                                  if (state?.desired_camera) {
                                    setFeaturedCamera.mutate({
                                      vehicleId: vehicle.vehicle_id,
                                      cameraId: state.desired_camera,
                                    })
                                  }
                                }}
                              >
                                Retry
                              </button>
                            </div>
                          </div>
                        )}
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          </Card>
        </div>

        {/* Right Column: Race Context */}
        <div className="lg:col-span-3 flex flex-col gap-ds-4 overflow-hidden">
          {/* Leaderboard */}
          <Card variant="default" padding="none" className="flex-1 flex flex-col overflow-hidden">
            <div className="px-ds-4 py-ds-3 border-b border-neutral-800 flex items-center justify-between flex-shrink-0">
              <h2 className="text-ds-heading text-neutral-50">Leaderboard</h2>
              <Badge variant="neutral" size="sm">Live order</Badge>
            </div>

            <div className="flex-1 overflow-y-auto">
              {!Array.isArray(leaderboard) || leaderboard.length === 0 ? (
                <div className="p-ds-4">
                  <EmptyState
                    title="No timing data yet"
                    description="Leaderboard updates after checkpoint crossings."
                  />
                </div>
              ) : (
                <div className="divide-y divide-neutral-800">
                  {leaderboard.slice(0, 10).map((entry) => (
                    <LeaderboardRow
                      key={entry.vehicle_id}
                      entry={entry}
                      isSelected={broadcastState?.featured_vehicle_id === entry.vehicle_id}
                      onSelect={() => setFeatured.mutate({ vehicleId: entry.vehicle_id })}
                    />
                  ))}
                </div>
              )}
            </div>
          </Card>

          {/* Edge Status Panel */}
          <Card variant="default" padding="none" className="flex-shrink-0 max-h-64 overflow-hidden flex flex-col">
            <div className="px-ds-4 py-ds-3 border-b border-neutral-800 flex items-center justify-between flex-shrink-0">
              <h2 className="text-ds-heading text-neutral-50">Edge Devices</h2>
              <Badge variant={edgeStatus?.streaming_count ? 'error' : 'neutral'} size="sm" dot={!!edgeStatus?.streaming_count} pulse={!!edgeStatus?.streaming_count}>
                {edgeStatus?.streaming_count || 0} streaming
              </Badge>
            </div>
            <div className="flex-1 overflow-y-auto">
              {!edgeStatus || !Array.isArray(edgeStatus.edges) || edgeStatus.edges.length === 0 ? (
                <div className="p-ds-4">
                  <EmptyState
                    title="No edge devices"
                    description="No edge devices are connected to this event."
                  />
                </div>
              ) : (
                <div className="divide-y divide-neutral-800">
                  {edgeStatus.edges.map((edge) => (
                    <button
                      key={edge.vehicle_id}
                      onClick={() => setSelectedVehicle(edge)}
                      className="w-full px-ds-4 py-ds-2 flex items-center justify-between text-left hover:bg-neutral-800/50 transition-colors duration-ds-fast"
                    >
                      <div className="flex items-center gap-ds-2">
                        <span className={`w-2 h-2 rounded-full ${
                          edge.edge_online ? 'bg-status-success' : 'bg-status-error'
                        }`} />
                        <span className="text-ds-body-sm font-medium">#{edge.vehicle_number}</span>
                        <span className="text-ds-caption text-neutral-500 truncate max-w-[80px]">{edge.team_name}</span>
                      </div>
                      <StreamingStatusBadge status={edge.streaming_status} camera={edge.streaming_camera} />
                    </button>
                  ))}
                </div>
              )}
            </div>
          </Card>

          {/* Alerts Panel */}
          <Card variant="default" padding="none" className="flex-shrink-0">
            <div className="px-ds-4 py-ds-3 border-b border-neutral-800">
              <h2 className="text-ds-heading text-neutral-50">Alerts</h2>
            </div>
            <div className="p-ds-4">
              <EmptyState
                title="No active alerts"
                description="Alert events will appear here when they occur."
              />
            </div>
          </Card>

          {/* PIT-NOTES-1: Pit Notes Panel */}
          <Card variant="default" padding="none" className="flex-shrink-0 max-h-48 overflow-hidden flex flex-col">
            <div className="px-ds-4 py-ds-3 border-b border-neutral-800 flex items-center justify-between flex-shrink-0">
              <h2 className="text-ds-heading text-neutral-50">Pit Notes</h2>
              {pitNotes && pitNotes.total > 0 && (
                <Badge variant="neutral" size="sm">{pitNotes.total}</Badge>
              )}
            </div>
            <div className="flex-1 overflow-y-auto">
              {!pitNotes || !Array.isArray(pitNotes.notes) || pitNotes.notes.length === 0 ? (
                <div className="p-ds-4">
                  <EmptyState
                    title="No pit notes"
                    description="Notes from pit crews will appear here."
                  />
                </div>
              ) : (
                <div className="divide-y divide-neutral-800">
                  {pitNotes.notes.slice(0, 10).map((note) => (
                    <div key={note.note_id} className="px-ds-4 py-ds-2">
                      <div className="flex items-center justify-between text-ds-caption text-neutral-500 mb-ds-1">
                        <span className="font-medium text-neutral-300">
                          #{note.vehicle_number || '?'} {note.team_name || ''}
                        </span>
                        <span>{new Date(note.timestamp_ms).toLocaleTimeString()}</span>
                      </div>
                      <p className="text-ds-body-sm text-neutral-200 break-words">{note.message}</p>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </Card>

          {/* Keyboard Shortcuts Reference */}
          <Card variant="elevated" padding="sm" className="flex-shrink-0">
            <div className="text-ds-body-sm font-semibold text-neutral-300 mb-ds-2">Keyboard Shortcuts</div>
            <div className="grid grid-cols-2 gap-ds-1 text-ds-caption text-neutral-400">
              <div><kbd className="px-ds-1 bg-neutral-700 rounded-ds-sm">1-9</kbd> Switch camera</div>
              <div><kbd className="px-ds-1 bg-neutral-700 rounded-ds-sm">Esc</kbd> Auto mode</div>
            </div>
          </Card>
        </div>
      </div>

      {/* Vehicle Drill-Down Modal */}
      {selectedVehicle && eventId && (
        <VehicleDrillDownModal
          vehicle={selectedVehicle}
          onClose={() => setSelectedVehicle(null)}
          eventId={eventId}
          adminToken={adminToken}
        />
      )}
    </div>
  )
}

/**
 * Truck status badge component
 */
function TruckStatusBadge({ status, small }: { status?: string; small?: boolean }) {
  if (small) {
    return (
      <span className={`w-2 h-2 rounded-full ${
        status === 'online' ? 'bg-status-success' :
        status === 'stale' ? 'bg-status-warning' :
        status === 'offline' ? 'bg-status-error' : 'bg-neutral-500'
      }`} />
    )
  }

  const variant = status === 'online' ? 'success' :
                  status === 'stale' ? 'warning' :
                  status === 'offline' ? 'error' : 'neutral'

  const label = status === 'online' ? 'Online' :
                status === 'stale' ? 'Stale' :
                status === 'offline' ? 'Offline' : 'Unknown'

  return <Badge variant={variant} size="sm">{label}</Badge>
}

/**
 * Leaderboard row component
 */
function LeaderboardRow({
  entry,
  isSelected,
  onSelect,
}: {
  entry: LeaderboardEntry
  isSelected: boolean
  onSelect: () => void
}) {
  return (
    <button
      onClick={onSelect}
      className={`w-full px-ds-4 py-ds-2 flex items-center justify-between text-left hover:bg-neutral-800/50 transition-colors duration-ds-fast ${
        isSelected ? 'bg-status-error/20' : ''
      }`}
    >
      <div className="flex items-center gap-ds-3">
        <span className={`w-6 h-6 flex items-center justify-center rounded-ds-sm font-bold text-ds-caption ${
          entry.position === 1 ? 'bg-status-warning text-neutral-950' :
          entry.position === 2 ? 'bg-neutral-300 text-neutral-950' :
          entry.position === 3 ? 'bg-amber-600 text-white' :
          'bg-neutral-700 text-neutral-300'
        }`}>
          {entry.position}
        </span>
        <div>
          <div className="text-ds-body-sm font-semibold flex items-center gap-ds-2">
            #{entry.vehicle_number}
            {isSelected && <Badge variant="error" size="sm">LIVE</Badge>}
          </div>
          <div className="text-ds-caption text-neutral-500 truncate max-w-[120px]">{entry.team_name}</div>
        </div>
      </div>
      <div className="text-right">
        <div className="text-ds-body-sm font-mono">
          {entry.position === 1 ? 'Leader' : entry.delta_formatted}
        </div>
        <div className="text-ds-caption text-neutral-500">
          CP {entry.last_checkpoint}
        </div>
      </div>
    </button>
  )
}

/**
 * Streaming status badge component
 */
function StreamingStatusBadge({ status, camera }: { status: string; camera?: string | null }) {
  const safeStatus = typeof status === 'string' ? status : 'unknown'
  const variant = safeStatus === 'live' ? 'error' :
                  safeStatus === 'starting' ? 'warning' :
                  safeStatus === 'error' ? 'warning' : 'neutral'

  const showDot = safeStatus === 'live' || safeStatus === 'starting'
  const showPulse = safeStatus === 'live'

  return (
    <Badge variant={variant} size="sm" dot={showDot} pulse={showPulse}>
      {safeStatus.charAt(0).toUpperCase() + safeStatus.slice(1)}
      {camera && safeStatus === 'live' && <span className="text-ds-caption opacity-70 ml-ds-1">({camera})</span>}
    </Badge>
  )
}

/**
 * Vehicle drill-down modal component with camera controls
 */
function VehicleDrillDownModal({
  vehicle,
  onClose,
  eventId,
  adminToken,
}: {
  vehicle: EdgeStatus
  onClose: () => void
  eventId: string
  adminToken: string
}) {
  const [pendingCommand, setPendingCommand] = useState<'start' | 'stop' | null>(null)
  const [commandResult, setCommandResult] = useState<{ status: 'success' | 'error'; message: string } | null>(null)
  const [showDiagnostics, setShowDiagnostics] = useState(false)
  const queryClient = useQueryClient()

  // Selected camera for streaming - defaults to current streaming camera or null
  const [selectedCamera, setSelectedCamera] = useState<string | null>(
    vehicle.streaming_camera || null
  )

  // Fetch stream state from state machine
  const { data: streamStateData } = useQuery({
    queryKey: ['stream-state', eventId, vehicle.vehicle_id],
    queryFn: async () => {
      const res = await fetch(
        `${API_BASE}/stream/events/${eventId}/vehicles/${vehicle.vehicle_id}/state`,
        { headers: { Authorization: `Bearer ${adminToken}` } }
      )
      if (!res.ok) return { state: 'IDLE', error_message: null }
      return res.json()
    },
    refetchInterval: 2000,
  })

  // Map API state to StreamState type
  const streamState: StreamState = (streamStateData?.state as StreamState) || 'IDLE'
  const errorMessage = streamStateData?.error_message as string | null

  // Map vehicle to EdgeStatusInfo for StreamControlPanel
  const edgeInfo: EdgeStatusInfo = {
    isOnline: vehicle.edge_online,
    lastHeartbeatAgoS: vehicle.last_heartbeat_ago_s,
    streamingStatus: vehicle.streaming_status,
    streamingCamera: vehicle.streaming_camera,
    streamingError: vehicle.streaming_error,
    youtubeConfigured: vehicle.youtube_configured,
    cameras: vehicle.cameras.map(c => ({ name: c.name, status: c.status })),
  }

  // Stream control handlers using unified stream control API
  const handleStartStream = async (camera: string) => {
    setPendingCommand('start')
    setCommandResult(null)

    try {
      // Use new unified stream control API
      const res = await fetch(
        `${API_BASE}/stream/events/${eventId}/vehicles/${vehicle.vehicle_id}/start`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${adminToken}`,
          },
          body: JSON.stringify({ source_id: camera }),
        }
      )

      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || `Failed to start stream: HTTP ${res.status}`)
      }

      const result = await res.json()

      // Stream control returns state and command_id
      if (result.state === 'ERROR') {
        setCommandResult({
          status: 'error',
          message: result.error_message || 'Failed to start stream',
        })
        return
      }

      // Poll stream state until STREAMING or ERROR (max 20 seconds)
      let attempts = 0
      const maxAttempts = 20
      while (attempts < maxAttempts) {
        await new Promise(r => setTimeout(r, 1000))
        attempts++

        const stateRes = await fetch(
          `${API_BASE}/stream/events/${eventId}/vehicles/${vehicle.vehicle_id}/state`,
          { headers: { Authorization: `Bearer ${adminToken}` } }
        )

        if (stateRes.ok) {
          const stateData = await stateRes.json()

          if (stateData.state === 'STREAMING') {
            setCommandResult({
              status: 'success',
              message: `Streaming live on ${CAMERA_LABELS[camera] || camera}`,
            })
            queryClient.invalidateQueries({ queryKey: ['edge-status', eventId] })
            return
          } else if (stateData.state === 'ERROR') {
            setCommandResult({
              status: 'error',
              message: stateData.error_message || 'Stream failed to start',
            })

            // Report timeout to state machine if applicable
            if (result.command_id && stateData.error_reason === 'EDGE_TIMEOUT') {
              await fetch(
                `${API_BASE}/stream/events/${eventId}/vehicles/${vehicle.vehicle_id}/timeout`,
                {
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/json',
                    Authorization: `Bearer ${adminToken}`,
                  },
                  body: JSON.stringify({ command_id: result.command_id }),
                }
              )
            }
            return
          } else if (stateData.state === 'IDLE' || stateData.state === 'DISCONNECTED') {
            // Stream didn't start - something went wrong
            setCommandResult({
              status: 'error',
              message: stateData.error_message || 'Stream request failed',
            })
            return
          }
          // Still STARTING - continue polling
        }
      }

      // Timeout - report to state machine
      if (result.command_id) {
        await fetch(
          `${API_BASE}/stream/events/${eventId}/vehicles/${vehicle.vehicle_id}/timeout`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${adminToken}`,
            },
            body: JSON.stringify({ command_id: result.command_id }),
          }
        )
      }

      setCommandResult({
        status: 'error',
        message: 'Stream start timed out - edge device may be unreachable',
      })
    } catch (err) {
      setCommandResult({
        status: 'error',
        message: err instanceof Error ? err.message : 'Failed to start stream',
      })
    } finally {
      setPendingCommand(null)
      queryClient.invalidateQueries({ queryKey: ['edge-status', eventId] })
    }
  }

  const handleStopStream = async () => {
    setPendingCommand('stop')
    setCommandResult(null)

    try {
      // Use new unified stream control API
      const res = await fetch(
        `${API_BASE}/stream/events/${eventId}/vehicles/${vehicle.vehicle_id}/stop`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${adminToken}`,
          },
        }
      )

      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || `Failed to stop stream: HTTP ${res.status}`)
      }

      const result = await res.json()

      // Poll stream state until IDLE or ERROR (max 15 seconds)
      let attempts = 0
      const maxAttempts = 15
      while (attempts < maxAttempts) {
        await new Promise(r => setTimeout(r, 1000))
        attempts++

        const stateRes = await fetch(
          `${API_BASE}/stream/events/${eventId}/vehicles/${vehicle.vehicle_id}/state`,
          { headers: { Authorization: `Bearer ${adminToken}` } }
        )

        if (stateRes.ok) {
          const stateData = await stateRes.json()

          if (stateData.state === 'IDLE' || stateData.state === 'DISCONNECTED') {
            setCommandResult({ status: 'success', message: 'Stream stopped' })
            setSelectedCamera(null)
            queryClient.invalidateQueries({ queryKey: ['edge-status', eventId] })
            return
          } else if (stateData.state === 'ERROR') {
            setCommandResult({
              status: 'error',
              message: stateData.error_message || 'Failed to stop stream',
            })
            return
          }
          // Still STOPPING - continue polling
        }
      }

      // Timeout
      if (result.command_id) {
        await fetch(
          `${API_BASE}/stream/events/${eventId}/vehicles/${vehicle.vehicle_id}/timeout`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${adminToken}`,
            },
            body: JSON.stringify({ command_id: result.command_id }),
          }
        )
      }

      setCommandResult({
        status: 'error',
        message: 'Stream stop timed out - stream may still be active',
      })
    } catch (err) {
      setCommandResult({
        status: 'error',
        message: err instanceof Error ? err.message : 'Failed to stop stream',
      })
    } finally {
      setPendingCommand(null)
      queryClient.invalidateQueries({ queryKey: ['edge-status', eventId] })
    }
  }

  return (
    <div className="fixed inset-0 bg-neutral-950/70 flex items-center justify-center z-50 p-ds-4" onClick={onClose}>
      <div className="bg-neutral-900 rounded-ds-lg border border-neutral-700 max-w-lg w-full max-h-[80vh] overflow-y-auto shadow-ds-overlay" onClick={e => e.stopPropagation()}>
        {/* Header */}
        <div className="px-ds-6 py-ds-4 border-b border-neutral-800 flex items-center justify-between">
          <div>
            <h2 className="text-ds-title flex items-center gap-ds-2">
              #{vehicle.vehicle_number}
              <span className={`w-2.5 h-2.5 rounded-full ${vehicle.edge_online ? 'bg-status-success' : 'bg-status-error'}`} />
            </h2>
            <p className="text-ds-body-sm text-neutral-400">{vehicle.team_name}</p>
          </div>
          <button onClick={onClose} className="p-ds-2 hover:bg-neutral-800 rounded-ds-md transition-colors duration-ds-fast">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Success Toast - Only show success messages */}
        {commandResult?.status === 'success' && (
          <div className="mx-ds-6 mt-ds-4">
            <Alert variant="success" onDismiss={() => setCommandResult(null)}>
              {commandResult.message}
            </Alert>
          </div>
        )}

        {/* Content */}
        <div className="p-ds-6 space-y-ds-6">
          {/* Stream Control Panel - Unified component with actionable errors */}
          <section>
            <h3 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wider mb-ds-3">Stream Control</h3>
            <StreamControlPanel
              edge={edgeInfo}
              streamState={streamState}
              errorMessage={errorMessage}
              selectedCamera={selectedCamera}
              onCameraSelect={setSelectedCamera}
              onStartStream={handleStartStream}
              onStopStream={handleStopStream}
              onDiagnostics={() => setShowDiagnostics(true)}
              isPending={pendingCommand !== null}
              pendingCommand={pendingCommand}
            />
          </section>

          {/* Connection Status */}
          <section>
            <h3 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wider mb-ds-3">Connection</h3>
            <div className="grid grid-cols-2 gap-ds-4">
              <div className="bg-neutral-800 rounded-ds-md p-ds-3">
                <div className="text-ds-caption text-neutral-500 mb-ds-1">Status</div>
                <div className={`text-ds-body-sm font-semibold ${
                  vehicle.connection_status === 'online' ? 'text-status-success' :
                  vehicle.connection_status === 'stale' ? 'text-status-warning' :
                  vehicle.connection_status === 'offline' ? 'text-status-error' : 'text-neutral-400'
                }`}>
                  {vehicle.connection_status.replace('_', ' ').toUpperCase()}
                </div>
              </div>
              <div className="bg-neutral-800 rounded-ds-md p-ds-3">
                <div className="text-ds-caption text-neutral-500 mb-ds-1">Last Heartbeat</div>
                <div className="font-mono text-ds-body-sm">
                  {vehicle.last_heartbeat_ago_s !== null
                    ? `${vehicle.last_heartbeat_ago_s}s ago`
                    : 'Never'}
                </div>
              </div>
              <div className="bg-neutral-800 rounded-ds-md p-ds-3">
                <div className="text-ds-caption text-neutral-500 mb-ds-1">Data Rate</div>
                <div className="font-mono text-ds-body-sm">{vehicle.data_rate_hz.toFixed(1)} Hz</div>
              </div>
              <div className="bg-neutral-800 rounded-ds-md p-ds-3">
                <div className="text-ds-caption text-neutral-500 mb-ds-1">Edge Online</div>
                <div className={`text-ds-body-sm font-semibold ${vehicle.edge_online ? 'text-status-success' : 'text-neutral-400'}`}>
                  {vehicle.edge_online ? 'Yes' : 'No'}
                </div>
              </div>
            </div>
          </section>

          {/* Streaming Status */}
          <section>
            <h3 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wider mb-ds-3">Streaming</h3>
            <div className="bg-neutral-800 rounded-ds-md p-ds-4 space-y-ds-3">
              <div className="flex items-center justify-between">
                <span className="text-ds-body-sm text-neutral-400">Status</span>
                <StreamingStatusBadge status={vehicle.streaming_status} camera={vehicle.streaming_camera} />
              </div>
              {vehicle.streaming_camera && (
                <div className="flex items-center justify-between">
                  <span className="text-ds-body-sm text-neutral-400">Active Camera</span>
                  <span className="font-mono text-ds-body-sm">{CAMERA_LABELS[vehicle.streaming_camera] || vehicle.streaming_camera}</span>
                </div>
              )}
              {vehicle.streaming_uptime_s !== null && vehicle.streaming_uptime_s > 0 && (
                <div className="flex items-center justify-between">
                  <span className="text-ds-body-sm text-neutral-400">Uptime</span>
                  <span className="font-mono text-ds-body-sm">{formatDuration(vehicle.streaming_uptime_s)}</span>
                </div>
              )}
              {vehicle.streaming_error && (
                <Alert variant="error" title="Error">
                  {vehicle.streaming_error}
                </Alert>
              )}
              <div className="flex items-center justify-between">
                <span className="text-ds-body-sm text-neutral-400">YouTube Configured</span>
                <span className={vehicle.youtube_configured ? 'text-status-success' : 'text-neutral-500'}>
                  {vehicle.youtube_configured ? 'Yes' : 'No'}
                </span>
              </div>
              {vehicle.youtube_url && (
                <div className="flex items-center justify-between">
                  <span className="text-ds-body-sm text-neutral-400">YouTube URL</span>
                  <a href={vehicle.youtube_url} target="_blank" rel="noopener noreferrer" className="text-accent-400 hover:underline text-ds-body-sm truncate max-w-[200px]">
                    {vehicle.youtube_url}
                  </a>
                </div>
              )}
            </div>
          </section>

          {/* Cameras */}
          <section>
            <h3 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wider mb-ds-3">Cameras</h3>
            {vehicle.cameras.length === 0 ? (
              <EmptyState title="No cameras detected" description="Connect cameras to the edge device to see them here." />
            ) : (
              <div className="grid grid-cols-2 gap-ds-2">
                {vehicle.cameras.map((cam) => (
                  <div key={cam.name} className="bg-neutral-800 rounded-ds-md p-ds-3">
                    <div className="text-ds-body-sm font-medium">{CAMERA_LABELS[cam.name] || cam.name}</div>
                    <div className="text-ds-caption text-neutral-500 font-mono">{cam.device || 'No device'}</div>
                    <div className={`text-ds-caption mt-ds-1 ${
                      cam.status === 'available' ? 'text-status-success' :
                      cam.status === 'active' ? 'text-status-error' : 'text-neutral-500'
                    }`}>
                      {cam.status === 'active' && <span className="inline-block w-1.5 h-1.5 rounded-full bg-status-error animate-pulse mr-ds-1" />}
                      {typeof cam.status === 'string' ? cam.status.charAt(0).toUpperCase() + cam.status.slice(1) : 'Unknown'}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>

          {/* Telemetry */}
          <section>
            <h3 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wider mb-ds-3">Telemetry</h3>
            <div className="grid grid-cols-2 gap-ds-4">
              <div className="bg-neutral-800 rounded-ds-md p-ds-3">
                <div className="text-ds-caption text-neutral-500 mb-ds-1">Last CAN</div>
                <div className="font-mono text-ds-body-sm">
                  {vehicle.last_can_ts
                    ? formatTimestamp(vehicle.last_can_ts)
                    : 'Never'}
                </div>
              </div>
              <div className="bg-neutral-800 rounded-ds-md p-ds-3">
                <div className="text-ds-caption text-neutral-500 mb-ds-1">Last GPS</div>
                <div className="font-mono text-ds-body-sm">
                  {vehicle.last_gps_ts
                    ? formatTimestamp(vehicle.last_gps_ts)
                    : 'Never'}
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>

      {/* Diagnostics Modal */}
      {showDiagnostics && (
        <DiagnosticsModal
          eventId={eventId}
          vehicleId={vehicle.vehicle_id}
          adminToken={adminToken}
          onClose={() => setShowDiagnostics(false)}
        />
      )}
    </div>
  )
}

/**
 * Helper to format duration in seconds to human readable
 */
function formatDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = Math.floor(seconds % 60)
  if (h > 0) {
    return `${h}h ${m}m ${s}s`
  } else if (m > 0) {
    return `${m}m ${s}s`
  }
  return `${s}s`
}

/**
 * Helper to format timestamp to relative time
 */
function formatTimestamp(ts: number): string {
  const now = Date.now()
  const diff = Math.floor((now - ts) / 1000)
  if (diff < 5) return 'Just now'
  if (diff < 60) return `${diff}s ago`
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
  return `${Math.floor(diff / 3600)}h ago`
}

/**
 * Helper to extract YouTube video ID from URL
 */
function extractYouTubeId(url: string): string {
  if (!url) return ''
  const match = url.match(/(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=))([^?&]+)/)
  return match ? match[1] : url
}
