/**
 * StreamControlPanel - Unified stream control UI with actionable errors
 *
 * UI-21: Migrated to design system tokens (neutral-*, status-*, accent-*, ds-*)
 * Provides a compact, non-technical-user-friendly interface for:
 * - Edge connection status (Connected/Disconnected + last seen time)
 * - Stream state (Idle/Starting/Streaming/Stopping/Error)
 * - Active camera/source label
 * - Start/Stop buttons with disabled states
 * - Actionable error messages with retry guidance
 *
 * Design principles:
 * - Never show technical jargon to users
 * - Always provide next action when something fails
 * - Show exact times, not vague "a while ago"
 */

import { useState, useCallback } from 'react'

// Stream states that match backend state machine
export type StreamState = 'DISCONNECTED' | 'IDLE' | 'STARTING' | 'STREAMING' | 'STOPPING' | 'ERROR'

// CAM-CONTRACT-1B: Canonical 4-camera slots with user-friendly labels
const CAMERA_LABELS: Record<string, string> = {
  main: 'Main Cam',
  cockpit: 'Cockpit',
  chase: 'Chase Cam',
  suspension: 'Suspension',
}

export interface EdgeStatusInfo {
  isOnline: boolean
  lastHeartbeatAgoS: number | null
  streamingStatus: string
  streamingCamera: string | null
  streamingError: string | null
  youtubeConfigured: boolean
  cameras: { name: string; status: string }[]
}

interface StreamControlPanelProps {
  /** Edge device status info */
  edge: EdgeStatusInfo
  /** Current stream state from state machine */
  streamState: StreamState
  /** Error message from state machine */
  errorMessage?: string | null
  /** Selected camera (before streaming starts) */
  selectedCamera: string | null
  /** Callback when camera is selected */
  onCameraSelect: (camera: string) => void
  /** Callback to start stream */
  onStartStream: (camera: string) => Promise<void>
  /** Callback to stop stream */
  onStopStream: () => Promise<void>
  /** Callback to run diagnostics */
  onDiagnostics?: () => void
  /** Whether a command is pending */
  isPending?: boolean
  /** Which command is pending */
  pendingCommand?: 'start' | 'stop' | null
}

/**
 * Get actionable error message for users
 */
function getActionableError(
  edge: EdgeStatusInfo,
  streamState: StreamState,
  errorMessage?: string | null,
  selectedCamera?: string | null
): { message: string; action: string; canRetry: boolean } | null {
  // Edge not connected
  if (!edge.isOnline) {
    const lastSeen = edge.lastHeartbeatAgoS !== null
      ? formatLastSeen(edge.lastHeartbeatAgoS)
      : 'never'
    return {
      message: `Edge device not connected. Last seen: ${lastSeen}.`,
      action: 'Check truck power and network connection, then wait for reconnect.',
      canRetry: false,
    }
  }

  // YouTube not configured
  if (!edge.youtubeConfigured) {
    return {
      message: 'YouTube stream key not configured.',
      action: 'Set up YouTube stream key on the edge device or contact support.',
      canRetry: false,
    }
  }

  // No camera selected
  if (streamState === 'IDLE' && !selectedCamera) {
    return {
      message: 'No camera selected.',
      action: 'Pick a camera above to start streaming.',
      canRetry: false,
    }
  }

  // Error state with message
  if (streamState === 'ERROR' && errorMessage) {
    // Parse common errors into user-friendly messages
    if (errorMessage.toLowerCase().includes('timeout')) {
      return {
        message: 'Edge device did not respond in time.',
        action: 'Check truck network connection and try again.',
        canRetry: true,
      }
    }
    if (errorMessage.toLowerCase().includes('ffmpeg') || errorMessage.toLowerCase().includes('encoder')) {
      return {
        message: 'Video encoder failed to start.',
        action: 'Edge device may need restart. Try again or contact support.',
        canRetry: true,
      }
    }
    if (errorMessage.toLowerCase().includes('camera') || errorMessage.toLowerCase().includes('video device')) {
      return {
        message: 'Camera not available.',
        action: 'Check camera connection on truck, then select a different camera.',
        canRetry: true,
      }
    }
    if (errorMessage.toLowerCase().includes('youtube') || errorMessage.toLowerCase().includes('rtmp')) {
      return {
        message: 'YouTube stream connection failed.',
        action: 'Check YouTube stream key and internet connection.',
        canRetry: true,
      }
    }
    // Generic error
    return {
      message: errorMessage,
      action: 'Try again or contact support if the problem persists.',
      canRetry: true,
    }
  }

  // No camera available
  if (edge.cameras.length === 0) {
    return {
      message: 'No cameras detected on edge device.',
      action: 'Check camera connections on the truck.',
      canRetry: false,
    }
  }

  // All cameras unavailable
  const availableCameras = edge.cameras.filter(c => c.status === 'available' || c.status === 'active')
  if (availableCameras.length === 0) {
    return {
      message: 'All cameras are currently unavailable.',
      action: 'Wait for cameras to become available or check connections.',
      canRetry: false,
    }
  }

  return null
}

