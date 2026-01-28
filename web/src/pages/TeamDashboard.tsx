/**
 * Team Dashboard - Gateway to Pit Crew + Fan Preview
 *
 * TEAM-1: Acts as a gateway that redirects teams to their Edge Pit Crew portal
 * for full control. Retains cloud-only features (visibility, sharing, fan preview).
 *
 * Behavior:
 * - If edge URL is saved, auto-redirects to Pit Crew with 5s cancel window.
 * - If no edge URL, shows a form to set it.
 * - "Preview Fan View" always available when event is active + vehicle visible.
 * - Cloud-only controls (visibility, sharing policy) accessible via "Stay Here".
 */
import { useState, useEffect, useCallback, useRef } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import VideoFeedManager from '../components/Team/VideoFeedManager'
// TEAM-3: TelemetrySharingPolicy moved to Pit Crew edge dashboard
import { PageHeader } from '../components/common'
import { Badge, EmptyState, Alert } from '../components/ui'
import { copyToClipboard } from '../utils/clipboard'

// TEAM-1: localStorage key for edge device URL
const EDGE_URL_STORAGE_KEY = 'argus_edge_url'

/**
 * Validate edge URL to prevent open-redirect attacks.
 * Only allows http/https URLs pointing to LAN IPs, hostnames, or localhost.
 */
function isValidEdgeUrl(url: string): boolean {
  try {
    const parsed = new URL(url)
    // Must be http or https
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return false
    const host = parsed.hostname
    // Allow localhost
    if (host === 'localhost' || host === '127.0.0.1') return true
    // Allow private IPv4 ranges: 10.x, 172.16-31.x, 192.168.x
    if (/^10\./.test(host)) return true
    if (/^172\.(1[6-9]|2\d|3[01])\./.test(host)) return true
    if (/^192\.168\./.test(host)) return true
    // Allow .local mDNS hostnames
    if (host.endsWith('.local')) return true
    // Allow short hostnames (no dots = LAN hostname)
    if (!host.includes('.')) return true
    // Allow any hostname with port (common for edge devices)
    if (parsed.port) return true
    return false
  } catch {
    return false
  }
}

type TabId = 'ops' | 'sharing'

interface Permission {
  field_name: string
  permission_level: string
  updated_at: string | null
}

interface VideoFeed {
  camera_name: string
  youtube_url: string
  permission_level: string
}

interface DashboardData {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  event_id: string | null
  telemetry_permissions: Permission[]
  video_feeds: VideoFeed[]
  visible: boolean
}

// Diagnostics data from GET /api/v1/team/diagnostics
interface DiagnosticsData {
  vehicle_id: string
  event_id: string | null
  visible: boolean
  edge_last_seen_ms: number | null
  edge_status: 'online' | 'stale' | 'offline' | 'unknown'
  is_online: boolean
  gps_status: 'locked' | 'searching' | 'no_signal' | 'unknown'
  can_status: 'active' | 'idle' | 'error' | 'unknown'
  video_status: 'streaming' | 'configured' | 'none' | 'unknown'
  queue_depth: number | null
  last_position_ms: number | null
  data_rate_hz: number | null
  edge_ip: string | null
  edge_version: string | null
}

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

