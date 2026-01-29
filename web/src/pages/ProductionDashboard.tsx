/**
 * Production Director Dashboard
 *
 * Control interface for broadcast directors to manage:
 * - Multi-camera switching
 * - Featured vehicle selection
 * - Live feed monitoring
 *
 * Requires admin authentication via Authorization: Bearer header.
 * Uses standardized 'admin_token' localStorage key.
 */
import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { AppLoading, Spinner, StatusPill, PageHeader } from '../components/common'

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

interface TruckDiagnostics {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  connection: {
    last_heartbeat_ms: number | null
    last_heartbeat_ago_s: number | null
    data_rate_hz: number
    status: string
  }
  gps: {
    has_position: boolean
    lat: number | null
    lon: number | null
    speed_mps: number | null
    last_update_ms: number | null
  }
  video: {
    feed_count: number
    feeds: { camera_name: string; youtube_url: string }[]
  }
  recommendation: string
  checked_at: string
}

// PROMPT 5: Production telemetry response
interface ProductionTelemetry {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  telemetry: Record<string, number | string | null>
  policy: {
    allow_production: string[]
    allow_fans: string[]
  }
  last_update_ms: number | null
}

// CAM-CONTRACT-1B: Canonical 4-camera slots
const CAMERA_LABELS: Record<string, string> = {
  main: 'Main Cam',
  cockpit: 'Cockpit',
  chase: 'Chase Cam',
  suspension: 'Suspension',
}

