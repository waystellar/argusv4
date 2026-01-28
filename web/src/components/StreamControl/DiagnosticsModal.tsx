/**
 * DiagnosticsModal - Shows stream control system diagnostics
 *
 * UI-14: Migrated to design system tokens (neutral-*, status-*, accent-*)
 *
 * Fetches diagnostic data from the API and displays it in a user-friendly format.
 * For technical users who need to debug stream control issues.
 *
 * Shows:
 * - Edge device status from Redis
 * - Stream state machine state
 * - Pending commands
 * - Recent heartbeat info
 */

import { useState, useEffect, useCallback } from 'react'

interface DiagnosticsModalProps {
  eventId: string
  vehicleId: string
  adminToken: string
  onClose: () => void
}

interface DiagnosticsData {
  timestamp: string
  edge_status: {
    vehicle_id: string
    connection_status: string
    last_heartbeat_ago_s: number | null
    streaming_status: string
    streaming_camera: string | null
    streaming_error: string | null
    youtube_configured: boolean
    cameras: { name: string; status: string }[]
  } | null
  stream_state: {
    state: string
    source_id: string | null
    command_id: string | null
    error_message: string | null
    updated_at: string
  } | null
  pending_commands: {
    command_id: string
    command: string
    created_at: string
    ttl_s: number
  }[]
  raw_redis?: Record<string, unknown>
}

