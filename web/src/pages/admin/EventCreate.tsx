/**
 * Event Creation Wizard
 *
 * UI-18: Migrated to design system tokens (neutral-*, accent-*, status-*, ds-*)
 * Multi-step form to create a new race event with:
 * - Basic info (name, dates)
 * - Course file upload (GPX/KML)
 * - Race classes selection
 * - Vehicle capacity
 */
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useToast } from '../../hooks/useToast'
import { PageHeader } from '../../components/common'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

// Helper to get auth headers for admin API calls
function getAdminHeaders(): HeadersInit {
  const token = localStorage.getItem('admin_token')
  return token ? { Authorization: `Bearer ${token}` } : {}
}

// Common off-road racing classes
const RACE_CLASSES = [
  // Ultra4
  { id: 'ultra4_4400', name: '4400 Unlimited', series: 'Ultra4' },
  { id: 'ultra4_4500', name: '4500 Modified', series: 'Ultra4' },
  { id: 'ultra4_4600', name: '4600 Stock', series: 'Ultra4' },
  { id: 'ultra4_4800', name: '4800 Legends', series: 'Ultra4' },
  { id: 'ultra4_4900', name: '4900 UTV', series: 'Ultra4' },
  // SCORE / Trophy Truck
  { id: 'trophy_truck', name: 'Trophy Truck', series: 'SCORE/BITD' },
  { id: 'trick_truck', name: 'Trick Truck', series: 'SCORE/BITD' },
  { id: 'tt_spec', name: 'Trophy Truck Spec', series: 'SCORE/BITD' },
  { id: 'class_1', name: 'Class 1', series: 'SCORE/BITD' },
  { id: 'class_10', name: 'Class 10', series: 'SCORE/BITD' },
  { id: 'class_1_2_1600', name: 'Class 1/2-1600', series: 'SCORE/BITD' },
  // Truck Classes
  { id: 'class_6100', name: 'Class 6100', series: 'Trucks' },
  { id: 'class_7200', name: 'Class 7200', series: 'Trucks' },
  { id: 'class_8100', name: 'Class 8100', series: 'Trucks' },
  { id: 'unlimited_truck', name: 'Unlimited Truck', series: 'Trucks' },
  { id: 'pro_truck', name: 'Pro Truck', series: 'Trucks' },
  { id: 'spec_truck', name: 'Spec Truck', series: 'Trucks' },
  // UTV
  { id: 'utv_pro', name: 'UTV Pro', series: 'UTV' },
  { id: 'utv_pro_na', name: 'UTV Pro NA', series: 'UTV' },
  { id: 'utv_turbo', name: 'UTV Turbo', series: 'UTV' },
  { id: 'utv_production', name: 'UTV Production', series: 'UTV' },
  { id: 'utv_rally', name: 'UTV Rally', series: 'UTV' },
  // Motorcycles
  { id: 'moto_pro', name: 'Pro Motorcycle', series: 'Moto' },
  { id: 'moto_ironman', name: 'Ironman', series: 'Moto' },
  // Other
  { id: 'buggy', name: 'Buggy', series: 'Other' },
  { id: 'sportsman', name: 'Sportsman', series: 'Other' },
]

interface EventFormData {
  name: string
  description: string
  start_date: string
  end_date: string
  location: string
  classes: string[]
  max_vehicles: number
  course_file: File | null
}