/**
 * Format last seen time in a user-friendly way
 */
function formatLastSeen(seconds: number): string {
  if (seconds < 5) return 'just now'
  if (seconds < 60) return `${seconds}s ago`
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s ago`
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m ago`
}

/**
 * Get status indicator color
 */
function getStatusColor(streamState: StreamState, isOnline: boolean): string {
  if (!isOnline) return 'bg-status-error'
  switch (streamState) {
    case 'STREAMING':
      return 'bg-status-error animate-pulse'
    case 'STARTING':
    case 'STOPPING':
      return 'bg-status-warning animate-pulse'
    case 'ERROR':
      return 'bg-status-warning'
    case 'IDLE':
      return 'bg-status-success'
    default:
      return 'bg-neutral-500'
  }
}

/**
 * Get status label for display
 */
function getStatusLabel(streamState: StreamState, isOnline: boolean, camera?: string | null): string {
  if (!isOnline) return 'Disconnected'
  switch (streamState) {
    case 'STREAMING':
      return camera ? `Live: ${CAMERA_LABELS[camera] || camera}` : 'Live'
    case 'STARTING':
      return 'Starting stream...'
    case 'STOPPING':
      return 'Stopping stream...'
    case 'ERROR':
      return 'Error'
    case 'IDLE':
      return 'Ready'
    default:
      return 'Unknown'
  }
}