export default function TeamDashboard() {
  const navigate = useNavigate()
  const [activeTab, setActiveTab] = useState<TabId>('ops')
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [data, setData] = useState<DashboardData | null>(null)
  const [isSaving, setIsSaving] = useState(false)
  const [diagnostics, setDiagnostics] = useState<DiagnosticsData | null>(null)
  const [copySuccess, setCopySuccess] = useState(false)

  // TEAM-1: Gateway redirect state
  const [edgeUrl, setEdgeUrl] = useState<string>(
    () => localStorage.getItem(EDGE_URL_STORAGE_KEY) || ''
  )
  const [edgeUrlInput, setEdgeUrlInput] = useState('')
  const [edgeUrlError, setEdgeUrlError] = useState<string | null>(null)
  const [redirectCountdown, setRedirectCountdown] = useState<number | null>(null)
  const [redirectCancelled, setRedirectCancelled] = useState(false)
  const countdownRef = useRef<ReturnType<typeof setInterval> | null>(null)

  // Get token from localStorage
  const token = localStorage.getItem('team_token')

  useEffect(() => {
    if (!token) {
      navigate('/team/login')
      return
    }
    fetchDashboard()
  }, [token])

  // TEAM-1: Auto-redirect to edge when URL is set and not cancelled
  useEffect(() => {
    if (!edgeUrl || redirectCancelled || isLoading || !data) return

    // Start 5-second countdown
    setRedirectCountdown(5)
    countdownRef.current = setInterval(() => {
      setRedirectCountdown((prev) => {
        if (prev === null || prev <= 1) {
          // Redirect now
          if (countdownRef.current) clearInterval(countdownRef.current)
          window.location.href = edgeUrl
          return 0
        }
        return prev - 1
      })
    }, 1000)

    return () => {
      if (countdownRef.current) clearInterval(countdownRef.current)
    }
  }, [edgeUrl, redirectCancelled, isLoading, data])

  // TEAM-1: Cancel redirect and stay on cloud dashboard
  function handleCancelRedirect() {
    if (countdownRef.current) clearInterval(countdownRef.current)
    setRedirectCountdown(null)
    setRedirectCancelled(true)
  }

  // TEAM-1: Save edge URL to localStorage
  function handleSaveEdgeUrl() {
    const trimmed = edgeUrlInput.trim()
    if (!trimmed) {
      setEdgeUrlError('URL is required')
      return
    }
    // Add protocol if missing
    const urlWithProtocol = /^https?:\/\//i.test(trimmed) ? trimmed : `http://${trimmed}`
    if (!isValidEdgeUrl(urlWithProtocol)) {
      setEdgeUrlError('Must be a local/LAN address (e.g. http://192.168.1.100:8080)')
      return
    }
    localStorage.setItem(EDGE_URL_STORAGE_KEY, urlWithProtocol)
    setEdgeUrl(urlWithProtocol)
    setEdgeUrlError(null)
    setRedirectCancelled(false)
  }

  // TEAM-1: Clear saved edge URL
  function handleClearEdgeUrl() {
    localStorage.removeItem(EDGE_URL_STORAGE_KEY)
    setEdgeUrl('')
    setEdgeUrlInput('')
    setRedirectCancelled(false)
    setRedirectCountdown(null)
  }

  // Poll diagnostics every 5 seconds when on Ops tab (only after data loads)
  useEffect(() => {
    if (!token || !data) return

    // Fetch immediately when data becomes available or tab switches to ops
    if (activeTab === 'ops') {
      fetchDiagnostics()
    }

    const interval = setInterval(() => {
      if (activeTab === 'ops') {
        fetchDiagnostics()
      }
    }, 5000)

    return () => clearInterval(interval)
  }, [token, activeTab, data?.event_id])

  async function fetchDashboard() {
    try {
      const response = await fetch(`${API_BASE}/team/dashboard`, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      })

      if (response.status === 401) {
        localStorage.removeItem('team_token')
        navigate('/team/login')
        return
      }

      if (response.status === 403) {
        setError('Access denied. Your session may have expired.')
        return
      }

      if (!response.ok) {
        throw new Error('Failed to load dashboard')
      }

      const dashData = await response.json()
      setData(dashData)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setIsLoading(false)
    }
  }

  async function fetchDiagnostics() {
    if (!token) return

    try {
      const response = await fetch(`${API_BASE}/team/diagnostics`, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      })

      if (response.ok) {
        const diagData = await response.json()
        setDiagnostics(diagData)
      } else if (response.status === 401) {
        localStorage.removeItem('team_token')
        navigate('/team/login')
      }
    } catch (err) {
      console.warn('Failed to fetch diagnostics:', err)
    }
  }

  async function updateVisibility(visible: boolean) {
    if (!token) return

    setIsSaving(true)
    try {
      const response = await fetch(`${API_BASE}/team/visibility?visible=${visible}`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
        },
      })

      if (!response.ok) {
        // Extract error detail from backend response
        let errorMessage = 'Failed to update visibility'
        try {
          const errorData = await response.json()
          if (errorData.detail) {
            errorMessage = errorData.detail
          }
        } catch {
          // Response wasn't JSON, use status text
          errorMessage = response.statusText || errorMessage
        }
        throw new Error(errorMessage)
      }

      setData((prev) => prev ? { ...prev, visible } : null)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save')
    } finally {
      setIsSaving(false)
    }
  }

  async function updateVideoFeed(camera_name: string, youtube_url: string, permission_level: string) {
    if (!token) return

    setIsSaving(true)
    try {
      const response = await fetch(`${API_BASE}/team/video`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ camera_name, youtube_url, permission_level }),
      })

      if (!response.ok) {
        throw new Error('Failed to update video feed')
      }

      await fetchDashboard()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save')
    } finally {
      setIsSaving(false)
    }
  }

  const handleCopyDiagnostics = useCallback(() => {
    if (!diagnostics || !data) return

    const diagText = `
=== ARGUS TRUCK DIAGNOSTICS ===
Timestamp: ${new Date().toISOString()}
Vehicle: #${data.vehicle_number} - ${data.team_name}
Vehicle ID: ${data.vehicle_id}
Event ID: ${data.event_id || 'Not registered'}

EDGE STATUS
-----------
Status: ${diagnostics.edge_status}
Online: ${diagnostics.is_online ? 'Yes' : 'No'}
Last Seen: ${diagnostics.edge_last_seen_ms ? `${Math.round((Date.now() - diagnostics.edge_last_seen_ms) / 1000)}s ago` : 'Never'}
Edge IP: ${diagnostics.edge_ip || 'Unknown'}
Edge Version: ${diagnostics.edge_version || 'Unknown'}
Data Rate: ${diagnostics.data_rate_hz ? `${diagnostics.data_rate_hz} Hz` : 'Unknown'}
Queue Depth: ${diagnostics.queue_depth ?? 'Unknown'}

SENSORS
-------
GPS: ${diagnostics.gps_status}
CAN Bus: ${diagnostics.can_status}
Last Position: ${diagnostics.last_position_ms ? `${Math.round((Date.now() - diagnostics.last_position_ms) / 1000)}s ago` : 'Never'}

VIDEO
-----
Status: ${diagnostics.video_status}
Feeds: ${data.video_feeds.filter(f => f.youtube_url).map(f => f.camera_name).join(', ') || 'None'}

VISIBILITY
----------
Visible to Fans: ${data.visible ? 'Yes' : 'No'}
`.trim()

    copyToClipboard(diagText).then((success) => {
      if (success) {
        setCopySuccess(true)
        setTimeout(() => setCopySuccess(false), 2000)
      }
    })
  }, [diagnostics, data])

  function handleLogout() {
    localStorage.removeItem('team_token')
    navigate('/team/login')
  }

  // Calculate staleness
  const edgeAge = diagnostics?.edge_last_seen_ms
    ? Math.round((Date.now() - diagnostics.edge_last_seen_ms) / 1000)
    : null

  const isStale = edgeAge !== null && edgeAge > 30
  const isOffline = edgeAge !== null && edgeAge > 60

  if (isLoading) {
    return (
      <div className="min-h-screen bg-neutral-950 flex flex-col">
        {/* Header Skeleton */}
        <header className="bg-neutral-900 border-b border-neutral-800 px-ds-4 py-ds-3">
          <div className="flex items-center justify-between">
            <div className="skeleton bg-neutral-800 rounded-ds-md w-12 h-12" />
            <div className="flex-1 flex flex-col items-center gap-ds-1">
              <div className="skeleton bg-neutral-800 rounded-ds-sm h-5 w-24" />
              <div className="skeleton bg-neutral-800 rounded-ds-sm h-4 w-32" />
            </div>
            <div className="w-12" />
          </div>
        </header>

        {/* Tab Skeleton */}
        <div className="flex border-b border-neutral-800 bg-neutral-900">
          <div className="flex-1 min-h-[48px] flex items-center justify-center">
            <div className="skeleton bg-neutral-800 rounded-ds-sm h-4 w-12" />
          </div>
          <div className="flex-1 min-h-[48px] flex items-center justify-center">
            <div className="skeleton bg-neutral-800 rounded-ds-sm h-4 w-16" />
          </div>
        </div>

        {/* Content Skeleton */}
        <div className="flex-1 p-ds-4 space-y-ds-4">
          <div className="skeleton bg-neutral-800 rounded-ds-lg h-20 w-full" />
          <div className="grid grid-cols-2 gap-ds-3">
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className="skeleton bg-neutral-800 rounded-ds-lg h-24" />
            ))}
          </div>
          <div className="skeleton bg-neutral-800 rounded-ds-lg h-40 w-full" />
        </div>

        {/* Loading indicator */}
        <div className="fixed inset-0 flex items-center justify-center pointer-events-none">
          <div className="bg-neutral-900/90 rounded-ds-lg p-ds-4 flex flex-col items-center gap-ds-3">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-accent-500" />
            <p className="text-neutral-400 text-ds-body-sm">Loading dashboard...</p>
          </div>
        </div>
      </div>
    )
  }

  if (error) {
    const isAuthError = error.includes('401') || error.includes('403') || error.includes('denied')
    return (
      <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-ds-4">
        <EmptyState
          icon={
            <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
          }
          title={error}
          description={isAuthError
            ? 'Your session has expired. Please log in again.'
            : 'Please try again or contact support if the problem persists.'}
          action={{
            label: isAuthError ? 'Login' : 'Retry',
            onClick: isAuthError ? handleLogout : fetchDashboard,
            variant: 'primary',
          }}
        />
      </div>
    )
  }

  if (!data) {
    return null
  }

  return (
    <div className="h-full flex flex-col bg-neutral-950 viewport-fixed">
      {/* Page Header with Back + Home + Logout */}
      <PageHeader
        title="Team Dashboard"
        subtitle="Manage your truck"
        backTo="/team/login"
        backLabel="Back to login"
        rightSlot={
          <button
            onClick={handleLogout}
            className="min-h-[40px] px-ds-3 py-ds-2 text-ds-body-sm text-neutral-400 hover:text-neutral-200 transition-colors duration-ds-fast rounded-full hover:bg-neutral-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-accent-400"
          >
            Logout
          </button>
        }
      />

      {/* TEAM-1: Gateway redirect banner */}
      {redirectCountdown !== null && redirectCountdown > 0 && (
        <div className="px-ds-4 py-ds-3 bg-accent-900/80 border-b border-accent-700 flex items-center justify-between">
          <div className="flex items-center gap-ds-3">
            <span className="w-8 h-8 rounded-full bg-accent-600 flex items-center justify-center font-mono font-bold text-white text-ds-body">
              {redirectCountdown}
            </span>
            <div>
              <p className="text-ds-body-sm text-accent-200">Redirecting to Pit Crew Portal...</p>
              <p className="text-ds-caption text-accent-400 font-mono truncate max-w-[200px]">{edgeUrl}</p>
            </div>
          </div>
          <button
            onClick={handleCancelRedirect}
            className="min-h-[40px] px-ds-4 py-ds-2 bg-neutral-800 hover:bg-neutral-700 text-neutral-200 rounded-ds-md text-ds-body-sm font-medium transition-colors duration-ds-fast"
          >
            Stay Here
          </button>
        </div>
      )}

      {/* TEAM-1: Edge URL setup (when no edge URL saved and redirect not active) */}
      {!edgeUrl && !isLoading && data && (
        <div className="px-ds-4 py-ds-4 bg-neutral-900 border-b border-neutral-800">
          <h3 className="text-ds-body-sm font-medium text-neutral-200 mb-ds-2">Connect to Pit Crew Portal</h3>
          <p className="text-ds-caption text-neutral-500 mb-ds-3">
            Enter your edge device URL to access full truck controls (streaming, cameras, telemetry).
          </p>
          <div className="flex gap-ds-2">
            <input
              type="text"
              value={edgeUrlInput}
              onChange={(e) => { setEdgeUrlInput(e.target.value); setEdgeUrlError(null) }}
              onKeyDown={(e) => e.key === 'Enter' && handleSaveEdgeUrl()}
              placeholder="e.g. 192.168.1.100:8080"
              className="flex-1 min-h-[40px] px-ds-3 bg-neutral-800 border border-neutral-700 rounded-ds-md text-neutral-200 text-ds-body-sm placeholder:text-neutral-600 focus:outline-none focus:border-accent-500"
            />
            <button
              onClick={handleSaveEdgeUrl}
              className="min-h-[40px] px-ds-4 bg-accent-600 hover:bg-accent-500 text-white rounded-ds-md text-ds-body-sm font-medium transition-colors duration-ds-fast"
            >
              Save
            </button>
          </div>
          {edgeUrlError && (
            <p className="text-ds-caption text-status-error mt-ds-1">{edgeUrlError}</p>
          )}
          {diagnostics?.edge_ip && (
            <button
              onClick={() => { setEdgeUrlInput(`${diagnostics.edge_ip}:8080`); setEdgeUrlError(null) }}
              className="mt-ds-2 text-ds-caption text-accent-400 hover:text-accent-300 transition-colors"
            >
              Use detected edge IP: {diagnostics.edge_ip}:8080
            </button>
          )}
        </div>
      )}

      {/* TEAM-1: Quick actions bar (when redirect cancelled or edge URL set) */}
      {edgeUrl && redirectCancelled && (
        <div className="px-ds-4 py-ds-2 bg-neutral-900/50 border-b border-neutral-800/50 flex items-center justify-between">
          <div className="flex items-center gap-ds-2">
            <a
              href={edgeUrl}
              className="min-h-[36px] px-ds-3 py-ds-1 bg-accent-600 hover:bg-accent-500 text-white rounded-ds-md text-ds-body-sm font-medium transition-colors duration-ds-fast flex items-center gap-ds-2"
            >
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
              </svg>
              Open Pit Crew
            </a>
            <button
              onClick={handleClearEdgeUrl}
              className="min-h-[36px] px-ds-3 py-ds-1 text-neutral-500 hover:text-neutral-300 text-ds-caption transition-colors"
            >
              Change URL
            </button>
          </div>
          <span className="text-ds-caption text-neutral-600 font-mono truncate max-w-[150px]">{edgeUrl}</span>
        </div>
      )}

      {/* Event Context Bar */}
      <div className="px-ds-4 py-ds-2 bg-neutral-950/50 border-b border-neutral-800/50">
        {data.event_id ? (
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-ds-2">
              <span className={`w-2 h-2 rounded-full ${isOffline ? 'bg-status-error' : isStale ? 'bg-status-warning animate-pulse' : 'bg-status-success animate-pulse'}`} />
              <span className="text-ds-body-sm text-neutral-300">Active Event</span>
              <Badge variant={isOffline ? 'error' : isStale ? 'warning' : 'success'} size="sm">
                {isOffline ? 'OFFLINE' : isStale ? 'STALE' : 'LIVE'}
              </Badge>
            </div>
            <span className="text-ds-caption text-neutral-500 font-mono">{data.event_id}</span>
          </div>
        ) : (
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-ds-2">
              <span className="w-2 h-2 rounded-full bg-neutral-600" />
              <span className="text-ds-body-sm text-neutral-500">No Active Event</span>
            </div>
            <span className="text-ds-caption text-accent-400">Register to go live</span>
          </div>
        )}
      </div>

      {/* Saving indicator */}
      {isSaving && (
        <div className="bg-accent-900/50 text-accent-200 text-ds-caption text-center py-ds-1 px-ds-4">
          Saving changes...
        </div>
      )}

      {/* Tab Navigation */}
      <div className="flex border-b border-neutral-800 bg-neutral-900">
        <button
          onClick={() => setActiveTab('ops')}
          className={`flex-1 min-h-[48px] px-ds-4 py-ds-3 text-ds-body-sm font-medium transition-colors duration-ds-fast relative ${
            activeTab === 'ops'
              ? 'text-accent-400'
              : 'text-neutral-400 hover:text-neutral-300'
          }`}
        >
          <span className="flex items-center justify-center gap-ds-2">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
            </svg>
            Ops
            {diagnostics && (isStale || isOffline) && (
              <span className={`w-2 h-2 rounded-full ${isOffline ? 'bg-status-error' : 'bg-status-warning'} animate-pulse`} />
            )}
          </span>
          {activeTab === 'ops' && (
            <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-accent-500" />
          )}
        </button>
        <button
          onClick={() => setActiveTab('sharing')}
          className={`flex-1 min-h-[48px] px-ds-4 py-ds-3 text-ds-body-sm font-medium transition-colors duration-ds-fast relative ${
            activeTab === 'sharing'
              ? 'text-accent-400'
              : 'text-neutral-400 hover:text-neutral-300'
          }`}
        >
          <span className="flex items-center justify-center gap-ds-2">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" />
            </svg>
            Sharing
          </span>
          {activeTab === 'sharing' && (
            <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-accent-500" />
          )}
        </button>
      </div>

      {/* Tab Content */}
      <div className="flex-1 overflow-y-auto bg-neutral-950">
        {activeTab === 'ops' ? (
          <OpsTab
            data={data}
            diagnostics={diagnostics}
            edgeAge={edgeAge}
            isStale={isStale}
            isOffline={isOffline}
            onCopyDiagnostics={handleCopyDiagnostics}
            copySuccess={copySuccess}
            onToggleVisibility={() => updateVisibility(!data.visible)}
            token={token || ''}
            onFetchDiagnostics={fetchDiagnostics}
          />
        ) : (
          <SharingTab
            data={data}
            token={token || ''}
            onUpdateVisibility={updateVisibility}
            onUpdateVideoFeed={updateVideoFeed}
          />
        )}

        {/* Footer Actions — TEAM-1: Preview Fan View opens in new tab */}
        {data.event_id && data.visible && (
          <div className="p-ds-4 border-t border-neutral-800">
            <Link
              to={`/events/${data.event_id}/vehicles/${data.vehicle_id}`}
              target="_blank"
              rel="noopener noreferrer"
              className="w-full min-h-[48px] px-ds-4 py-ds-3 bg-accent-600 hover:bg-accent-500 rounded-ds-lg font-medium text-white transition-colors duration-ds-fast flex items-center justify-center gap-ds-2"
            >
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
              </svg>
              Preview Fan View
              <svg className="w-4 h-4 opacity-60" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
              </svg>
            </Link>
          </div>
        )}
      </div>
    </div>
  )
}