export default function EventCreate() {
  const navigate = useNavigate()
  const toast = useToast()
  const queryClient = useQueryClient()
  const [step, setStep] = useState(1)
  const [formData, setFormData] = useState<EventFormData>({
    name: '',
    description: '',
    start_date: '',
    end_date: '',
    location: '',
    classes: [],
    max_vehicles: 50,
    course_file: null,
  })
  const [errors, setErrors] = useState<Record<string, string>>({})

  const createEvent = useMutation({
    mutationFn: async (data: EventFormData) => {
      // First create the event
      const eventPayload = {
        name: data.name,
        description: data.description,
        scheduled_start: data.start_date ? new Date(data.start_date).toISOString() : null,
        scheduled_end: data.end_date ? new Date(data.end_date).toISOString() : null,
        location: data.location,
        classes: data.classes,
        max_vehicles: data.max_vehicles,
      }

      // Log for debugging
      const url = `${API_BASE}/admin/events`
      console.log('[EventCreate] ====== CREATE EVENT REQUEST ======')
      console.log('[EventCreate] URL:', url)
      console.log('[EventCreate] Method: POST')
      console.log('[EventCreate] Payload:', JSON.stringify(eventPayload, null, 2))

      const res = await fetch(url, {
        method: 'POST',
        credentials: 'include',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          ...getAdminHeaders(),
        },
        body: JSON.stringify(eventPayload),
      })

      console.log('[EventCreate] ====== RESPONSE ======')
      console.log('[EventCreate] Status:', res.status, res.statusText)
      console.log('[EventCreate] Headers:', Object.fromEntries(res.headers.entries()))
      console.log('[EventCreate] URL after redirect:', res.url)

      if (!res.ok) {
        let errorMessage = 'Failed to create event'
        try {
          const error = await res.json()
          errorMessage = error.detail || errorMessage
        } catch {
          // If response isn't JSON, use status text
          errorMessage = `${res.status}: ${res.statusText}`
        }
        console.error('[EventCreate] Event creation failed:', errorMessage)
        throw new Error(errorMessage)
      }

      const event = await res.json()
      console.log('[EventCreate] Event created:', event.event_id)

      // If there's a course file, upload it
      if (data.course_file) {
        console.log('[EventCreate] Uploading course file:', data.course_file.name)
        const formData = new FormData()
        formData.append('file', data.course_file)

        const courseRes = await fetch(`${API_BASE}/admin/events/${event.event_id}/course`, {
          method: 'POST',
          credentials: 'include',
          headers: getAdminHeaders(),
          body: formData,
        })

        console.log('[EventCreate] Course upload response:', courseRes.status, courseRes.statusText)

        if (!courseRes.ok) {
          let courseError = 'Failed to upload course file'
          try {
            const error = await courseRes.json()
            courseError = error.detail || courseError
          } catch {
            courseError = `${courseRes.status}: ${courseRes.statusText}`
          }
          // Log but don't fail - event was created successfully
          console.warn('[EventCreate] Course upload failed:', courseError)
          // Still return the event, but with a warning
          return { ...event, courseUploadWarning: courseError }
        }

        const courseResult = await courseRes.json()
        console.log('[EventCreate] Course upload success:', courseResult)
      }

      return event
    },
    onSuccess: (event) => {
      // Invalidate queries so EventDetail gets fresh data including course
      queryClient.invalidateQueries({ queryKey: ['event', event.event_id] })
      queryClient.invalidateQueries({ queryKey: ['course', event.event_id] })
      queryClient.invalidateQueries({ queryKey: ['events'] })

      if (event.courseUploadWarning) {
        toast.warning('Event created', `Course upload failed: ${event.courseUploadWarning}`)
      } else {
        toast.success('Event created', `${event.name} is ready for vehicle registration`)
      }
      navigate(`/admin/events/${event.event_id}`)
    },
    onError: (error: Error) => {
      toast.error('Failed to create event', error.message)
    },
  })

  const validateStep = (stepNum: number): boolean => {
    const newErrors: Record<string, string> = {}

    if (stepNum === 1) {
      if (!formData.name.trim()) {
        newErrors.name = 'Event name is required'
      } else if (formData.name.length < 3) {
        newErrors.name = 'Event name must be at least 3 characters'
      }
      if (!formData.start_date) {
        newErrors.start_date = 'Start date is required'
      }
      if (formData.end_date && formData.start_date) {
        if (new Date(formData.end_date) < new Date(formData.start_date)) {
          newErrors.end_date = 'End date must be after start date'
        }
      }
    }

    if (stepNum === 2) {
      if (formData.classes.length === 0) {
        newErrors.classes = 'Select at least one race class'
      }
    }

    if (stepNum === 3) {
      if (formData.max_vehicles < 1 || formData.max_vehicles > 500) {
        newErrors.max_vehicles = 'Max vehicles must be between 1 and 500'
      }
    }

    setErrors(newErrors)
    return Object.keys(newErrors).length === 0
  }

  const nextStep = () => {
    if (validateStep(step)) {
      setStep(step + 1)
    }
  }

  const prevStep = () => {
    setStep(step - 1)
  }

  const handleSubmit = () => {
    if (validateStep(step)) {
      createEvent.mutate(formData)
    }
  }

  const toggleClass = (classId: string) => {
    setFormData((prev) => ({
      ...prev,
      classes: prev.classes.includes(classId)
        ? prev.classes.filter((c) => c !== classId)
        : [...prev.classes, classId],
    }))
  }

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      const validExtensions = ['.gpx', '.kml', '.kmz']
      const ext = file.name.toLowerCase().slice(file.name.lastIndexOf('.'))
      if (!validExtensions.includes(ext)) {
        setErrors({ ...errors, course_file: 'Please upload a .gpx, .kml, or .kmz file' })
        return
      }
      setFormData({ ...formData, course_file: file })
      setErrors({ ...errors, course_file: '' })
    }
  }

  // Group classes by series
  const classesBySeries = RACE_CLASSES.reduce((acc, cls) => {
    if (!acc[cls.series]) acc[cls.series] = []
    acc[cls.series].push(cls)
    return acc
  }, {} as Record<string, typeof RACE_CLASSES>)

  /** Shared input class builder */
  const inputClasses = (hasError?: boolean) =>
    `w-full px-ds-4 py-ds-3 bg-neutral-800 border ${
      hasError ? 'border-status-error' : 'border-neutral-700'
    } rounded-ds-lg text-neutral-50 placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-accent-500 transition-colors duration-ds-fast`

  return (
    <div className="min-h-screen bg-neutral-950">
      <PageHeader
        title="Create Event"
        subtitle={`Step ${step} of 3`}
        backTo="/admin"
        backLabel="Back to admin"
      />

      {/* Progress Bar */}
      <div className="bg-neutral-900 border-b border-neutral-800">
        <div className="max-w-3xl mx-auto px-ds-4 sm:px-ds-6">
          <div className="flex" role="progressbar" aria-valuenow={step} aria-valuemin={1} aria-valuemax={3} aria-label={`Step ${step} of 3`}>
            {[1, 2, 3].map((s) => (
              <div
                key={s}
                className={`flex-1 h-1 rounded-full ${s <= step ? 'bg-accent-500' : 'bg-neutral-800'} ${
                  s < 3 ? 'mr-ds-1' : ''
                }`}
              />
            ))}
          </div>
        </div>
      </div>

      <main className="max-w-3xl mx-auto px-ds-4 py-ds-8 sm:px-ds-6">
        {/* Step 1: Basic Info */}
        {step === 1 && (
          <div className="space-y-ds-6">
            <div>
              <h2 className="text-ds-title font-bold text-neutral-50 mb-ds-2">Event Details</h2>
              <p className="text-neutral-400 text-ds-body-sm">Basic information about your race event</p>
            </div>

            <div className="bg-neutral-900 rounded-ds-xl border border-neutral-800 p-ds-6 space-y-ds-6">
              <div>
                <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-2">
                  Event Name *
                </label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={(e) => {
                    const value = e.target.value.slice(0, 100)
                    setFormData({ ...formData, name: value })
                    if (errors.name && value.trim()) {
                      setErrors({ ...errors, name: '' })
                    }
                  }}
                  placeholder="e.g., King of the Hammers 2026"
                  className={inputClasses(!!errors.name)}
                />
                <div className="flex justify-between mt-ds-1">
                  {errors.name ? (
                    <p className="text-ds-body-sm text-status-error" role="alert">{errors.name}</p>
                  ) : (
                    <span />
                  )}
                  <span className={`text-ds-caption ${formData.name.length > 80 ? 'text-status-warning' : 'text-neutral-500'}`}>
                    {formData.name.length}/100
                  </span>
                </div>
              </div>

              <div>
                <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-2">
                  Description
                </label>
                <textarea
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value.slice(0, 500) })}
                  placeholder="Brief description of the event..."
                  rows={3}
                  className={inputClasses()}
                />
                <div className="flex justify-end mt-ds-1">
                  <span className={`text-ds-caption ${formData.description.length > 400 ? 'text-status-warning' : 'text-neutral-500'}`}>
                    {formData.description.length}/500
                  </span>
                </div>
              </div>

              <div>
                <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-2">
                  Location
                </label>
                <input
                  type="text"
                  value={formData.location}
                  onChange={(e) => setFormData({ ...formData, location: e.target.value })}
                  placeholder="e.g., Johnson Valley, CA"
                  className={inputClasses()}
                />
              </div>

              <div className="grid grid-cols-2 gap-ds-4">
                <div>
                  <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-2">
                    Start Date *
                  </label>
                  <input
                    type="datetime-local"
                    value={formData.start_date}
                    onChange={(e) => setFormData({ ...formData, start_date: e.target.value })}
                    className={inputClasses(!!errors.start_date)}
                  />
                  {errors.start_date && (
                    <p className="mt-ds-1 text-ds-body-sm text-status-error" role="alert">{errors.start_date}</p>
                  )}
                </div>
                <div>
                  <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-2">
                    End Date
                  </label>
                  <input
                    type="datetime-local"
                    value={formData.end_date}
                    min={formData.start_date || undefined}
                    onChange={(e) => {
                      setFormData({ ...formData, end_date: e.target.value })
                      if (errors.end_date) setErrors({ ...errors, end_date: '' })
                    }}
                    className={inputClasses(!!errors.end_date)}
                  />
                  {errors.end_date && (
                    <p className="mt-ds-1 text-ds-body-sm text-status-error" role="alert">{errors.end_date}</p>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Step 2: Race Classes */}
        {step === 2 && (
          <div className="space-y-ds-6">
            <div>
              <h2 className="text-ds-title font-bold text-neutral-50 mb-ds-2">Race Classes</h2>
              <p className="text-neutral-400 text-ds-body-sm">Select the classes competing in this event</p>
            </div>

            {errors.classes && (
              <div className="p-ds-3 bg-status-error/10 border border-status-error/30 rounded-ds-lg text-status-error text-ds-body-sm" role="alert">
                {errors.classes}
              </div>
            )}

            <div className="space-y-ds-4 max-h-[60vh] overflow-y-auto pr-ds-2">
              {Object.entries(classesBySeries).map(([series, classes]) => (
                <div key={series} className="bg-neutral-900 rounded-ds-xl border border-neutral-800 overflow-hidden">
                  <div className="px-ds-4 py-ds-3 bg-neutral-800/50 border-b border-neutral-800">
                    <h3 className="font-medium text-neutral-50">{series}</h3>
                  </div>
                  <div className="p-ds-4 grid grid-cols-2 sm:grid-cols-3 gap-ds-2">
                    {classes.map((cls) => (
                      <button
                        key={cls.id}
                        onClick={() => toggleClass(cls.id)}
                        className={`px-ds-3 py-ds-2 text-ds-body-sm rounded-ds-lg border transition-colors duration-ds-fast text-left focus:outline-none focus:ring-2 focus:ring-accent-500 ${
                          formData.classes.includes(cls.id)
                            ? 'bg-accent-600 border-accent-500 text-white'
                            : 'bg-neutral-800 border-neutral-700 text-neutral-300 hover:border-neutral-600'
                        }`}
                      >
                        {cls.name}
                      </button>
                    ))}
                  </div>
                </div>
              ))}
            </div>

            <div className="text-ds-body-sm text-neutral-400">
              Selected: {formData.classes.length} class{formData.classes.length !== 1 ? 'es' : ''}
            </div>
          </div>
        )}

        {/* Step 3: Course & Capacity */}
        {step === 3 && (
          <div className="space-y-ds-6 max-h-[60vh] overflow-y-auto pr-ds-2">
            <div>
              <h2 className="text-ds-title font-bold text-neutral-50 mb-ds-2">Course & Capacity</h2>
              <p className="text-neutral-400 text-ds-body-sm">Upload course file and set vehicle limits</p>
            </div>

            <div className="bg-neutral-900 rounded-ds-xl border border-neutral-800 p-ds-6 space-y-ds-6">
              <div>
                <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-2">
                  Course File (Optional)
                </label>
                <div
                  className={`relative border-2 border-dashed rounded-ds-lg p-ds-8 text-center transition-colors duration-ds-fast ${
                    formData.course_file
                      ? 'border-status-success bg-status-success/10'
                      : 'border-neutral-700 hover:border-neutral-600'
                  }`}
                >
                  {formData.course_file ? (
                    <div>
                      <svg className="w-8 h-8 mx-auto mb-ds-2 text-status-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                      </svg>
                      <p className="text-neutral-50 font-medium">{formData.course_file.name}</p>
                      <p className="text-ds-body-sm text-neutral-400 mt-ds-1">
                        {(formData.course_file.size / 1024).toFixed(1)} KB
                      </p>
                      <button
                        onClick={() => setFormData({ ...formData, course_file: null })}
                        className="mt-ds-3 text-ds-body-sm text-status-error hover:text-status-error/80 transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500 rounded-ds-sm"
                      >
                        Remove
                      </button>
                    </div>
                  ) : (
                    <div>
                      <svg className="w-8 h-8 mx-auto mb-ds-2 text-neutral-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                      </svg>
                      <p className="text-neutral-300 mb-ds-2">Drop a course file here or click to browse</p>
                      <p className="text-ds-body-sm text-neutral-500">Accepts .gpx, .kml, .kmz</p>
                      <input
                        type="file"
                        accept=".gpx,.kml,.kmz"
                        onChange={handleFileChange}
                        className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                        aria-label="Upload course file"
                      />
                    </div>
                  )}
                </div>
                {errors.course_file && (
                  <p className="mt-ds-1 text-ds-body-sm text-status-error" role="alert">{errors.course_file}</p>
                )}
                <p className="mt-ds-2 text-ds-caption text-neutral-500">
                  The course file will be used to generate checkpoints and calculate distances.
                </p>
              </div>

              <div>
                <label className="block text-ds-body-sm font-medium text-neutral-300 mb-ds-2">
                  Maximum Vehicles
                </label>
                <input
                  type="number"
                  value={formData.max_vehicles}
                  onChange={(e) => setFormData({ ...formData, max_vehicles: parseInt(e.target.value) || 50 })}
                  min={1}
                  max={500}
                  className={inputClasses()}
                />
                <p className="mt-ds-1 text-ds-body-sm text-neutral-500">
                  Maximum number of vehicles that can register for this event
                </p>
              </div>
            </div>

            {/* Summary */}
            <div className="bg-accent-500/10 rounded-ds-xl border border-accent-500/20 p-ds-6">
              <h3 className="text-lg font-semibold text-neutral-50 mb-ds-4">Event Summary</h3>
              <dl className="space-y-ds-2 text-ds-body-sm">
                <div className="flex justify-between">
                  <dt className="text-neutral-400">Name</dt>
                  <dd className="text-neutral-50 font-medium">{formData.name}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-neutral-400">Start Date</dt>
                  <dd className="text-neutral-50">
                    {formData.start_date
                      ? new Date(formData.start_date).toLocaleDateString('en-US', {
                          weekday: 'short',
                          month: 'short',
                          day: 'numeric',
                          year: 'numeric',
                        })
                      : 'TBD'}
                  </dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-neutral-400">Classes</dt>
                  <dd className="text-neutral-50">{formData.classes.length} selected</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-neutral-400">Max Vehicles</dt>
                  <dd className="text-neutral-50">{formData.max_vehicles}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-neutral-400">Course File</dt>
                  <dd className="text-neutral-50">{formData.course_file ? 'Uploaded' : 'None'}</dd>
                </div>
              </dl>
            </div>
          </div>
        )}

        {/* Navigation Buttons */}
        <div className="flex gap-ds-4 mt-ds-8">
          {step > 1 && (
            <button
              onClick={prevStep}
              className="flex-1 py-ds-3 bg-neutral-800 hover:bg-neutral-700 text-white font-medium rounded-ds-lg transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500"
            >
              Back
            </button>
          )}
          {step < 3 ? (
            <button
              onClick={nextStep}
              className="flex-1 py-ds-3 bg-accent-600 hover:bg-accent-500 text-white font-medium rounded-ds-lg transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500"
            >
              Continue
            </button>
          ) : (
            <button
              onClick={handleSubmit}
              disabled={createEvent.isPending}
              className="flex-1 py-ds-3 bg-status-success hover:bg-status-success/90 disabled:bg-neutral-700 disabled:text-neutral-400 disabled:cursor-wait text-white font-medium rounded-ds-lg transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500"
            >
              {createEvent.isPending ? 'Creating...' : 'Create Event'}
            </button>
          )}
        </div>

        {createEvent.isError && (
          <div className="mt-ds-4 p-ds-4 bg-status-error/10 border border-status-error/30 rounded-ds-lg text-status-error text-ds-body-sm" role="alert">
            {createEvent.error?.message || 'Failed to create event'}
          </div>
        )}
      </main>
    </div>
  )
}