export default function StreamControlPanel({
  edge,
  streamState,
  errorMessage,
  selectedCamera,
  onCameraSelect,
  onStartStream,
  onStopStream,
  onDiagnostics,
  isPending = false,
  pendingCommand = null,
}: StreamControlPanelProps) {
  const [localError, setLocalError] = useState<string | null>(null)

  // Compute actionable error
  const error = getActionableError(edge, streamState, errorMessage || localError, selectedCamera)

  // Can start stream?
  const canStart = edge.isOnline &&
    edge.youtubeConfigured &&
    selectedCamera !== null &&
    streamState === 'IDLE' &&
    !isPending

  // Can stop stream?
  const canStop = (streamState === 'STREAMING' || streamState === 'STARTING') && !isPending

  // Handle start
  const handleStart = useCallback(async () => {
    if (!selectedCamera) {
      setLocalError('Please select a camera first')
      return
    }
    setLocalError(null)
    try {
      await onStartStream(selectedCamera)
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : 'Failed to start stream')
    }
  }, [selectedCamera, onStartStream])

  // Handle stop
  const handleStop = useCallback(async () => {
    setLocalError(null)
    try {
      await onStopStream()
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : 'Failed to stop stream')
    }
  }, [onStopStream])

  return (
    <div className="ds-stack">
      {/* Compact Status Bar */}
      <div className="bg-neutral-800 rounded-ds-lg p-ds-3">
        <div className="flex items-center justify-between">
          {/* Edge Status */}
          <div className="flex items-center gap-ds-3">
            <div className="flex items-center gap-ds-2">
              <span className={`w-2.5 h-2.5 rounded-full ${edge.isOnline ? 'bg-status-success' : 'bg-status-error'}`} />
              <span className="text-ds-body-sm font-medium text-neutral-100">
                {edge.isOnline ? 'Edge Connected' : 'Edge Disconnected'}
              </span>
            </div>
            {edge.lastHeartbeatAgoS !== null && (
              <span className="text-ds-caption text-neutral-500">
                ({formatLastSeen(edge.lastHeartbeatAgoS)})
              </span>
            )}
          </div>

          {/* Stream Status */}
          <div className="flex items-center gap-ds-2">
            <span className={`w-2 h-2 rounded-full ${getStatusColor(streamState, edge.isOnline)}`} />
            <span className="text-ds-body-sm font-medium text-neutral-100">
              {getStatusLabel(streamState, edge.isOnline, edge.streamingCamera)}
            </span>
          </div>
        </div>
      </div>

      {/* Error/Action Alert */}
      {error && (
        <div
          className={`rounded-ds-lg p-ds-4 ${
            error.canRetry
              ? 'bg-status-warning/15 border border-status-warning/30'
              : 'bg-status-error/15 border border-status-error/30'
          }`}
          role="alert"
        >
          <div className="flex items-start gap-ds-3">
            <div className={`mt-0.5 ${error.canRetry ? 'text-status-warning' : 'text-status-error'}`}>
              <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
              </svg>
            </div>
            <div className="flex-1">
              <div className={`font-medium text-ds-body-sm ${error.canRetry ? 'text-status-warning' : 'text-status-error'}`}>
                {error.message}
              </div>
              <div className="text-ds-body-sm text-neutral-400 mt-ds-1">
                {error.action}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Camera Selection */}
      {edge.isOnline && (
        <div>
          <div className="text-ds-caption text-neutral-500 mb-ds-2 font-medium uppercase tracking-wide">
            Select Camera
          </div>
          <div className="grid grid-cols-2 gap-ds-2">
            {/* CAM-CONTRACT-1B: Canonical 4-camera slots */}
            {['main', 'cockpit', 'chase', 'suspension'].map((cam) => {
              const camInfo = edge.cameras.find(c => c.name === cam)
              const isAvailable = camInfo?.status === 'available' || camInfo?.status === 'active'
              const isSelected = selectedCamera === cam
              const isStreaming = edge.streamingCamera === cam && streamState === 'STREAMING'
              const isDisabled = !isAvailable || isPending

              return (
                <button
                  key={cam}
                  onClick={() => onCameraSelect(cam)}
                  disabled={isDisabled}
                  className={`min-h-[44px] px-ds-3 py-ds-2 rounded-ds-lg text-ds-body-sm font-medium transition-all duration-ds-fast flex items-center gap-ds-2 ${
                    isStreaming
                      ? 'bg-status-error text-white ring-2 ring-status-error/60'
                      : isSelected
                      ? 'bg-accent-600 text-white ring-2 ring-accent-400'
                      : isAvailable
                      ? 'bg-neutral-700 hover:bg-neutral-600 text-neutral-200'
                      : 'bg-neutral-800 text-neutral-500 cursor-not-allowed'
                  }`}
                  aria-pressed={isSelected || isStreaming}
                >
                  {isStreaming && <span className="w-2 h-2 bg-white rounded-full animate-pulse" />}
                  {isSelected && !isStreaming && <span className="w-2 h-2 bg-accent-300 rounded-full" />}
                  <span>{CAMERA_LABELS[cam] || cam}</span>
                  {!isAvailable && !camInfo && <span className="text-ds-caption opacity-60">(N/A)</span>}
                </button>
              )
            })}
          </div>
        </div>
      )}

      {/* Stream Control Buttons */}
      <div className="flex gap-ds-3">
        {streamState === 'STREAMING' || streamState === 'STARTING' || streamState === 'STOPPING' ? (
          <button
            onClick={handleStop}
            disabled={!canStop}
            className={`flex-1 min-h-[44px] px-ds-4 py-ds-3 rounded-ds-lg font-medium transition-all duration-ds-fast flex items-center justify-center gap-ds-2 ${
              canStop
                ? 'bg-status-error hover:bg-status-error/90 text-white'
                : 'bg-neutral-700 text-neutral-500 cursor-not-allowed'
            }`}
          >
            {pendingCommand === 'stop' ? (
              <>
                <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                <span>Stopping...</span>
              </>
            ) : streamState === 'STOPPING' ? (
              <>
                <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                <span>Stopping...</span>
              </>
            ) : (
              <>
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <rect x="6" y="6" width="12" height="12" rx="2" />
                </svg>
                <span>Stop Stream</span>
              </>
            )}
          </button>
        ) : (
          <button
            onClick={handleStart}
            disabled={!canStart}
            className={`flex-1 min-h-[44px] px-ds-4 py-ds-3 rounded-ds-lg font-medium transition-all duration-ds-fast flex items-center justify-center gap-ds-2 ${
              canStart
                ? 'bg-status-success hover:bg-status-success/90 text-white'
                : 'bg-neutral-700 text-neutral-500 cursor-not-allowed'
            }`}
          >
            {pendingCommand === 'start' ? (
              <>
                <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                <span>Starting...</span>
              </>
            ) : (
              <>
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M8 5v14l11-7z" />
                </svg>
                <span>Start Stream</span>
              </>
            )}
          </button>
        )}

        {/* Diagnostics Button */}
        {onDiagnostics && (
          <button
            onClick={onDiagnostics}
            className="min-h-[44px] px-ds-4 py-ds-3 bg-neutral-700 hover:bg-neutral-600 text-neutral-300 rounded-ds-lg font-medium transition-colors duration-ds-fast flex items-center gap-ds-2 focus:outline-none focus:ring-2 focus:ring-accent-500 focus:ring-offset-2 focus:ring-offset-neutral-900"
            title="View system diagnostics"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            <span className="sr-only sm:not-sr-only">Diagnostics</span>
          </button>
        )}
      </div>

      {/* Help text when ready */}
      {streamState === 'IDLE' && selectedCamera && edge.isOnline && edge.youtubeConfigured && (
        <div className="text-ds-body-sm text-neutral-400 text-center">
          Ready to stream with {CAMERA_LABELS[selectedCamera] || selectedCamera}
        </div>
      )}
    </div>
  )
}