/**
 * Ops Tab - System status and diagnostics
 */
function OpsTab({
  data,
  diagnostics,
  edgeAge,
  isStale,
  isOffline,
  onCopyDiagnostics,
  copySuccess,
  token,
  onFetchDiagnostics,
}: {
  data: DashboardData
  diagnostics: DiagnosticsData | null
  edgeAge: number | null
  isStale: boolean
  isOffline: boolean
  onCopyDiagnostics: () => void
  copySuccess: boolean
  onToggleVisibility?: () => void
  token: string
  onFetchDiagnostics: () => void
}) {
  // Compute truck status
  const getTruckStatusBadge = (): { label: string; variant: 'success' | 'warning' | 'error' | 'neutral' } => {
    if (!data.event_id) return { label: 'Not Registered', variant: 'neutral' }
    if (isOffline) return { label: 'Offline', variant: 'error' }
    if (diagnostics?.video_status === 'streaming') return { label: 'Streaming', variant: 'success' }
    if (isStale) return { label: 'Stale Data', variant: 'warning' }
    if (diagnostics?.edge_status === 'online') return { label: 'Online', variant: 'success' }
    return { label: 'No Data', variant: 'warning' }
  }

  const truckStatus = getTruckStatusBadge()

  // Determine next action for the user
  const getNextAction = (): { message: string; action: string; actionLabel: string } | null => {
    if (!data.event_id) {
      return {
        message: 'Your truck is not registered for any event.',
        action: 'Contact race organizers to register for an upcoming event.',
        actionLabel: 'Registration Required',
      }
    }
    if (isOffline || diagnostics?.edge_status === 'offline' || diagnostics?.edge_status === 'unknown') {
      const lastSeenHint = diagnostics?.edge_last_seen_ms
        ? ` Last seen ${Math.round((Date.now() - diagnostics.edge_last_seen_ms) / 1000)}s ago.`
        : ''
      return {
        message: `Edge device is not connected.${lastSeenHint}`,
        action: 'Check: 1) Edge is powered on, 2) Cellular/WiFi connected, 3) Correct cloud URL in edge config, 4) Truck token matches.',
        actionLabel: 'Edge Offline',
      }
    }
    if (diagnostics?.video_status === 'none' || diagnostics?.video_status === 'configured') {
      return {
        message: 'Video stream is not active.',
        action: 'Configure YouTube URL in Sharing tab and start stream from edge device.',
        actionLabel: 'Start Streaming',
      }
    }
    return null
  }

  const nextAction = getNextAction()

  return (
    <div className="p-ds-4 space-y-ds-4">
      {/* My Truck Card */}
      <section>
        <h2 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wide mb-ds-3">My Truck</h2>
        <div className="bg-neutral-900 rounded-ds-lg p-ds-4">
          <div className="flex items-start justify-between">
            {/* Truck Info */}
            <div className="flex items-center gap-ds-4">
              <div className="w-16 h-16 rounded-ds-lg bg-accent-600/20 border-2 border-accent-500/50 flex items-center justify-center">
                <span className="text-ds-display font-bold text-accent-400">#{data.vehicle_number}</span>
              </div>
              <div>
                <h3 className="text-ds-heading font-semibold text-neutral-50">{data.team_name}</h3>
                <p className="text-ds-caption text-neutral-500 font-mono mt-ds-1">{data.vehicle_id}</p>
              </div>
            </div>

            {/* Status Badges */}
            <div className="flex flex-col items-end gap-ds-2">
              <Badge variant={truckStatus.variant} size="sm" dot={truckStatus.variant !== 'neutral'} pulse={truckStatus.variant === 'success'}>
                {truckStatus.label}
              </Badge>
              {data.visible ? (
                <Badge variant="success" size="sm">Visible</Badge>
              ) : (
                <Badge variant="neutral" size="sm">Hidden</Badge>
              )}
            </div>
          </div>

          {/* Quick Stats Row */}
          <div className="mt-ds-4 pt-ds-4 border-t border-neutral-800 grid grid-cols-3 gap-ds-4">
            <div className="text-center">
              <div className="text-ds-display font-mono font-bold text-neutral-50">
                {diagnostics?.data_rate_hz ?? '—'}
              </div>
              <div className="text-ds-caption text-neutral-500">Hz</div>
            </div>
            <div className="text-center">
              <div className="text-ds-display font-mono font-bold text-neutral-50">
                {edgeAge !== null ? (edgeAge < 60 ? `${edgeAge}s` : `${Math.floor(edgeAge / 60)}m`) : '—'}
              </div>
              <div className="text-ds-caption text-neutral-500">Last Seen</div>
            </div>
            <div className="text-center">
              <div className="text-ds-display font-mono font-bold text-neutral-50">
                {diagnostics?.queue_depth ?? '—'}
              </div>
              <div className="text-ds-caption text-neutral-500">Queue</div>
            </div>
          </div>
        </div>
      </section>

      {/* Next Action Prompt (if applicable) */}
      {nextAction && (
        <Alert variant="info">
          <strong className="block text-ds-body-sm">{nextAction.actionLabel}</strong>
          <span className="text-ds-caption opacity-80">{nextAction.message}</span>
          <span className="block text-ds-caption text-accent-400 mt-ds-1">{nextAction.action}</span>
        </Alert>
      )}

      {/* Streaming / Edge Status Section */}
      <section>
        <h2 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wide mb-ds-3">Streaming & Edge Status</h2>
        <div className="grid grid-cols-2 gap-ds-3">
          {/* GPS Status */}
          <StatusCard
            title="GPS"
            status={diagnostics?.gps_status || 'unknown'}
            icon={
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            }
            statusLabels={{
              locked: { label: 'Locked', color: 'green' },
              searching: { label: 'Searching', color: 'yellow' },
              no_signal: { label: 'No Signal', color: 'red' },
              unknown: { label: 'Unknown', color: 'gray' },
            }}
          />

          {/* CAN Bus Status */}
          <StatusCard
            title="CAN Bus"
            status={diagnostics?.can_status || 'unknown'}
            icon={
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            }
            statusLabels={{
              active: { label: 'Active', color: 'green' },
              idle: { label: 'Idle', color: 'yellow' },
              error: { label: 'Error', color: 'red' },
              unknown: { label: 'Unknown', color: 'gray' },
            }}
          />

          {/* Video Status */}
          <StatusCard
            title="Video"
            status={diagnostics?.video_status || 'unknown'}
            icon={
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
            }
            statusLabels={{
              streaming: { label: 'Streaming', color: 'green' },
              configured: { label: 'Configured', color: 'blue' },
              none: { label: 'Not Set', color: 'gray' },
              unknown: { label: 'Unknown', color: 'gray' },
            }}
          />

          {/* TEAM-3: Visibility now managed from Pit Crew — read-only display */}
          <div className="bg-neutral-900 rounded-ds-lg p-ds-4">
            <div className="flex items-center gap-ds-2 mb-ds-2">
              <svg className="w-5 h-5 text-neutral-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
              </svg>
              <span className="text-ds-body-sm text-neutral-400">Visibility</span>
            </div>
            <div className={`w-full min-h-[36px] px-ds-3 py-ds-2 rounded-ds-md font-medium text-ds-body-sm text-center ${
              data.visible
                ? 'bg-status-success/20 text-status-success'
                : 'bg-neutral-700/50 text-neutral-400'
            }`}>
              {data.visible ? 'Visible' : 'Hidden'}
            </div>
            <p className="text-ds-caption text-neutral-600 mt-ds-1">Managed from Pit Crew</p>
          </div>
        </div>

        {/* Stream Control - Only show when streaming */}
        {diagnostics?.video_status === 'streaming' && data?.event_id && (
          <div className="mt-ds-3">
            <StreamControlCard
              eventId={data.event_id}
              vehicleId={data.vehicle_id}
              token={token}
              onStreamStopped={() => {
                // Refresh diagnostics to update video_status
                onFetchDiagnostics()
              }}
            />
          </div>
        )}
      </section>

      {/* Diagnostics Section */}
      <section>
        <div className="flex items-center justify-between mb-ds-3">
          <h2 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wide">Diagnostics</h2>
          <button
            onClick={onCopyDiagnostics}
            className={`min-h-[36px] px-ds-3 py-ds-1 rounded-ds-md text-ds-body-sm font-medium transition-colors duration-ds-fast flex items-center gap-ds-2 ${
              copySuccess
                ? 'bg-status-success text-white'
                : 'bg-neutral-700 hover:bg-neutral-600 text-neutral-300'
            }`}
          >
            {copySuccess ? (
              <>
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
                Copied!
              </>
            ) : (
              <>
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3" />
                </svg>
                Copy
              </>
            )}
          </button>
        </div>

        <div className="bg-neutral-900 rounded-ds-lg p-ds-4 space-y-ds-3 font-mono text-ds-body-sm">
          <DiagRow label="Vehicle ID" value={data.vehicle_id} />
          <DiagRow label="Event ID" value={data.event_id || '—'} />
          <DiagRow
            label="Edge Status"
            value={diagnostics?.edge_status || '—'}
          />
          <DiagRow
            label="Edge Last Seen"
            value={
              diagnostics?.edge_last_seen_ms
                ? `${Math.round((Date.now() - diagnostics.edge_last_seen_ms) / 1000)}s ago`
                : 'Never'
            }
          />
          {diagnostics?.edge_ip && (
            <DiagRow label="Edge IP" value={diagnostics.edge_ip} />
          )}
          {diagnostics?.edge_version && (
            <DiagRow label="Edge Version" value={diagnostics.edge_version} />
          )}
          <DiagRow
            label="Queue Depth"
            value={diagnostics?.queue_depth?.toString() || '—'}
          />
          <DiagRow
            label="Last Position"
            value={
              diagnostics?.last_position_ms
                ? `${Math.round((Date.now() - diagnostics.last_position_ms) / 1000)}s ago`
                : '—'
            }
          />
        </div>
      </section>

      {/* Alerts Section (if any issues) */}
      {(isStale || isOffline || diagnostics?.gps_status === 'no_signal') && (
        <div className="space-y-ds-2">
          <h3 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wide">Alerts</h3>
          {isOffline && (
            <Alert variant="error">
              <strong className="block">Edge Device Offline</strong>
              <span className="text-ds-caption opacity-80">
                No data received in over 60 seconds.
                {diagnostics?.edge_last_seen_ms
                  ? ` Last seen ${Math.round((Date.now() - diagnostics.edge_last_seen_ms) / 1000)}s ago.`
                  : ' Edge has never connected to this event.'}
              </span>
              <span className="block text-ds-caption opacity-60 mt-ds-1">
                Likely causes: edge not powered, no network, wrong cloud URL, or incorrect truck token.
              </span>
            </Alert>
          )}
          {isStale && !isOffline && (
            <Alert variant="warning">
              <strong className="block">Stale Data</strong>
              <span className="text-ds-caption opacity-80">Data is delayed. May indicate poor signal or high latency.</span>
            </Alert>
          )}
          {diagnostics?.gps_status === 'no_signal' && (
            <Alert variant="warning">
              <strong className="block">GPS Signal Lost</strong>
              <span className="text-ds-caption opacity-80">GPS antenna may be obstructed or damaged.</span>
            </Alert>
          )}
        </div>
      )}
    </div>
  )
}