export default function DiagnosticsModal({
  eventId,
  vehicleId,
  adminToken,
  onClose,
}: DiagnosticsModalProps) {
  const [data, setData] = useState<DiagnosticsData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showRaw, setShowRaw] = useState(false)

  const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

  const fetchDiagnostics = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      // Fetch edge status
      const edgeRes = await fetch(
        `${API_BASE}/production/events/${eventId}/edge-status`,
        { headers: { Authorization: `Bearer ${adminToken}` } }
      )
      const edgeData = edgeRes.ok ? await edgeRes.json() : null
      const edgeStatus = edgeData?.edges?.find((e: { vehicle_id: string }) => e.vehicle_id === vehicleId) || null

      // Fetch stream state
      const stateRes = await fetch(
        `${API_BASE}/stream/events/${eventId}/vehicles/${vehicleId}/state`,
        { headers: { Authorization: `Bearer ${adminToken}` } }
      )
      const streamState = stateRes.ok ? await stateRes.json() : null

      // Compose diagnostics data
      const diagnostics: DiagnosticsData = {
        timestamp: new Date().toISOString(),
        edge_status: edgeStatus ? {
          vehicle_id: edgeStatus.vehicle_id,
          connection_status: edgeStatus.connection_status,
          last_heartbeat_ago_s: edgeStatus.last_heartbeat_ago_s,
          streaming_status: edgeStatus.streaming_status,
          streaming_camera: edgeStatus.streaming_camera,
          streaming_error: edgeStatus.streaming_error,
          youtube_configured: edgeStatus.youtube_configured,
          cameras: edgeStatus.cameras || [],
        } : null,
        stream_state: streamState ? {
          state: streamState.state,
          source_id: streamState.source_id,
          command_id: streamState.command_id,
          error_message: streamState.error_message,
          updated_at: streamState.updated_at,
        } : null,
        pending_commands: [], // Would need a separate endpoint
        raw_redis: {
          edge_status: edgeStatus,
          stream_state: streamState,
        },
      }

      setData(diagnostics)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch diagnostics')
    } finally {
      setLoading(false)
    }
  }, [eventId, vehicleId, adminToken, API_BASE])

  useEffect(() => {
    fetchDiagnostics()
  }, [fetchDiagnostics])

  const formatTime = (iso: string) => {
    try {
      return new Date(iso).toLocaleString()
    } catch {
      return iso
    }
  }

  return (
    <div
      className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-ds-4"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-labelledby="diagnostics-title"
    >
      <div
        className="bg-neutral-900 rounded-ds-lg border border-neutral-700 max-w-2xl w-full max-h-[80vh] overflow-hidden flex flex-col shadow-ds-overlay"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="px-ds-6 py-ds-4 border-b border-neutral-800 flex items-center justify-between flex-shrink-0">
          <div>
            <h2 id="diagnostics-title" className="text-ds-heading text-neutral-50">Stream Control Diagnostics</h2>
            <p className="text-ds-body-sm text-neutral-400">Vehicle: {vehicleId}</p>
          </div>
          <div className="flex items-center gap-ds-2">
            <button
              onClick={fetchDiagnostics}
              disabled={loading}
              className="p-ds-2 hover:bg-neutral-800 rounded-ds-md transition-colors duration-ds-fast disabled:opacity-50 focus:outline-none focus:ring-2 focus:ring-accent-500"
              title="Refresh"
            >
              <svg
                className={`w-5 h-5 text-neutral-300 ${loading ? 'animate-spin' : ''}`}
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
            </button>
            <button
              onClick={onClose}
              className="p-ds-2 hover:bg-neutral-800 rounded-ds-md transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500"
              aria-label="Close dialog"
            >
              <svg className="w-5 h-5 text-neutral-300" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-ds-6 space-y-ds-6">
          {loading && !data && (
            <div className="flex items-center justify-center py-12">
              <div className="w-8 h-8 border-4 border-accent-500 border-t-transparent rounded-full animate-spin" />
            </div>
          )}

          {error && (
            <div className="bg-status-error/10 border border-status-error/30 rounded-ds-md p-ds-4 text-status-error">
              <div className="font-medium">Failed to load diagnostics</div>
              <div className="text-ds-body-sm mt-ds-1 opacity-80">{error}</div>
            </div>
          )}

          {data && (
            <>
              {/* Timestamp */}
              <div className="text-ds-caption text-neutral-500">
                Captured: {formatTime(data.timestamp)}
              </div>

              {/* Edge Status */}
              <section>
                <h3 className="text-ds-body-sm font-semibold text-neutral-400 uppercase tracking-wider mb-ds-3">
                  Edge Status
                </h3>
                {data.edge_status ? (
                  <div className="bg-neutral-800 rounded-ds-md p-ds-4 space-y-ds-2 font-mono text-ds-body-sm">
                    <div className="flex justify-between">
                      <span className="text-neutral-500">Connection:</span>
                      <span className={
                        data.edge_status.connection_status === 'online' ? 'text-status-success' :
                        data.edge_status.connection_status === 'stale' ? 'text-status-warning' :
                        'text-status-error'
                      }>
                        {data.edge_status.connection_status}
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-neutral-500">Last Heartbeat:</span>
                      <span className="text-neutral-200">
                        {data.edge_status.last_heartbeat_ago_s !== null
                          ? `${data.edge_status.last_heartbeat_ago_s}s ago`
                          : 'Never'}
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-neutral-500">Streaming Status:</span>
                      <span className={
                        data.edge_status.streaming_status === 'live' ? 'text-status-error' :
                        data.edge_status.streaming_status === 'starting' ? 'text-status-warning' :
                        'text-neutral-400'
                      }>
                        {data.edge_status.streaming_status}
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-neutral-500">Streaming Camera:</span>
                      <span className="text-neutral-200">{data.edge_status.streaming_camera || 'None'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-neutral-500">YouTube Configured:</span>
                      <span className={data.edge_status.youtube_configured ? 'text-status-success' : 'text-neutral-500'}>
                        {data.edge_status.youtube_configured ? 'Yes' : 'No'}
                      </span>
                    </div>
                    {data.edge_status.streaming_error && (
                      <div className="pt-ds-2 border-t border-neutral-700">
                        <span className="text-status-error">Error: </span>
                        <span className="text-status-error/80">{data.edge_status.streaming_error}</span>
                      </div>
                    )}
                    {data.edge_status.cameras.length > 0 && (
                      <div className="pt-ds-2 border-t border-neutral-700">
                        <div className="text-neutral-500 mb-ds-1">Cameras:</div>
                        <div className="grid grid-cols-2 gap-ds-1">
                          {data.edge_status.cameras.map((cam) => (
                            <div key={cam.name} className="flex justify-between">
                              <span className="text-neutral-200">{cam.name}</span>
                              <span className={
                                cam.status === 'available' ? 'text-status-success' :
                                cam.status === 'active' ? 'text-status-error' :
                                'text-neutral-500'
                              }>
                                {cam.status}
                              </span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                ) : (
                  <div className="bg-neutral-800 rounded-ds-md p-ds-4 text-neutral-500 text-center">
                    No edge status data available
                  </div>
                )}
              </section>

              {/* Stream State Machine */}
              <section>
                <h3 className="text-ds-body-sm font-semibold text-neutral-400 uppercase tracking-wider mb-ds-3">
                  Stream State Machine
                </h3>
                {data.stream_state ? (
                  <div className="bg-neutral-800 rounded-ds-md p-ds-4 space-y-ds-2 font-mono text-ds-body-sm">
                    <div className="flex justify-between">
                      <span className="text-neutral-500">State:</span>
                      <span className={`font-bold ${
                        data.stream_state.state === 'STREAMING' ? 'text-status-error' :
                        data.stream_state.state === 'STARTING' || data.stream_state.state === 'STOPPING' ? 'text-status-warning' :
                        data.stream_state.state === 'ERROR' ? 'text-status-warning' :
                        data.stream_state.state === 'IDLE' ? 'text-status-success' :
                        'text-neutral-400'
                      }`}>
                        {data.stream_state.state}
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-neutral-500">Source ID:</span>
                      <span className="text-neutral-200">{data.stream_state.source_id || 'None'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-neutral-500">Command ID:</span>
                      <span className="text-ds-caption text-neutral-200">{data.stream_state.command_id || 'None'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-neutral-500">Updated:</span>
                      <span className="text-ds-caption text-neutral-200">{formatTime(data.stream_state.updated_at)}</span>
                    </div>
                    {data.stream_state.error_message && (
                      <div className="pt-ds-2 border-t border-neutral-700">
                        <span className="text-status-warning">Error: </span>
                        <span className="text-status-warning/80">{data.stream_state.error_message}</span>
                      </div>
                    )}
                  </div>
                ) : (
                  <div className="bg-neutral-800 rounded-ds-md p-ds-4 text-neutral-500 text-center">
                    No stream state data available
                  </div>
                )}
              </section>

              {/* Raw Data Toggle */}
              <section>
                <button
                  onClick={() => setShowRaw(!showRaw)}
                  className="text-ds-body-sm text-neutral-500 hover:text-neutral-400 flex items-center gap-ds-1 transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500 rounded-ds-sm"
                >
                  <svg
                    className={`w-4 h-4 transition-transform duration-ds-fast ${showRaw ? 'rotate-90' : ''}`}
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                  </svg>
                  {showRaw ? 'Hide' : 'Show'} Raw Data
                </button>
                {showRaw && data.raw_redis && (
                  <pre className="mt-ds-2 bg-neutral-800 rounded-ds-md p-ds-4 text-ds-caption text-neutral-300 overflow-x-auto">
                    {JSON.stringify(data.raw_redis, null, 2)}
                  </pre>
                )}
              </section>
            </>
          )}
        </div>

        {/* Footer */}
        <div className="px-ds-6 py-ds-4 border-t border-neutral-800 flex justify-end gap-ds-3 flex-shrink-0">
          <button
            onClick={() => {
              if (data?.raw_redis) {
                navigator.clipboard.writeText(JSON.stringify(data.raw_redis, null, 2))
              }
            }}
            className="px-ds-4 py-ds-2 bg-neutral-700 hover:bg-neutral-600 text-neutral-300 rounded-ds-md font-medium transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500"
          >
            Copy Raw Data
          </button>
          <button
            onClick={onClose}
            className="px-ds-4 py-ds-2 bg-accent-600 hover:bg-accent-700 text-white rounded-ds-md font-medium transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  )
}