export default function ProductionDashboard() {
  const { eventId } = useParams<{ eventId: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  // STANDARDIZED: Use 'admin_token' key (same as AdminLogin)
  const [adminToken, setAdminToken] = useState(() =>
    localStorage.getItem('admin_token') || ''
  )
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [tokenInput, setTokenInput] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [selectedTruckDiagnostics, setSelectedTruckDiagnostics] = useState<TruckDiagnostics | null>(null)
  const [selectedTruckTelemetry, setSelectedTruckTelemetry] = useState<ProductionTelemetry | null>(null)
  const [showTruckPanel, setShowTruckPanel] = useState(true)

  // Fetch broadcast state
  const { data: broadcastState, isLoading } = useQuery({
    queryKey: ['broadcast', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/broadcast`)
      if (!res.ok) throw new Error('Failed to fetch broadcast state')
      return res.json() as Promise<BroadcastState>
    },
    enabled: !!eventId,
    refetchInterval: 5000,
  })

  // Fetch all available cameras
  const { data: cameras } = useQuery({
    queryKey: ['cameras', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/cameras`)
      if (!res.ok) throw new Error('Failed to fetch cameras')
      return res.json() as Promise<CameraFeed[]>
    },
    enabled: !!eventId,
    refetchInterval: 10000,
  })

  // Fetch truck connectivity status
  const { data: truckStatus, refetch: refetchTruckStatus } = useQuery({
    queryKey: ['truck-status', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/truck-status`, {
        headers: { Authorization: `Bearer ${adminToken}` },
      })
      if (!res.ok) {
        if (res.status === 401) {
          setIsAuthenticated(false)
          localStorage.removeItem('admin_token')
        }
        throw new Error('Failed to fetch truck status')
      }
      return res.json() as Promise<TruckStatusList>
    },
    enabled: !!eventId && isAuthenticated,
    refetchInterval: 5000, // Check status every 5 seconds
  })

  // Switch camera mutation
  const switchCamera = useMutation({
    mutationFn: async ({ vehicleId, cameraName }: { vehicleId: string; cameraName: string }) => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/switch-camera`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${adminToken}`,
        },
        body: JSON.stringify({ vehicle_id: vehicleId, camera_name: cameraName }),
      })
      if (!res.ok) {
        const data = await res.json()
        throw new Error(data.detail || 'Failed to switch camera')
      }
      return res.json()
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['broadcast', eventId] })
      setError(null)
    },
    onError: (err: Error) => {
      setError(err.message)
      if (err.message.includes('401') || err.message.includes('Invalid')) {
        setIsAuthenticated(false)
        localStorage.removeItem('admin_token')
      }
    },
  })

  // Set featured vehicle mutation
  const setFeatured = useMutation({
    mutationFn: async ({ vehicleId, duration }: { vehicleId: string; duration?: number }) => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/featured-vehicle`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${adminToken}`,
        },
        body: JSON.stringify({ vehicle_id: vehicleId, duration_seconds: duration }),
      })
      if (!res.ok) {
        const data = await res.json()
        throw new Error(data.detail || 'Failed to set featured vehicle')
      }
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

  // Test truck connection
  const testConnection = useMutation({
    mutationFn: async (vehicleId: string) => {
      const res = await fetch(`${API_BASE}/production/events/${eventId}/trucks/${vehicleId}/test-connection`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${adminToken}` },
      })
      if (!res.ok) throw new Error('Failed to test connection')
      return res.json() as Promise<TruckDiagnostics>
    },
    onSuccess: async (data) => {
      setSelectedTruckDiagnostics(data)
      // PROMPT 5: Also fetch production telemetry
      try {
        const telemetryRes = await fetch(
          `${API_BASE}/production/events/${eventId}/vehicles/${data.vehicle_id}/telemetry`,
          { headers: { Authorization: `Bearer ${adminToken}` } }
        )
        if (telemetryRes.ok) {
          const telemetryData = await telemetryRes.json() as ProductionTelemetry
          setSelectedTruckTelemetry(telemetryData)
        }
      } catch {
        // Telemetry fetch is optional, don't fail on error
      }
    },
    onError: (err: Error) => {
      setError(`Connection test failed: ${err.message}`)
    },
  })

  // Login handler
  const handleLogin = useCallback(() => {
    if (!tokenInput.trim()) return
    localStorage.setItem('admin_token', tokenInput)
    setAdminToken(tokenInput)
    setIsAuthenticated(true)
    setError(null)
  }, [tokenInput])

  // Check if we have a stored token
  useEffect(() => {
    if (adminToken) {
      setIsAuthenticated(true)
    }
  }, [adminToken])

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

  // Login screen
  if (!isAuthenticated) {
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
              <h1 className="text-ds-title text-neutral-50">Production Director</h1>
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
          />

          <button
            onClick={handleLogin}
            className="w-full py-ds-3 bg-accent-600 hover:bg-accent-700 text-white font-semibold rounded-ds-md transition-colors duration-ds-fast"
          >
            Access Dashboard
          </button>

          <button
            onClick={() => navigate(`/events/${eventId}`)}
            className="w-full mt-ds-3 py-ds-2 text-neutral-400 hover:text-neutral-50 text-ds-body-sm transition-colors duration-ds-fast"
          >
            Return to Fan View
          </button>
        </div>
      </div>
    )
  }

  if (isLoading) {
    return <AppLoading message="Loading broadcast state..." />
  }

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-50">
      <PageHeader
        title="Production Dashboard"
        subtitle={`Event: ${eventId}`}
        backTo={`/events/${eventId}`}
        backLabel="Back to event"
        rightSlot={
          <div className="flex items-center gap-ds-3">
            <StatusPill label="LIVE" variant="success" pulse />
            <button
              onClick={() => {
                localStorage.removeItem('admin_token')
                setIsAuthenticated(false)
                setAdminToken('')
              }}
              className="px-ds-3 py-ds-2 text-ds-body-sm bg-neutral-800 hover:bg-neutral-700 rounded-ds-md transition-colors duration-ds-fast"
            >
              Logout
            </button>
          </div>
        }
      />

      {error && (
        <div className="mx-ds-4 mt-ds-4 p-ds-3 bg-status-error/10 border border-status-error/30 rounded-ds-md text-status-error text-ds-body-sm flex items-start gap-ds-2">
          <svg className="w-5 h-5 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          {error}
        </div>
      )}

      {/* Truck Status Panel - Collapsible */}
      <div className="mx-ds-4 mt-ds-4">
        <button
          onClick={() => setShowTruckPanel(!showTruckPanel)}
          className="w-full flex items-center justify-between px-ds-4 py-ds-3 bg-neutral-900 rounded-t-ds-lg border border-neutral-800 hover:bg-neutral-800 transition-colors duration-ds-fast"
        >
          <div className="flex items-center gap-ds-3">
            <h2 className="text-ds-body font-semibold">Truck Connectivity</h2>
            {truckStatus && (
              <StatusPill
                label={`${truckStatus.online_count}/${truckStatus.total_count} online`}
                variant={
                  truckStatus.online_count === truckStatus.total_count
                    ? 'success'
                    : truckStatus.online_count > 0
                    ? 'warning'
                    : 'error'
                }
              />
            )}
          </div>
          <span className="text-neutral-400">{showTruckPanel ? '▲' : '▼'}</span>
        </button>

        {showTruckPanel && (
          <div className="bg-neutral-900 rounded-b-ds-lg border border-t-0 border-neutral-800 p-ds-4">
            {!truckStatus ? (
              <div className="flex items-center gap-ds-2 text-neutral-500 text-ds-body-sm">
                <Spinner size="sm" />
                Loading truck status...
              </div>
            ) : truckStatus.trucks.length === 0 ? (
              <div className="text-neutral-500 text-ds-body-sm">No trucks registered for this event.</div>
            ) : (
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-ds-3">
                {truckStatus.trucks.map((truck) => (
                  <div
                    key={truck.vehicle_id}
                    className={`p-ds-3 rounded-ds-md border transition-all duration-ds-fast ${
                      truck.status === 'online'
                        ? 'bg-status-success/10 border-status-success/30'
                        : truck.status === 'stale'
                        ? 'bg-status-warning/10 border-status-warning/30'
                        : truck.status === 'offline'
                        ? 'bg-status-error/10 border-status-error/30'
                        : 'bg-neutral-800 border-neutral-700'
                    }`}
                  >
                    <div className="flex items-center justify-between mb-ds-2">
                      <span className="font-bold text-ds-body">#{truck.vehicle_number}</span>
                      <span className={`w-2.5 h-2.5 rounded-full ${
                        truck.status === 'online'
                          ? 'bg-status-success animate-pulse'
                          : truck.status === 'stale'
                          ? 'bg-status-warning'
                          : truck.status === 'offline'
                          ? 'bg-status-error'
                          : 'bg-neutral-500'
                      }`} />
                    </div>
                    <div className="text-ds-caption text-neutral-400 truncate mb-ds-1">{truck.team_name}</div>
                    <div className="flex items-center gap-ds-1 text-ds-caption">
                      {truck.status === 'online' ? (
                        <span className="text-status-success">{truck.data_rate_hz} Hz</span>
                      ) : truck.status === 'stale' ? (
                        <span className="text-status-warning">{truck.last_heartbeat_ago_s}s ago</span>
                      ) : truck.status === 'offline' ? (
                        <span className="text-status-error">
                          {truck.last_heartbeat_ago_s ? `${Math.round(truck.last_heartbeat_ago_s / 60)}m ago` : 'offline'}
                        </span>
                      ) : (
                        <span className="text-neutral-500">never connected</span>
                      )}
                      {truck.has_video_feed && (
                        <span className="ml-auto text-accent-400" title="Has video feed">📹</span>
                      )}
                    </div>
                    <button
                      onClick={() => testConnection.mutate(truck.vehicle_id)}
                      disabled={testConnection.isPending}
                      className="mt-ds-2 w-full px-ds-2 py-ds-1 text-ds-caption bg-neutral-700 hover:bg-neutral-600 rounded-ds-sm transition-colors duration-ds-fast disabled:opacity-50"
                    >
                      {testConnection.isPending && testConnection.variables === truck.vehicle_id
                        ? 'Testing...'
                        : 'Test'}
                    </button>
                  </div>
                ))}
              </div>
            )}

            {/* Refresh button */}
            <div className="mt-ds-3 flex items-center justify-between text-ds-caption text-neutral-500">
              <span>
                Last checked: {truckStatus?.checked_at
                  ? new Date(truckStatus.checked_at).toLocaleTimeString()
                  : '--'}
              </span>
              <button
                onClick={() => refetchTruckStatus()}
                className="text-accent-400 hover:text-accent-300 transition-colors duration-ds-fast"
              >
                Refresh Now
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Truck Diagnostics Modal */}
      {selectedTruckDiagnostics && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-ds-4">
          <div className="bg-neutral-900 rounded-ds-lg border border-neutral-700 max-w-lg w-full max-h-[80vh] overflow-y-auto">
            <div className="p-ds-4 border-b border-neutral-800 flex items-center justify-between">
              <h3 className="text-ds-body font-semibold">
                Truck #{selectedTruckDiagnostics.vehicle_number} Diagnostics
              </h3>
              <button
                onClick={() => setSelectedTruckDiagnostics(null)}
                className="text-neutral-400 hover:text-neutral-50 transition-colors duration-ds-fast"
              >
                ✕
              </button>
            </div>

            <div className="p-ds-4 space-y-ds-4">
              {/* Connection Status */}
              <div>
                <h4 className="text-ds-caption uppercase tracking-wide text-neutral-500 mb-ds-2">Connection</h4>
                <div className={`p-ds-3 rounded-ds-md ${
                  selectedTruckDiagnostics.connection.status === 'online'
                    ? 'bg-status-success/10 border border-status-success/30'
                    : selectedTruckDiagnostics.connection.status === 'stale'
                    ? 'bg-status-warning/10 border border-status-warning/30'
                    : 'bg-status-error/10 border border-status-error/30'
                }`}>
                  <div className="flex items-center gap-ds-2 mb-ds-2">
                    <span className={`w-3 h-3 rounded-full ${
                      selectedTruckDiagnostics.connection.status === 'online'
                        ? 'bg-status-success'
                        : selectedTruckDiagnostics.connection.status === 'stale'
                        ? 'bg-status-warning'
                        : 'bg-status-error'
                    }`} />
                    <span className="font-semibold capitalize">
                      {selectedTruckDiagnostics.connection.status}
                    </span>
                  </div>
                  <div className="grid grid-cols-2 gap-ds-2 text-ds-body-sm">
                    <div>
                      <span className="text-neutral-500">Data Rate:</span>
                      <span className="ml-2 font-mono">{selectedTruckDiagnostics.connection.data_rate_hz} Hz</span>
                    </div>
                    <div>
                      <span className="text-neutral-500">Last Seen:</span>
                      <span className="ml-2 font-mono">
                        {selectedTruckDiagnostics.connection.last_heartbeat_ago_s
                          ? `${selectedTruckDiagnostics.connection.last_heartbeat_ago_s}s ago`
                          : 'Never'}
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              {/* GPS Status */}
              <div>
                <h4 className="text-ds-caption uppercase tracking-wide text-neutral-500 mb-ds-2">GPS Data</h4>
                <div className="bg-neutral-800 p-ds-3 rounded-ds-md">
                  {selectedTruckDiagnostics.gps.has_position ? (
                    <div className="grid grid-cols-2 gap-ds-2 text-ds-body-sm">
                      <div>
                        <span className="text-neutral-500">Latitude:</span>
                        <span className="ml-2 font-mono">{selectedTruckDiagnostics.gps.lat?.toFixed(5)}</span>
                      </div>
                      <div>
                        <span className="text-neutral-500">Longitude:</span>
                        <span className="ml-2 font-mono">{selectedTruckDiagnostics.gps.lon?.toFixed(5)}</span>
                      </div>
                      <div>
                        <span className="text-neutral-500">Speed:</span>
                        <span className="ml-2 font-mono">
                          {selectedTruckDiagnostics.gps.speed_mps
                            ? `${(selectedTruckDiagnostics.gps.speed_mps * 2.237).toFixed(1)} mph`
                            : 'N/A'}
                        </span>
                      </div>
                    </div>
                  ) : (
                    <div className="text-neutral-500 text-ds-body-sm">No GPS data received yet</div>
                  )}
                </div>
              </div>

              {/* Video Status */}
              <div>
                <h4 className="text-ds-caption uppercase tracking-wide text-neutral-500 mb-ds-2">Video Feeds</h4>
                <div className="bg-neutral-800 p-ds-3 rounded-ds-md">
                  {selectedTruckDiagnostics.video.feed_count > 0 ? (
                    <div className="space-y-ds-2">
                      {selectedTruckDiagnostics.video.feeds.map((feed) => (
                        <div key={feed.camera_name} className="flex items-center justify-between text-ds-body-sm">
                          <span className="capitalize">{feed.camera_name}</span>
                          <span className="text-status-success text-ds-caption">Configured</span>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="text-neutral-500 text-ds-body-sm">No video feeds configured</div>
                  )}
                </div>
              </div>

              {/* Production Telemetry */}
              {selectedTruckTelemetry && (
                <div>
                  <h4 className="text-ds-caption uppercase tracking-wide text-neutral-500 mb-ds-2">
                    Production Telemetry
                    <span className="ml-2 text-status-success normal-case">
                      ({selectedTruckTelemetry.policy.allow_production.length} fields allowed)
                    </span>
                  </h4>
                  <div className="bg-neutral-800 p-ds-3 rounded-ds-md">
                    {Object.keys(selectedTruckTelemetry.telemetry).length > 0 ? (
                      <div className="grid grid-cols-2 gap-ds-2 text-ds-body-sm">
                        {Object.entries(selectedTruckTelemetry.telemetry).map(([field, value]) => (
                          <div key={field} className="flex justify-between">
                            <span className="text-neutral-500 capitalize">
                              {field.replace(/_/g, ' ')}:
                            </span>
                            <span className="font-mono">
                              {typeof value === 'number' ? value.toFixed(2) : value ?? 'N/A'}
                            </span>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <div className="text-neutral-500 text-ds-body-sm">
                        No telemetry data available
                        {selectedTruckTelemetry.policy.allow_production.length === 0 && (
                          <span className="block mt-ds-1 text-status-warning text-ds-caption">
                            Team has not enabled any fields for production
                          </span>
                        )}
                      </div>
                    )}
                    {/* Show what's shared with fans */}
                    {selectedTruckTelemetry.policy.allow_fans.length > 0 && (
                      <div className="mt-ds-3 pt-ds-3 border-t border-neutral-700">
                        <div className="text-ds-caption text-neutral-500">
                          Fans can see: {selectedTruckTelemetry.policy.allow_fans.join(', ')}
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Recommendation */}
              <div className="bg-accent-600/10 border border-accent-600/30 rounded-ds-md p-ds-3">
                <div className="text-ds-caption uppercase tracking-wide text-accent-400 mb-ds-1">Recommendation</div>
                <div className="text-ds-body-sm">{selectedTruckDiagnostics.recommendation}</div>
              </div>
            </div>

            <div className="p-ds-4 border-t border-neutral-800">
              <button
                onClick={() => {
                  setSelectedTruckDiagnostics(null)
                  setSelectedTruckTelemetry(null)
                }}
                className="w-full py-ds-2 bg-neutral-800 hover:bg-neutral-700 rounded-ds-md transition-colors duration-ds-fast"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="p-ds-4 pb-20 grid grid-cols-1 lg:grid-cols-3 gap-ds-6">
        {/* Current Broadcast Panel */}
        <div className="lg:col-span-1 bg-neutral-900 rounded-ds-lg border border-neutral-800 p-ds-4">
          <h2 className="text-ds-body font-semibold mb-ds-4 flex items-center gap-ds-2">
            <span className="w-3 h-3 rounded-full bg-status-error animate-pulse"></span>
            ON AIR
          </h2>

          {broadcastState?.featured_vehicle_id ? (
            <div className="space-y-ds-4">
              <div className="aspect-video bg-black rounded-ds-md overflow-hidden relative">
                {broadcastState.active_feeds.find(
                  f => f.vehicle_id === broadcastState.featured_vehicle_id &&
                       f.camera_name === broadcastState.featured_camera
                )?.youtube_url ? (
                  <iframe
                    src={`https://www.youtube.com/embed/${extractYouTubeId(
                      broadcastState.active_feeds.find(
                        f => f.vehicle_id === broadcastState.featured_vehicle_id
                      )?.youtube_url || ''
                    )}?autoplay=1&mute=1`}
                    className="w-full h-full"
                    allow="autoplay; encrypted-media"
                    allowFullScreen
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center text-neutral-500">
                    No Video Feed
                  </div>
                )}
                <div className="absolute top-2 left-2 px-ds-2 py-ds-1 bg-black/70 rounded-ds-sm text-ds-caption font-mono">
                  {CAMERA_LABELS[broadcastState.featured_camera || ''] || broadcastState.featured_camera}
                </div>
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <div className="font-bold text-ds-body">
                    #{cameras?.find(c => c.vehicle_id === broadcastState.featured_vehicle_id)?.vehicle_number}
                  </div>
                  <div className="text-ds-body-sm text-neutral-400">
                    {cameras?.find(c => c.vehicle_id === broadcastState.featured_vehicle_id)?.team_name}
                  </div>
                </div>
                <button
                  onClick={() => clearFeatured.mutate()}
                  className="px-ds-3 py-ds-2 bg-neutral-800 hover:bg-neutral-700 text-ds-body-sm rounded-ds-md transition-colors duration-ds-fast"
                >
                  Auto Mode
                </button>
              </div>
            </div>
          ) : (
            <div className="aspect-video bg-neutral-800 rounded-ds-md flex items-center justify-center">
              <div className="text-center text-neutral-500">
                <div className="text-ds-title mb-ds-2">AUTO</div>
                <div className="text-ds-body-sm">Select a camera below</div>
              </div>
            </div>
          )}
        </div>

        {/* Camera Grid */}
        <div className="lg:col-span-2">
          <h2 className="text-ds-body font-semibold mb-ds-4">Available Cameras</h2>

          {Object.values(camerasByVehicle || {}).length === 0 ? (
            <div className="text-center py-12">
              <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-neutral-800 mb-ds-4">
                <svg className="w-8 h-8 text-neutral-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
                </svg>
              </div>
              <h3 className="text-ds-headline text-neutral-300 mb-ds-2">No Camera Feeds</h3>
              <p className="text-ds-body-sm text-neutral-500">
                Teams need to configure video feeds in their dashboard.
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-ds-4">
              {Object.values(camerasByVehicle || {}).map((vehicle) => (
                <div
                  key={vehicle.vehicle_id}
                  className={`bg-neutral-900 rounded-ds-lg border transition-all duration-ds-fast ${
                    broadcastState?.featured_vehicle_id === vehicle.vehicle_id
                      ? 'border-accent-500 ring-2 ring-accent-500/30'
                      : 'border-neutral-800 hover:border-neutral-700'
                  }`}
                >
                  <div className="p-ds-3 border-b border-neutral-800 flex items-center justify-between">
                    <div>
                      <span className="font-bold text-ds-body">#{vehicle.vehicle_number}</span>
                      <span className="text-neutral-400 text-ds-body-sm ml-2">{vehicle.team_name}</span>
                    </div>
                    <button
                      onClick={() => setFeatured.mutate({ vehicleId: vehicle.vehicle_id })}
                      className={`px-ds-2 py-ds-1 text-ds-caption rounded-ds-sm transition-colors duration-ds-fast ${
                        broadcastState?.featured_vehicle_id === vehicle.vehicle_id
                          ? 'bg-accent-600 text-white'
                          : 'bg-neutral-800 hover:bg-neutral-700 text-neutral-300'
                      }`}
                    >
                      {broadcastState?.featured_vehicle_id === vehicle.vehicle_id ? 'FEATURED' : 'Feature'}
                    </button>
                  </div>

                  <div className="p-ds-3 grid grid-cols-2 gap-ds-2">
                    {vehicle.cameras.map((cam) => (
                      <button
                        key={`${cam.vehicle_id}-${cam.camera_name}`}
                        onClick={() => switchCamera.mutate({
                          vehicleId: cam.vehicle_id,
                          cameraName: cam.camera_name
                        })}
                        disabled={switchCamera.isPending}
                        className={`p-ds-3 rounded-ds-md text-left transition-all duration-ds-fast ${
                          broadcastState?.featured_vehicle_id === cam.vehicle_id &&
                          broadcastState?.featured_camera === cam.camera_name
                            ? 'bg-status-error text-white ring-2 ring-status-error/50'
                            : 'bg-neutral-800 hover:bg-neutral-700 text-neutral-200'
                        }`}
                      >
                        <div className="text-ds-caption uppercase tracking-wide opacity-70">
                          {CAMERA_LABELS[cam.camera_name] || cam.camera_name}
                        </div>
                        <div className="flex items-center gap-ds-1 mt-ds-1">
                          {cam.is_live ? (
                            <>
                              <span className="w-1.5 h-1.5 rounded-full bg-status-success"></span>
                              <span className="text-ds-caption text-status-success">Live</span>
                            </>
                          ) : (
                            <>
                              <span className="w-1.5 h-1.5 rounded-full bg-neutral-500"></span>
                              <span className="text-ds-caption text-neutral-500">Offline</span>
                            </>
                          )}
                        </div>
                      </button>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Quick Actions Bar */}
      <div className="fixed bottom-0 left-0 right-0 bg-neutral-900 border-t border-neutral-800 px-ds-4 py-ds-3">
        <div className="flex items-center justify-between max-w-7xl mx-auto">
          <div className="flex items-center gap-ds-4">
            <span className="text-ds-body-sm text-neutral-400">Quick Switch:</span>
            {cameras?.slice(0, 4).map((cam) => (
              <button
                key={`quick-${cam.vehicle_id}`}
                onClick={() => switchCamera.mutate({
                  vehicleId: cam.vehicle_id,
                  cameraName: cam.camera_name
                })}
                className="px-ds-3 py-ds-2 bg-neutral-800 hover:bg-neutral-700 rounded-ds-sm text-ds-body-sm font-mono transition-colors duration-ds-fast"
              >
                #{cam.vehicle_number}
              </button>
            ))}
          </div>
          <button
            onClick={() => navigate(`/events/${eventId}`)}
            className="px-ds-4 py-ds-2 text-ds-body-sm text-neutral-400 hover:text-neutral-50 transition-colors duration-ds-fast"
          >
            View Fan Page
          </button>
        </div>
      </div>
    </div>
  )
}

// Helper to extract YouTube video ID from URL
function extractYouTubeId(url: string): string {
  if (!url) return ''
  const match = url.match(/(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=))([^?&]+)/)
  return match ? match[1] : url
}