/**
 * Sharing Tab - Permission and video management
 * PROMPT 5: Updated to use TelemetrySharingPolicy for production/fan visibility
 */
function SharingTab({
  data,
  token,
  onUpdateVideoFeed,
}: {
  data: DashboardData
  token: string
  onUpdateVisibility?: (visible: boolean) => void
  onUpdateVideoFeed: (camera_name: string, youtube_url: string, permission_level: string) => void
}) {
  return (
    <div className="p-ds-4 space-y-ds-6">
      {/* Event status */}
      {data.event_id ? (
        <Alert variant="success">
          <strong className="block text-ds-body-sm">Active Event</strong>
          <span className="text-ds-caption opacity-80">Changes will be visible to fans immediately</span>
        </Alert>
      ) : (
        <Alert variant="warning">
          <strong className="block text-ds-body-sm">No Active Event</strong>
          <span className="text-ds-caption opacity-80">Register for an event to enable permission controls</span>
        </Alert>
      )}

      {/* TEAM-3: Visibility now managed from Pit Crew — read-only display here */}
      <div className="bg-neutral-900 rounded-ds-lg p-ds-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-ds-body font-medium text-neutral-50">Vehicle Visibility</div>
            <div className="text-ds-body-sm text-neutral-400">
              {data.visible ? 'Visible to fans' : 'Hidden from fans'}
            </div>
          </div>
          <Badge variant={data.visible ? 'success' : 'error'} size="sm">
            {data.visible ? 'Visible' : 'Hidden'}
          </Badge>
        </div>
        <p className="text-ds-caption text-neutral-500 mt-ds-2">
          Manage visibility from your Pit Crew Portal (Team tab).
        </p>
      </div>

      {/* TEAM-3: Telemetry Sharing now managed from Pit Crew — read-only notice */}
      <div className="bg-neutral-900 rounded-ds-lg p-ds-4">
        <div className="text-ds-body font-medium text-neutral-50 mb-ds-1">Telemetry Sharing</div>
        <p className="text-ds-body-sm text-neutral-400">
          Telemetry sharing policy is managed from your Pit Crew Portal (Team tab).
        </p>
      </div>

      {/* Video Feeds */}
      <section>
        <h2 className="text-ds-caption font-semibold text-neutral-400 uppercase tracking-wide mb-ds-3">
          Video Feeds
        </h2>
        <VideoFeedManager
          feeds={data.video_feeds}
          onUpdate={onUpdateVideoFeed}
        />
      </section>
    </div>
  )
}

