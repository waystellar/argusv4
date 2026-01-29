/**
 * Event Detail Page - Full event management interface
 *
 * Features:
 * - Event info header with status controls
 * - Course map with GPX/KML overlay
 * - Vehicle registration and management
 * - Vehicle list with auth tokens
 *
 * UI-7: Refactored with design system tokens
 * UI-26: Completed migration — replaced space-y, legacy font sizing
 */
import { useState, useEffect, useRef, useMemo } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import maplibregl from 'maplibre-gl'
import { buildBasemapStyle } from '../../config/basemap'
import { useToast } from '../../hooks/useToast'
import { SkeletonVehicleCard } from '../../components/common/Skeleton'
import { PageHeader } from '../../components/common'
import { copyToClipboard } from '../../utils/clipboard'
import Badge from '../../components/ui/Badge'
import EmptyState from '../../components/ui/EmptyState'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

// Helper to get auth headers for admin API calls
function getAdminHeaders(): HeadersInit {
  const token = localStorage.getItem('admin_token')
  return token ? { Authorization: `Bearer ${token}` } : {}
}

interface Event {
  event_id: string
  name: string
  description: string | null
  status: string
  scheduled_start: string | null
  scheduled_end: string | null
  location: string | null
  classes: string[]
  max_vehicles: number
  vehicle_count: number
  created_at: string
}

interface Vehicle {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  driver_name: string | null
  codriver_name: string | null
  vehicle_class: string
  auth_token: string
  created_at: string
}

interface CourseData {
  event_id: string
  geojson: GeoJSON.FeatureCollection | null
  checkpoints: { checkpoint_number: number; name: string; lat: number; lon: number }[]
}

// Helper to get status badge variant
function getStatusBadgeVariant(status: string): 'success' | 'warning' | 'neutral' {
  switch (status) {
    case 'in_progress':
      return 'success'
    case 'upcoming':
      return 'warning'
    default:
      return 'neutral'
  }
}