// Helper Components

function StatusCard({
  title,
  status,
  icon,
  statusLabels,
  note,
}: {
  title: string
  status: string
  icon: React.ReactNode
  statusLabels: Record<string, { label: string; color: 'green' | 'yellow' | 'red' | 'blue' | 'gray' }>
  note?: string
}) {
  const statusInfo = statusLabels[status] || statusLabels.unknown || { label: 'Unknown', color: 'gray' }

  const colorClasses = {
    green: 'text-status-success bg-status-success/20',
    yellow: 'text-status-warning bg-status-warning/20',
    red: 'text-status-error bg-status-error/20',
    blue: 'text-accent-400 bg-accent-600/20',
    gray: 'text-neutral-400 bg-neutral-800',
  }

  return (
    <div className="bg-neutral-900 rounded-ds-lg p-ds-4">
      <div className="flex items-center gap-ds-2 mb-ds-2">
        <span className="text-neutral-400">{icon}</span>
        <span className="text-ds-body-sm text-neutral-400">{title}</span>
      </div>
      <div className={`inline-flex px-ds-2 py-ds-1 rounded-ds-sm text-ds-body-sm font-medium ${colorClasses[statusInfo.color]}`}>
        {statusInfo.label}
      </div>
      {note && (
        <div className="mt-ds-2 text-[10px] text-neutral-600">{note}</div>
      )}
    </div>
  )
}

function DiagRow({
  label,
  value,
  note,
}: {
  label: string
  value: string
  note?: string
}) {
  return (
    <div className="flex justify-between items-start">
      <span className="text-neutral-500">{label}</span>
      <div className="text-right">
        <span className="text-neutral-200">{value}</span>
        {note && (
          <div className="text-[9px] text-neutral-600 mt-0.5">{note}</div>
        )}
      </div>
    </div>
  )
}

/**
 * Stream Control Card - Allows teams to stop their active stream
 *
 * FIXED: Teams can now stop their own stream (parity with Production Control)
 */
function StreamControlCard({
  eventId,
  vehicleId,
  token,
  onStreamStopped,
}: {
  eventId: string
  vehicleId: string
  token: string
  onStreamStopped: () => void
}) {
  const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<{ message: string; action: string } | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  // Convert error to actionable message
  const getActionableError = (rawError: string): { message: string; action: string } => {
    const lowerError = rawError.toLowerCase()
    if (lowerError.includes('timeout')) {
      return {
        message: 'Edge device did not respond.',
        action: 'Check truck network connection and try again.',
      }
    }
    if (lowerError.includes('not found') || lowerError.includes('404')) {
      return {
        message: 'Stream control not available.',
        action: 'Edge device may have disconnected. Refresh the page.',
      }
    }
    if (lowerError.includes('unauthorized') || lowerError.includes('401') || lowerError.includes('403')) {
      return {
        message: 'Not authorized.',
        action: 'Your session may have expired. Please log in again.',
      }
    }
    if (lowerError.includes('network') || lowerError.includes('fetch')) {
      return {
        message: 'Network error.',
        action: 'Check your internet connection and try again.',
      }
    }
    return {
      message: rawError,
      action: 'Try again or contact support if the problem persists.',
    }
  }

  const handleStopStream = async () => {
    setIsLoading(true)
    setError(null)
    setSuccess(null)

    try {
      // Use unified stream control API
      const res = await fetch(
        `${API_BASE}/stream/events/${eventId}/vehicles/${vehicleId}/stop`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
        }
      )

      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || `HTTP ${res.status}`)
      }

      // Poll for state change (max 15 seconds)
      let attempts = 0
      while (attempts < 15) {
        await new Promise(r => setTimeout(r, 1000))
        attempts++

        const stateRes = await fetch(
          `${API_BASE}/stream/events/${eventId}/vehicles/${vehicleId}/state`,
          { headers: { Authorization: `Bearer ${token}` } }
        )

        if (stateRes.ok) {
          const stateData = await stateRes.json()

          if (stateData.state === 'IDLE' || stateData.state === 'DISCONNECTED') {
            setSuccess('Stream stopped successfully')
            onStreamStopped()
            return
          } else if (stateData.state === 'ERROR') {
            setError(getActionableError(stateData.error_message || 'Stream stop failed'))
            return
          }
        }
      }

      setError(getActionableError('Timeout waiting for stream to stop'))
    } catch (err) {
      setError(getActionableError(err instanceof Error ? err.message : 'Unknown error'))
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="bg-neutral-900 rounded-ds-lg p-ds-4">
      <div className="flex items-center gap-ds-2 mb-ds-3">
        <svg className="w-5 h-5 text-status-error" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M9 10a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z" />
        </svg>
        <span className="text-ds-body-sm text-neutral-400">Stream Control</span>
      </div>

      {error && (
        <div className="mb-ds-3 p-ds-2 bg-status-warning/20 border border-status-warning/50 rounded-ds-md">
          <div className="text-ds-caption font-medium text-status-warning">{error.message}</div>
          <div className="text-ds-caption text-neutral-400 mt-0.5">{error.action}</div>
        </div>
      )}

      {success && (
        <div className="mb-ds-3 p-ds-2 bg-status-success/20 border border-status-success/50 rounded-ds-md">
          <div className="text-ds-caption font-medium text-status-success">{success}</div>
        </div>
      )}

      <button
        onClick={handleStopStream}
        disabled={isLoading}
        className="w-full px-ds-3 py-ds-2 bg-status-error hover:bg-red-700 disabled:bg-neutral-700 disabled:text-neutral-500 text-white rounded-ds-md font-medium text-ds-body-sm transition-colors duration-ds-fast flex items-center justify-center gap-ds-2"
      >
        {isLoading ? (
          <>
            <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
            Stopping...
          </>
        ) : (
          <>
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <rect x="6" y="6" width="12" height="12" rx="2" />
            </svg>
            Stop Stream
          </>
        )}
      </button>
    </div>
  )
}