export default function EventDetail() {
  const { eventId } = useParams<{ eventId: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const toast = useToast()

  const [showAddVehicle, setShowAddVehicle] = useState(false)
  const [copiedToken, setCopiedToken] = useState<string | null>(null)
  const [copiedEventId, setCopiedEventId] = useState(false)
  const [courseFile, setCourseFile] = useState<File | null>(null)
  const [uploadingCourse, setUploadingCourse] = useState(false)
  const [deletingEvent, setDeletingEvent] = useState(false)
  const [showEditModal, setShowEditModal] = useState(false)
  const [vehiclePage, setVehiclePage] = useState(1)
  const vehiclesPerPage = 10

  // Confirmation dialog state
  const [confirmDialog, setConfirmDialog] = useState<{
    message: string
    onConfirm: () => void
    isDangerous?: boolean
  } | null>(null)

  const handleConfirmAction = (message: string, onConfirm: () => void, isDangerous?: boolean) => {
    setConfirmDialog({ message, onConfirm, isDangerous })
  }

  // Delete event handler
  const deleteEvent = () => {
    handleConfirmAction(
      `Delete this event and ALL associated data (vehicles, positions, timing)? This action cannot be undone.`,
      async () => {
        setDeletingEvent(true)
        try {
          const res = await fetch(`${API_BASE}/admin/events/${eventId}`, {
            method: 'DELETE',
            credentials: 'include',
            headers: getAdminHeaders(),
          })
          if (!res.ok) {
            const data = await res.json().catch(() => ({}))
            throw new Error(data.detail || 'Failed to delete event')
          }
          toast.success('Event deleted')
          queryClient.invalidateQueries({ queryKey: ['admin', 'events'] })
          navigate('/admin')
        } catch (err) {
          toast.error('Failed to delete event', err instanceof Error ? err.message : undefined)
          setDeletingEvent(false)
        }
      },
      true // isDangerous
    )
  }

  // Fetch event details
  const { data: event, isLoading: eventLoading, error: eventError } = useQuery({
    queryKey: ['event', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/admin/events/${eventId}`, {
        credentials: 'include',
        headers: getAdminHeaders(),
      })
      if (!res.ok) throw new Error('Failed to load event')
      return res.json() as Promise<Event>
    },
    enabled: !!eventId,
  })

  // Fetch vehicles
  const { data: vehicles, isLoading: vehiclesLoading } = useQuery({
    queryKey: ['vehicles', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/admin/events/${eventId}/vehicles`, {
        credentials: 'include',
        headers: getAdminHeaders(),
      })
      if (!res.ok) throw new Error('Failed to load vehicles')
      return res.json() as Promise<Vehicle[]>
    },
    enabled: !!eventId,
  })

  // Fetch course data
  const { data: courseData } = useQuery({
    queryKey: ['course', eventId],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/events/${eventId}`)
      if (!res.ok) return null
      const data = await res.json()
      return {
        event_id: eventId,
        geojson: data.course_geojson || null,
        checkpoints: [],
      } as CourseData
    },
    enabled: !!eventId,
  })

  // Update event status mutation
  const updateStatusMutation = useMutation({
    mutationFn: async (newStatus: string) => {
      const res = await fetch(`${API_BASE}/admin/events/${eventId}/status`, {
        method: 'PUT',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json', ...getAdminHeaders() },
        body: JSON.stringify({ status: newStatus }),
      })
      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || 'Failed to update status')
      }
      return res.json()
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['event', eventId] })
      const statusLabel = data.new_status === 'in_progress' ? 'LIVE' : data.new_status.toUpperCase()
      toast.success(`Event is now ${statusLabel}`)
    },
    onError: (err: Error) => {
      toast.error('Failed to update status', err.message)
    },
  })

  // Copy event ID to clipboard
  const copyEventId = async () => {
    if (!eventId) return
    const success = await copyToClipboard(eventId)
    if (success) {
      setCopiedEventId(true)
      setTimeout(() => setCopiedEventId(false), 2000)
      toast.success('Event ID copied to clipboard')
    } else {
      toast.error('Failed to copy', 'Clipboard access denied')
    }
  }

  // Copy token to clipboard with fallback for HTTP contexts
  const copyToken = async (token: string) => {
    const success = await copyToClipboard(token)
    if (success) {
      setCopiedToken(token)
      setTimeout(() => setCopiedToken(null), 2000)
      toast.success('Token copied to clipboard')
    } else {
      toast.error('Failed to copy', 'Clipboard access denied')
    }
  }

  // IMPORTANT: All hooks must be called before early returns to avoid React error #310
  // Pagination calculations - moved here from after loading check
  const totalVehiclePages = vehicles ? Math.ceil(vehicles.length / vehiclesPerPage) : 0
  const paginatedVehicles = useMemo(() => {
    if (!vehicles) return []
    const start = (vehiclePage - 1) * vehiclesPerPage
    return vehicles.slice(start, start + vehiclesPerPage)
  }, [vehicles, vehiclePage, vehiclesPerPage])

  // Reset to page 1 when vehicles change (e.g., new vehicle added)
  useEffect(() => {
    if (vehicles && vehiclePage > Math.ceil(vehicles.length / vehiclesPerPage)) {
      setVehiclePage(1)
    }
  }, [vehicles, vehiclePage, vehiclesPerPage])

  // Export vehicles to CSV
  const exportVehiclesToCSV = () => {
    if (!vehicles || vehicles.length === 0) {
      toast.warning('No data to export', 'Register vehicles first')
      return
    }

    const headers = ['number', 'class', 'team_name', 'driver_name', 'codriver_name', 'auth_token']
    const rows = vehicles.map(v => [
      v.vehicle_number,
      v.vehicle_class,
      `"${(v.team_name || '').replace(/"/g, '""')}"`,
      `"${(v.driver_name || '').replace(/"/g, '""')}"`,
      `"${(v.codriver_name || '').replace(/"/g, '""')}"`,
      v.auth_token,
    ])

    const csvContent = [headers.join(','), ...rows.map(r => r.join(','))].join('\n')
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `vehicles_${event?.name?.replace(/\s+/g, '_') || eventId}_${new Date().toISOString().split('T')[0]}.csv`
    link.click()
    URL.revokeObjectURL(url)
    toast.success('Export complete', `${vehicles.length} vehicles exported`)
  }

  // Upload course file
  const uploadCourse = async () => {
    if (!courseFile || !eventId) return

    setUploadingCourse(true)
    try {
      const formData = new FormData()
      formData.append('file', courseFile)

      const res = await fetch(`${API_BASE}/admin/events/${eventId}/course`, {
        method: 'POST',
        credentials: 'include',
        headers: getAdminHeaders(),
        body: formData,
      })

      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || 'Failed to upload course')
      }

      setCourseFile(null)
      queryClient.invalidateQueries({ queryKey: ['course', eventId] })
      queryClient.invalidateQueries({ queryKey: ['event', eventId] })
      toast.success('Course uploaded', `${courseFile.name} processed successfully`)
    } catch (err) {
      console.error('Course upload failed:', err)
      toast.error('Upload failed', err instanceof Error ? err.message : 'Failed to upload course file')
    } finally {
      setUploadingCourse(false)
    }
  }

  if (eventLoading) {
    return (
      <div className="min-h-screen bg-neutral-900 flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-accent-500"></div>
      </div>
    )
  }

  if (eventError || !event) {
    return (
      <div className="min-h-screen bg-neutral-900 flex items-center justify-center">
        <div className="text-center">
          <p className="text-status-error mb-ds-4">Event not found</p>
          <Link to="/admin" className="text-accent-400 hover:underline">Back to Dashboard</Link>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-neutral-900">
      <PageHeader
        title="Event"
        subtitle={event.name}
        backTo="/admin"
        backLabel="Back to admin"
        rightSlot={
          <div className="flex items-center gap-ds-3">
            <Badge
              variant={getStatusBadgeVariant(event.status)}
              dot={event.status === 'in_progress'}
              pulse={event.status === 'in_progress'}
            >
              {event.status === 'in_progress' ? 'LIVE' : event.status.replace('_', ' ').toUpperCase()}
            </Badge>
            {event.status === 'upcoming' && (
              <button
                onClick={() => updateStatusMutation.mutate('in_progress')}
                className="px-ds-4 py-ds-2 bg-status-success hover:bg-status-success/90 rounded-ds-md text-white font-medium"
              >
                Start Race
              </button>
            )}
            {event.status === 'in_progress' && (
              <button
                onClick={() => updateStatusMutation.mutate('finished')}
                className="px-ds-4 py-ds-2 bg-status-error hover:bg-status-error/90 rounded-ds-md text-white font-medium"
              >
                End Race
              </button>
            )}
            {event.status !== 'in_progress' && (
              <button
                onClick={deleteEvent}
                disabled={deletingEvent}
                className="p-ds-2 text-neutral-400 hover:text-status-error hover:bg-status-error/10 rounded-ds-md transition-colors disabled:opacity-50"
                title="Delete Event"
              >
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
              </button>
            )}
          </div>
        }
      />

      <div className="max-w-7xl mx-auto px-ds-4 py-ds-6">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-ds-6">
          {/* Left Column - Map & Course */}
          <div className="lg:col-span-2 flex flex-col gap-ds-6">
            {/* Course Map */}
            <div className="bg-neutral-800 rounded-ds-lg overflow-hidden">
              <div className="p-ds-4 border-b border-neutral-700 flex items-center justify-between">
                <h2 className="font-semibold text-neutral-50">Course Map</h2>
                <label className="cursor-pointer">
                  <input
                    type="file"
                    accept=".gpx,.kml,.kmz"
                    className="hidden"
                    onChange={(e) => setCourseFile(e.target.files?.[0] || null)}
                  />
                  <span className="text-ds-body-sm text-accent-400 hover:text-accent-300">
                    {courseData?.geojson ? 'Replace Course' : 'Upload GPX/KML'}
                  </span>
                </label>
              </div>

              {courseFile && (
                <div className="p-ds-4 bg-accent-900/30 border-b border-neutral-700 flex items-center justify-between">
                  <span className="text-ds-body-sm text-accent-300">
                    Selected: {courseFile.name}
                  </span>
                  <div className="flex gap-ds-2">
                    <button
                      onClick={() => setCourseFile(null)}
                      className="text-ds-body-sm text-neutral-400 hover:text-neutral-50"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={uploadCourse}
                      disabled={uploadingCourse}
                      className="px-ds-3 py-ds-1 bg-accent-500 hover:bg-accent-600 rounded-ds-sm text-ds-body-sm text-white disabled:opacity-50"
                    >
                      {uploadingCourse ? 'Uploading...' : 'Upload'}
                    </button>
                  </div>
                </div>
              )}

              <CourseMap courseData={courseData} />
            </div>

            {/* Event Details */}
            <div className="bg-neutral-800 rounded-ds-lg p-ds-4">
              <div className="flex items-center justify-between mb-ds-4">
                <h2 className="font-semibold text-neutral-50">Event Details</h2>
                <button
                  onClick={() => setShowEditModal(true)}
                  className="text-ds-body-sm text-accent-400 hover:text-accent-300 flex items-center gap-ds-1"
                >
                  <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                  </svg>
                  Edit
                </button>
              </div>
              {/* Event ID with copy button */}
              <div className="flex items-center gap-ds-2 mb-ds-4 pb-ds-4 border-b border-neutral-700" data-testid="event-id-display">
                <span className="text-neutral-400 text-ds-body-sm">Event ID:</span>
                <code className="font-mono text-ds-body-sm text-neutral-50 bg-neutral-900 px-ds-2 py-ds-1 rounded-ds-sm select-all">
                  {event.event_id}
                </code>
                <button
                  onClick={copyEventId}
                  className="ml-ds-1 px-ds-2 py-ds-1 text-ds-body-sm rounded-ds-sm transition-colors text-neutral-400 hover:text-neutral-50 hover:bg-neutral-700"
                  aria-label="Copy event ID to clipboard"
                  data-testid="copy-event-id"
                >
                  {copiedEventId ? (
                    <span className="text-status-success flex items-center gap-ds-1">
                      <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                      </svg>
                      Copied
                    </span>
                  ) : (
                    <span className="flex items-center gap-ds-1">
                      <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                      </svg>
                      Copy
                    </span>
                  )}
                </button>
              </div>

              <div className="grid grid-cols-2 gap-ds-4 text-ds-body-sm">
                <div>
                  <span className="text-neutral-400">Start:</span>
                  <p className="text-neutral-50">
                    {event.scheduled_start
                      ? new Date(event.scheduled_start).toLocaleString()
                      : 'Not set'}
                  </p>
                </div>
                <div>
                  <span className="text-neutral-400">End:</span>
                  <p className="text-neutral-50">
                    {event.scheduled_end
                      ? new Date(event.scheduled_end).toLocaleString()
                      : 'Not set'}
                  </p>
                </div>
                <div>
                  <span className="text-neutral-400">Classes:</span>
                  <p className="text-neutral-50">
                    {event.classes?.length > 0
                      ? event.classes.join(', ')
                      : 'None specified'}
                  </p>
                </div>
                <div>
                  <span className="text-neutral-400">Max Vehicles:</span>
                  <p className="text-neutral-50">{event.max_vehicles}</p>
                </div>
              </div>
              {event.description && (
                <div className="mt-ds-4 pt-ds-4 border-t border-neutral-700">
                  <span className="text-neutral-400 text-ds-body-sm">Description:</span>
                  <p className="text-neutral-50 text-ds-body-sm mt-ds-1">{event.description}</p>
                </div>
              )}
            </div>
          </div>

          {/* Right Column - Vehicles */}
          <div className="flex flex-col gap-ds-6">
            {/* Vehicle Registration */}
            <div className="bg-neutral-800 rounded-ds-lg">
              <div className="p-ds-4 border-b border-neutral-700 flex items-center justify-between">
                <h2 className="font-semibold text-neutral-50">
                  Vehicles ({vehicles?.length || 0}/{event.max_vehicles})
                </h2>
                <div className="flex items-center gap-ds-2">
                  {vehicles && vehicles.length > 0 && (
                    <button
                      onClick={exportVehiclesToCSV}
                      className="p-1.5 text-neutral-400 hover:text-neutral-50 hover:bg-neutral-700 rounded-ds-sm transition-colors"
                      title="Export to CSV"
                    >
                      <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                      </svg>
                    </button>
                  )}
                  <button
                    onClick={() => setShowAddVehicle(!showAddVehicle)}
                    className="px-ds-3 py-ds-1 bg-accent-500 hover:bg-accent-600 rounded-ds-sm text-ds-body-sm text-white"
                  >
                    {showAddVehicle ? 'Cancel' : '+ Add Vehicle'}
                  </button>
                </div>
              </div>

              {showAddVehicle && (
                <AddVehicleForm
                  eventId={eventId!}
                  classes={event.classes}
                  onSuccess={() => {
                    setShowAddVehicle(false)
                    queryClient.invalidateQueries({ queryKey: ['vehicles', eventId] })
                    queryClient.invalidateQueries({ queryKey: ['event', eventId] })
                  }}
                />
              )}

              {/* Vehicle List */}
              <div className="divide-y divide-neutral-700">
                {vehiclesLoading ? (
                  <div className="divide-y divide-neutral-700">
                    <SkeletonVehicleCard />
                    <SkeletonVehicleCard />
                    <SkeletonVehicleCard />
                  </div>
                ) : vehicles?.length === 0 ? (
                  <EmptyState
                    icon={
                      <svg className="w-12 h-12" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                          d="M9 17a2 2 0 11-4 0 2 2 0 014 0zM19 17a2 2 0 11-4 0 2 2 0 014 0z" />
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                          d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h1m8-1a1 1 0 01-1 1H9m4-1V8a1 1 0 011-1h2.586a1 1 0 01.707.293l3.414 3.414a1 1 0 01.293.707V16a1 1 0 01-1 1h-1m-6-1a1 1 0 001 1h1M5 17a2 2 0 104 0m-4 0a2 2 0 114 0m6 0a2 2 0 104 0m-4 0a2 2 0 114 0" />
                      </svg>
                    }
                    title="No vehicles registered"
                    description="Click 'Add Vehicle' to register a truck"
                    className="py-ds-8"
                  />
                ) : (
                  paginatedVehicles.map((vehicle) => (
                    <VehicleCard
                      key={vehicle.vehicle_id}
                      vehicle={vehicle}
                      eventId={eventId!}
                      copiedToken={copiedToken}
                      onCopyToken={copyToken}
                      onRefresh={() => {
                        queryClient.invalidateQueries({ queryKey: ['vehicles', eventId] })
                        queryClient.invalidateQueries({ queryKey: ['event', eventId] })
                      }}
                      onConfirmAction={handleConfirmAction}
                      canDelete={event.status !== 'in_progress'}
                    />
                  ))
                )}
              </div>

              {/* Pagination Controls */}
              {vehicles && vehicles.length > vehiclesPerPage && (
                <div className="p-ds-3 border-t border-neutral-700 flex items-center justify-between bg-neutral-800">
                  <span className="text-ds-caption text-neutral-400">
                    Showing {((vehiclePage - 1) * vehiclesPerPage) + 1}-
                    {Math.min(vehiclePage * vehiclesPerPage, vehicles.length)} of {vehicles.length}
                  </span>
                  <div className="flex items-center gap-ds-1">
                    <button
                      onClick={() => setVehiclePage(p => Math.max(1, p - 1))}
                      disabled={vehiclePage === 1}
                      className="p-1.5 rounded-ds-sm hover:bg-neutral-700 disabled:opacity-30 disabled:cursor-not-allowed text-neutral-400"
                    >
                      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                      </svg>
                    </button>
                    {Array.from({ length: totalVehiclePages }, (_, i) => i + 1).map(page => (
                      <button
                        key={page}
                        onClick={() => setVehiclePage(page)}
                        className={`w-7 h-7 rounded-ds-sm text-ds-body-sm font-medium ${
                          page === vehiclePage
                            ? 'bg-accent-500 text-white'
                            : 'text-neutral-400 hover:bg-neutral-700'
                        }`}
                      >
                        {page}
                      </button>
                    ))}
                    <button
                      onClick={() => setVehiclePage(p => Math.min(totalVehiclePages, p + 1))}
                      disabled={vehiclePage === totalVehiclePages}
                      className="p-1.5 rounded-ds-sm hover:bg-neutral-700 disabled:opacity-30 disabled:cursor-not-allowed text-neutral-400"
                    >
                      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                      </svg>
                    </button>
                  </div>
                </div>
              )}
            </div>

            {/* Quick Links */}
            <div className="bg-neutral-800 rounded-ds-lg p-ds-4">
              <h2 className="font-semibold text-neutral-50 mb-ds-3">Quick Links</h2>
              <div className="flex flex-col gap-ds-2">
                <a
                  href={`/events/${eventId}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="block p-ds-3 bg-neutral-700 hover:bg-neutral-600 rounded-ds-md text-ds-body-sm"
                >
                  <span className="text-neutral-50 font-medium">Fan Portal</span>
                  <span className="text-neutral-400 ml-ds-2">→ Live map & leaderboard</span>
                </a>
                <a
                  href={`/events/${eventId}/production`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="block p-ds-3 bg-neutral-700 hover:bg-neutral-600 rounded-ds-md text-ds-body-sm"
                >
                  <span className="text-neutral-50 font-medium">Production Director</span>
                  <span className="text-neutral-400 ml-ds-2">→ Camera switching</span>
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Edit Event Modal */}
      {showEditModal && event && (
        <EditEventModal
          event={event}
          onClose={() => setShowEditModal(false)}
          onSave={() => {
            queryClient.invalidateQueries({ queryKey: ['event', eventId] })
            setShowEditModal(false)
          }}
        />
      )}

      {/* Confirmation Dialog */}
      {confirmDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-ds-4">
          <div
            className="absolute inset-0 bg-black/70"
            onClick={() => setConfirmDialog(null)}
          />
          <div className={`relative rounded-ds-lg border p-ds-6 max-w-md w-full shadow-ds-overlay ${
            confirmDialog.isDangerous
              ? 'bg-status-error/10 border-status-error/30'
              : 'bg-neutral-800 border-neutral-700'
          }`}>
            <h3 className={`text-ds-heading mb-ds-2 ${
              confirmDialog.isDangerous ? 'text-status-error' : 'text-neutral-50'
            }`}>
              {confirmDialog.isDangerous ? '⚠️ Danger Zone' : 'Confirm Action'}
            </h3>
            <p className={`text-ds-body-sm mb-ds-6 ${confirmDialog.isDangerous ? 'text-neutral-300' : 'text-neutral-300'}`}>
              {confirmDialog.message}
            </p>
            <div className="flex gap-ds-3 justify-end">
              <button
                onClick={() => setConfirmDialog(null)}
                className="px-ds-4 py-ds-2 bg-neutral-700 hover:bg-neutral-600 rounded-ds-md text-neutral-50 font-medium"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  confirmDialog.onConfirm()
                  setConfirmDialog(null)
                }}
                className={`px-ds-4 py-ds-2 rounded-ds-md text-white font-medium ${
                  confirmDialog.isDangerous
                    ? 'bg-status-error hover:bg-status-error/90'
                    : 'bg-accent-500 hover:bg-accent-600'
                }`}
              >
                {confirmDialog.isDangerous ? 'Delete Permanently' : 'Confirm'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

/**
 * Course Map Component with GPX/GeoJSON overlay
 */
function CourseMap({ courseData }: { courseData: CourseData | null | undefined }) {
  const containerRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<maplibregl.Map | null>(null)
  // CLOUD-MAP-2: Topo overlay error detection
  const [topoUnavailable, setTopoUnavailable] = useState(false)
  const topoErrorFiredRef = useRef(false)

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return

    // MAP-STYLE-2: Use centralized basemap config
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: buildBasemapStyle(),
      center: [-116.38, 34.12], // Default to KOH area
      zoom: 10,
      attributionControl: false,
    })

    map.addControl(new maplibregl.NavigationControl(), 'top-right')
    map.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-right')

    // CLOUD-MAP-2: Detect topo overlay failures (same pattern as Map.tsx)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    map.on('error', (e: any) => {
      if (topoErrorFiredRef.current) return
      const isTopoSource = e.sourceId === 'topo-tiles'
      const isTileError = e.error?.message?.includes('tile') ||
        e.error?.message?.includes('Failed to fetch') ||
        e.error?.status === 429 || e.error?.status === 403 ||
        e.error?.status === 0
      if (isTopoSource || (isTileError && !e.sourceId)) {
        topoErrorFiredRef.current = true
        setTopoUnavailable(true)
      }
    })

    mapRef.current = map

    return () => {
      map.remove()
      mapRef.current = null
    }
  }, [])

  // Add course layer when data changes
  useEffect(() => {
    const map = mapRef.current
    if (!map || !courseData?.geojson) return

    // Track if this effect is still active (for cleanup)
    let cancelled = false

    // Wait for map to load
    const addCourse = () => {
      // Check if effect was cleaned up while waiting
      if (cancelled) return

      try {
        // Remove existing course layer if present
        if (map.getLayer('course-line')) {
          map.removeLayer('course-line')
        }
        if (map.getSource('course')) {
          map.removeSource('course')
        }

        // Add course source
        map.addSource('course', {
          type: 'geojson',
          data: courseData.geojson!,
        })

        // Add course line layer
        map.addLayer({
          id: 'course-line',
          type: 'line',
          source: 'course',
          paint: {
            'line-color': '#ff6600',
            'line-width': 4,
            'line-opacity': 0.8,
          },
        })

        // Fit bounds to course
        const bounds = new maplibregl.LngLatBounds()
        const features = courseData.geojson!.features
        features.forEach((feature) => {
          if (feature.geometry.type === 'LineString') {
            feature.geometry.coordinates.forEach((coord) => {
              bounds.extend(coord as [number, number])
            })
          } else if (feature.geometry.type === 'Point') {
            bounds.extend(feature.geometry.coordinates as [number, number])
          }
        })

        if (!bounds.isEmpty()) {
          map.fitBounds(bounds, { padding: 50 })
        }
      } catch (err) {
        console.error('[CourseMap] Failed to add course overlay:', err)
      }
    }

    // Use isStyleLoaded() for more reliable check - style must be loaded to add layers
    if (map.isStyleLoaded()) {
      addCourse()
    } else {
      // Listen for style.load which fires when style is ready for layer additions
      const onStyleLoad = () => addCourse()
      map.once('style.load', onStyleLoad)
      // Also listen for 'load' in case style.load already fired
      map.once('load', onStyleLoad)
    }

    // Cleanup function - mark as cancelled and remove listener
    return () => {
      cancelled = true
    }
  }, [courseData])

  return (
    <div ref={containerRef} className="relative h-80 w-full bg-neutral-900">
      {/* CLOUD-MAP-2: Topo overlay unavailable banner */}
      {topoUnavailable && (
        <div className="absolute top-2 left-2 z-10 bg-amber-800/90 text-amber-100 text-xs px-3 py-1.5 rounded-lg flex items-center gap-1.5">
          <svg className="w-3.5 h-3.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          Topo layer unavailable — showing base map
        </div>
      )}
      {!courseData?.geojson && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none z-10">
          <div className="text-center text-neutral-400">
            <svg className="w-12 h-12 mx-auto mb-ds-2 opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
            </svg>
            <p className="text-ds-body-sm">No course uploaded</p>
            <p className="text-ds-caption mt-ds-1">Upload a GPX or KML file to display the route</p>
          </div>
        </div>
      )}
    </div>
  )
}

/**
 * Add Vehicle Form
 */
function AddVehicleForm({
  eventId,
  classes,
  onSuccess,
}: {
  eventId: string
  classes: string[]
  onSuccess: () => void
}) {
  const toast = useToast()
  const [formData, setFormData] = useState({
    vehicle_number: '',
    team_name: '',
    driver_name: '',
    codriver_name: '',
    vehicle_class: classes[0] || 'trophy_truck',
  })
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})

  const validateForm = (): boolean => {
    const errors: Record<string, string> = {}

    if (!formData.vehicle_number.trim()) {
      errors.vehicle_number = 'Vehicle number is required'
    } else if (!/^[a-zA-Z0-9-]+$/.test(formData.vehicle_number)) {
      errors.vehicle_number = 'Only letters, numbers, and dashes allowed'
    }

    if (!formData.team_name.trim()) {
      errors.team_name = 'Team name is required'
    } else if (formData.team_name.length < 2) {
      errors.team_name = 'Team name must be at least 2 characters'
    }

    setFieldErrors(errors)
    return Object.keys(errors).length === 0
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!validateForm()) return

    setIsSubmitting(true)
    setError(null)

    try {
      const res = await fetch(`${API_BASE}/admin/events/${eventId}/vehicles`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json', ...getAdminHeaders() },
        body: JSON.stringify(formData),
      })

      if (!res.ok) {
        const data = await res.json()
        throw new Error(data.detail || 'Failed to register vehicle')
      }

      toast.success('Vehicle registered', `#${formData.vehicle_number} added to event`)
      onSuccess()
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to register vehicle'
      setError(message)
      toast.error('Registration failed', message)
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="p-ds-4 border-b border-neutral-700 bg-neutral-800">
      {error && (
        <div className="mb-ds-3 p-ds-2 bg-status-error/10 border border-status-error/30 rounded-ds-md text-status-error text-ds-body-sm">
          {error}
        </div>
      )}

      <div className="grid grid-cols-2 gap-ds-3">
        <div>
          <label className="block text-ds-caption text-neutral-400 mb-ds-1">Vehicle # *</label>
          <input
            type="text"
            value={formData.vehicle_number}
            onChange={(e) => {
              const value = e.target.value.slice(0, 10)
              setFormData({ ...formData, vehicle_number: value })
              if (fieldErrors.vehicle_number && value.trim()) {
                setFieldErrors({ ...fieldErrors, vehicle_number: '' })
              }
            }}
            className={`w-full px-ds-3 py-ds-2 bg-neutral-700 border rounded-ds-md text-neutral-50 text-ds-body-sm ${
              fieldErrors.vehicle_number ? 'border-status-error' : 'border-neutral-600'
            }`}
            placeholder="e.g., 83"
          />
          {fieldErrors.vehicle_number && (
            <p className="mt-0.5 text-ds-caption text-status-error">{fieldErrors.vehicle_number}</p>
          )}
        </div>
        <div>
          <label className="block text-ds-caption text-neutral-400 mb-ds-1">Class *</label>
          <select
            value={formData.vehicle_class}
            onChange={(e) => setFormData({ ...formData, vehicle_class: e.target.value })}
            className="w-full px-ds-3 py-ds-2 bg-neutral-700 border border-neutral-600 rounded-ds-md text-neutral-50 text-ds-body-sm"
          >
            {classes.length > 0 ? (
              classes.map((c) => (
                <option key={c} value={c}>{c.replace(/_/g, ' ').toUpperCase()}</option>
              ))
            ) : (
              <>
                <option value="trophy_truck">Trophy Truck</option>
                <option value="class_1">Class 1</option>
                <option value="6100">6100</option>
                <option value="utv_pro">UTV Pro</option>
              </>
            )}
          </select>
        </div>
        <div className="col-span-2">
          <label className="block text-ds-caption text-neutral-400 mb-ds-1">Team Name *</label>
          <input
            type="text"
            value={formData.team_name}
            onChange={(e) => {
              const value = e.target.value.slice(0, 100)
              setFormData({ ...formData, team_name: value })
              if (fieldErrors.team_name && value.trim().length >= 2) {
                setFieldErrors({ ...fieldErrors, team_name: '' })
              }
            }}
            className={`w-full px-ds-3 py-ds-2 bg-neutral-700 border rounded-ds-md text-neutral-50 text-ds-body-sm ${
              fieldErrors.team_name ? 'border-status-error' : 'border-neutral-600'
            }`}
            placeholder="e.g., Red Bull Racing"
          />
          {fieldErrors.team_name && (
            <p className="mt-0.5 text-ds-caption text-status-error">{fieldErrors.team_name}</p>
          )}
        </div>
        <div>
          <label className="block text-ds-caption text-neutral-400 mb-ds-1">Driver</label>
          <input
            type="text"
            value={formData.driver_name}
            onChange={(e) => setFormData({ ...formData, driver_name: e.target.value })}
            className="w-full px-ds-3 py-ds-2 bg-neutral-700 border border-neutral-600 rounded-ds-md text-neutral-50 text-ds-body-sm"
            placeholder="Driver name"
          />
        </div>
        <div>
          <label className="block text-ds-caption text-neutral-400 mb-ds-1">Co-Driver</label>
          <input
            type="text"
            value={formData.codriver_name}
            onChange={(e) => setFormData({ ...formData, codriver_name: e.target.value })}
            className="w-full px-ds-3 py-ds-2 bg-neutral-700 border border-neutral-600 rounded-ds-md text-neutral-50 text-ds-body-sm"
            placeholder="Co-driver name"
          />
        </div>
      </div>

      <button
        type="submit"
        disabled={isSubmitting}
        className="mt-ds-3 w-full py-ds-2 bg-status-success hover:bg-status-success/90 disabled:opacity-50 rounded-ds-md text-white font-medium text-ds-body-sm"
      >
        {isSubmitting ? 'Registering...' : 'Register Vehicle'}
      </button>
    </form>
  )
}

/**
 * Vehicle Card with token display
 */
function VehicleCard({
  vehicle,
  eventId,
  copiedToken,
  onCopyToken,
  onRefresh,
  onConfirmAction,
  canDelete,
}: {
  vehicle: Vehicle
  eventId: string
  copiedToken: string | null
  onCopyToken: (token: string) => void
  onRefresh: () => void
  onConfirmAction: (message: string, onConfirm: () => void) => void
  canDelete: boolean
}) {
  const toast = useToast()
  const [showToken, setShowToken] = useState(false)
  const [regenerating, setRegenerating] = useState(false)
  const [deleting, setDeleting] = useState(false)

  const regenerateToken = async () => {
    onConfirmAction(
      `Regenerate auth token for #${vehicle.vehicle_number}? The old token will stop working immediately.`,
      async () => {
        setRegenerating(true)
        try {
          const res = await fetch(
            `${API_BASE}/admin/events/${eventId}/vehicles/${vehicle.vehicle_id}/regenerate-token`,
            { method: 'POST', credentials: 'include', headers: getAdminHeaders() }
          )
          if (!res.ok) {
            const data = await res.json().catch(() => ({}))
            throw new Error(data.detail || 'Failed to regenerate token')
          }
          toast.success('Token regenerated', `New token for #${vehicle.vehicle_number}`)
          onRefresh()
        } catch (err) {
          toast.error('Failed to regenerate token', err instanceof Error ? err.message : undefined)
        } finally {
          setRegenerating(false)
        }
      }
    )
  }

  const deleteVehicle = () => {
    onConfirmAction(
      `Remove #${vehicle.vehicle_number} (${vehicle.team_name}) from this event? This will also delete any position/timing data for this vehicle.`,
      async () => {
        setDeleting(true)
        try {
          const res = await fetch(
            `${API_BASE}/admin/events/${eventId}/vehicles/${vehicle.vehicle_id}`,
            { method: 'DELETE', credentials: 'include', headers: getAdminHeaders() }
          )
          if (!res.ok) {
            const data = await res.json().catch(() => ({}))
            throw new Error(data.detail || 'Failed to remove vehicle')
          }
          toast.success('Vehicle removed', `#${vehicle.vehicle_number} removed from event`)
          onRefresh()
        } catch (err) {
          toast.error('Failed to remove vehicle', err instanceof Error ? err.message : undefined)
        } finally {
          setDeleting(false)
        }
      }
    )
  }

  return (
    <div className="p-ds-4 hover:bg-neutral-800">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-ds-2">
            <span className="text-ds-body font-bold text-neutral-50">#{vehicle.vehicle_number}</span>
            <Badge variant="neutral" size="sm">
              {vehicle.vehicle_class.replace(/_/g, ' ')}
            </Badge>
          </div>
          <p className="text-ds-body-sm text-neutral-300">{vehicle.team_name}</p>
          {vehicle.driver_name && (
            <p className="text-ds-caption text-neutral-400 mt-ds-1">
              Driver: {vehicle.driver_name}
              {vehicle.codriver_name && ` / ${vehicle.codriver_name}`}
            </p>
          )}
        </div>
      </div>

      {/* Auth Token Section */}
      <div className="mt-ds-3 p-ds-2 bg-neutral-900 rounded-ds-md">
        <div className="flex items-center justify-between mb-ds-1">
          <span className="text-ds-caption text-neutral-400">Auth Token</span>
          <div className="flex gap-ds-2">
            <button
              onClick={() => setShowToken(!showToken)}
              className="text-ds-caption text-accent-400 hover:text-accent-300"
            >
              {showToken ? 'Hide' : 'Show'}
            </button>
            <button
              onClick={() => onCopyToken(vehicle.auth_token)}
              className="text-ds-caption text-accent-400 hover:text-accent-300"
            >
              {copiedToken === vehicle.auth_token ? '✓ Copied' : 'Copy'}
            </button>
            <button
              onClick={regenerateToken}
              disabled={regenerating}
              className="text-ds-caption text-status-warning hover:text-status-warning/80 disabled:opacity-50"
            >
              {regenerating ? '...' : 'Regenerate'}
            </button>
          </div>
        </div>
        <code className="text-ds-caption text-status-success break-all">
          {showToken ? vehicle.auth_token : '••••••••••••••••••••••••'}
        </code>
      </div>

      {/* Delete Button - only shown when event is not in progress */}
      {canDelete && (
        <button
          onClick={deleteVehicle}
          disabled={deleting}
          className="mt-ds-3 w-full py-ds-2 text-ds-caption text-status-error hover:text-status-error/80 hover:bg-status-error/10 rounded-ds-md border border-transparent hover:border-status-error/30 transition-colors disabled:opacity-50"
        >
          {deleting ? 'Removing...' : 'Remove from Event'}
        </button>
      )}
    </div>
  )
}

/**
 * Edit Event Modal
 */
function EditEventModal({
  event,
  onClose,
  onSave,
}: {
  event: Event
  onClose: () => void
  onSave: () => void
}) {
  const toast = useToast()
  const [saving, setSaving] = useState(false)
  const [formData, setFormData] = useState({
    name: event.name,
    description: event.description || '',
    location: event.location || '',
    scheduled_start: event.scheduled_start
      ? new Date(event.scheduled_start).toISOString().slice(0, 16)
      : '',
    scheduled_end: event.scheduled_end
      ? new Date(event.scheduled_end).toISOString().slice(0, 16)
      : '',
    max_vehicles: event.max_vehicles,
  })

  const handleSave = async () => {
    setSaving(true)
    try {
      // Build update payload with only changed fields
      const updates: Record<string, unknown> = {}

      if (formData.name !== event.name) updates.name = formData.name
      if (formData.description !== (event.description || '')) {
        updates.description = formData.description || null
      }
      if (formData.location !== (event.location || '')) {
        updates.location = formData.location || null
      }
      if (formData.max_vehicles !== event.max_vehicles) {
        updates.max_vehicles = formData.max_vehicles
      }

      // Handle dates - convert to ISO if present
      const originalStart = event.scheduled_start
        ? new Date(event.scheduled_start).toISOString().slice(0, 16)
        : ''
      const originalEnd = event.scheduled_end
        ? new Date(event.scheduled_end).toISOString().slice(0, 16)
        : ''

      if (formData.scheduled_start !== originalStart) {
        updates.scheduled_start = formData.scheduled_start
          ? new Date(formData.scheduled_start).toISOString()
          : null
      }
      if (formData.scheduled_end !== originalEnd) {
        updates.scheduled_end = formData.scheduled_end
          ? new Date(formData.scheduled_end).toISOString()
          : null
      }

      if (Object.keys(updates).length === 0) {
        toast.info('No changes', 'No fields were modified')
        onClose()
        return
      }

      const res = await fetch(`${API_BASE}/admin/events/${event.event_id}`, {
        method: 'PATCH',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json', ...getAdminHeaders() },
        body: JSON.stringify(updates),
      })

      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || 'Failed to update event')
      }

      toast.success('Event updated')
      onSave()
    } catch (err) {
      toast.error('Failed to update', err instanceof Error ? err.message : undefined)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-ds-4">
      <div className="absolute inset-0 bg-black/70" onClick={onClose} />
      <div className="relative bg-neutral-800 rounded-ds-lg border border-neutral-700 w-full max-w-lg max-h-[90vh] overflow-y-auto shadow-ds-overlay">
        {/* Header */}
        <div className="sticky top-0 bg-neutral-800 px-ds-6 py-ds-4 border-b border-neutral-700 flex items-center justify-between">
          <h3 className="text-ds-heading text-neutral-50">Edit Event</h3>
          <button onClick={onClose} className="text-neutral-400 hover:text-neutral-50">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Form */}
        <div className="p-ds-6 flex flex-col gap-ds-4">
          <div>
            <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-1">Event Name *</label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              className="w-full px-ds-3 py-ds-2 bg-neutral-700 border border-neutral-600 rounded-ds-md text-neutral-50 focus:outline-none focus:ring-2 focus:ring-accent-500"
            />
          </div>

          <div>
            <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-1">Description</label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              rows={3}
              className="w-full px-ds-3 py-ds-2 bg-neutral-700 border border-neutral-600 rounded-ds-md text-neutral-50 focus:outline-none focus:ring-2 focus:ring-accent-500"
            />
          </div>

          <div>
            <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-1">Location</label>
            <input
              type="text"
              value={formData.location}
              onChange={(e) => setFormData({ ...formData, location: e.target.value })}
              placeholder="e.g., Johnson Valley, CA"
              className="w-full px-ds-3 py-ds-2 bg-neutral-700 border border-neutral-600 rounded-ds-md text-neutral-50 focus:outline-none focus:ring-2 focus:ring-accent-500"
            />
          </div>

          <div className="grid grid-cols-2 gap-ds-4">
            <div>
              <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-1">Start Date</label>
              <input
                type="datetime-local"
                value={formData.scheduled_start}
                onChange={(e) => setFormData({ ...formData, scheduled_start: e.target.value })}
                className="w-full px-ds-3 py-ds-2 bg-neutral-700 border border-neutral-600 rounded-ds-md text-neutral-50 focus:outline-none focus:ring-2 focus:ring-accent-500"
              />
            </div>
            <div>
              <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-1">End Date</label>
              <input
                type="datetime-local"
                value={formData.scheduled_end}
                onChange={(e) => setFormData({ ...formData, scheduled_end: e.target.value })}
                className="w-full px-ds-3 py-ds-2 bg-neutral-700 border border-neutral-600 rounded-ds-md text-neutral-50 focus:outline-none focus:ring-2 focus:ring-accent-500"
              />
            </div>
          </div>

          <div>
            <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-1">Max Vehicles</label>
            <input
              type="number"
              value={formData.max_vehicles}
              onChange={(e) => setFormData({ ...formData, max_vehicles: parseInt(e.target.value) || 50 })}
              min={1}
              max={500}
              className="w-full px-ds-3 py-ds-2 bg-neutral-700 border border-neutral-600 rounded-ds-md text-neutral-50 focus:outline-none focus:ring-2 focus:ring-accent-500"
            />
          </div>
        </div>

        {/* Footer */}
        <div className="sticky bottom-0 bg-neutral-800 px-ds-6 py-ds-4 border-t border-neutral-700 flex justify-end gap-ds-3">
          <button
            onClick={onClose}
            className="px-ds-4 py-ds-2 bg-neutral-700 hover:bg-neutral-600 rounded-ds-md text-neutral-50 font-medium"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={saving || !formData.name.trim()}
            className="px-ds-4 py-ds-2 bg-accent-500 hover:bg-accent-600 disabled:opacity-50 disabled:cursor-not-allowed rounded-ds-md text-white font-medium"
          >
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
        </div>
      </div>
    </div>
  )
}
