/**
 * Telemetry Sharing Policy Component
 *
 * Allows pit crew to configure what telemetry data is shared with:
 * - Production team (control room)
 * - Fans (public viewers)
 *
 * Server-side enforcement ensures fans can only see what's in allow_fans,
 * even if they try to request other fields.
 *
 * UI-5 Update: Refactored to use design system tokens and components
 */
import { useState, useEffect } from 'react'
import { Alert } from '../ui'

interface TelemetrySharingPolicyProps {
  token: string
  eventId: string | null
}

interface PolicyData {
  vehicle_id: string
  event_id: string
  allow_production: string[]
  allow_fans: string[]
  available_fields: string[]
  field_groups: Record<string, string[]>
  updated_at: string | null
}

// Human-readable labels for telemetry fields
const FIELD_LABELS: Record<string, string> = {
  lat: 'Latitude',
  lon: 'Longitude',
  speed_mps: 'Speed (GPS)',
  heading_deg: 'Heading',
  altitude_m: 'Altitude',
  rpm: 'Engine RPM',
  gear: 'Gear',
  speed_mph: 'Speed (CAN)',
  throttle_pct: 'Throttle %',
  coolant_temp_c: 'Coolant Temp',
  oil_pressure_psi: 'Oil Pressure',
  fuel_pressure_psi: 'Fuel Pressure',
  heart_rate: 'Heart Rate',
  heart_rate_zone: 'HR Zone',
}

// Group labels
const GROUP_LABELS: Record<string, string> = {
  gps: 'GPS & Position',
  engine_basic: 'Engine (Basic)',
  engine_advanced: 'Engine (Advanced)',
  biometrics: 'Driver Biometrics',
}

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

export default function TelemetrySharingPolicy({ token, eventId }: TelemetrySharingPolicyProps) {
  const [policy, setPolicy] = useState<PolicyData | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  // Local state for editing
  const [allowProduction, setAllowProduction] = useState<Set<string>>(new Set())
  const [allowFans, setAllowFans] = useState<Set<string>>(new Set())

  useEffect(() => {
    if (eventId && token) {
      fetchPolicy()
    } else {
      setIsLoading(false)
    }
  }, [eventId, token])

  async function fetchPolicy() {
    setIsLoading(true)
    setError(null)

    try {
      const res = await fetch(`${API_BASE}/team/sharing-policy`, {
        headers: { Authorization: `Bearer ${token}` },
      })

      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || 'Failed to fetch policy')
      }

      const data: PolicyData = await res.json()
      setPolicy(data)
      setAllowProduction(new Set(data.allow_production))
      setAllowFans(new Set(data.allow_fans))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load policy')
    } finally {
      setIsLoading(false)
    }
  }

  async function savePolicy() {
    setIsSaving(true)
    setError(null)
    setSuccess(null)

    try {
      const res = await fetch(`${API_BASE}/team/sharing-policy`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          allow_production: Array.from(allowProduction),
          allow_fans: Array.from(allowFans),
        }),
      })

      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.detail || 'Failed to save policy')
      }

      const result = await res.json()
      // Update local state with server response (in case of constraint adjustments)
      setAllowProduction(new Set(result.allow_production))
      setAllowFans(new Set(result.allow_fans))
      setSuccess('Sharing policy updated')
      setTimeout(() => setSuccess(null), 3000)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save')
    } finally {
      setIsSaving(false)
    }
  }

  function toggleProduction(field: string) {
    const newSet = new Set(allowProduction)
    if (newSet.has(field)) {
      newSet.delete(field)
      // Also remove from fans if it was there
      const newFans = new Set(allowFans)
      newFans.delete(field)
      setAllowFans(newFans)
    } else {
      newSet.add(field)
    }
    setAllowProduction(newSet)
  }

  function toggleFans(field: string) {
    // Can only enable for fans if it's enabled for production
    if (!allowProduction.has(field)) return

    const newSet = new Set(allowFans)
    if (newSet.has(field)) {
      newSet.delete(field)
    } else {
      newSet.add(field)
    }
    setAllowFans(newSet)
  }

  function selectPreset(preset: 'minimal' | 'basic' | 'full' | 'none') {
    const gps = ['lat', 'lon', 'speed_mps', 'heading_deg']
    const engineBasic = ['rpm', 'gear', 'speed_mph']
    const engineAdvanced = ['throttle_pct', 'coolant_temp_c', 'oil_pressure_psi', 'fuel_pressure_psi']
    const biometrics = ['heart_rate', 'heart_rate_zone']

    switch (preset) {
      case 'none':
        setAllowProduction(new Set())
        setAllowFans(new Set())
        break
      case 'minimal':
        setAllowProduction(new Set(gps))
        setAllowFans(new Set(gps))
        break
      case 'basic':
        setAllowProduction(new Set([...gps, ...engineBasic]))
        setAllowFans(new Set(gps))
        break
      case 'full':
        setAllowProduction(new Set([...gps, ...engineBasic, ...engineAdvanced, ...biometrics]))
        setAllowFans(new Set([...gps, ...engineBasic]))
        break
    }
  }

  if (!eventId) {
    return (
      <Alert variant="warning">
        Register for an event to configure telemetry sharing
      </Alert>
    )
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center p-ds-8">
        <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-accent-500" />
      </div>
    )
  }

  if (error && !policy) {
    return (
      <Alert variant="error">{error}</Alert>
    )
  }

  return (
    <div className="space-y-ds-4">
      {/* Header with description */}
      <div className="bg-accent-600/10 border border-accent-500/30 rounded-ds-lg p-ds-3">
        <p className="text-ds-body-sm text-accent-300">
          Control what telemetry data is visible to the production team (control room) and fans.
          Fans can only see fields that are also enabled for production.
        </p>
      </div>

      {/* Status messages */}
      {error && <Alert variant="error">{error}</Alert>}
      {success && <Alert variant="success">{success}</Alert>}

      {/* Preset buttons */}
      <div className="flex flex-wrap gap-ds-2">
        <span className="text-ds-caption text-neutral-500 self-center mr-ds-2">Presets:</span>
        <button
          onClick={() => selectPreset('none')}
          className="px-ds-3 py-ds-1 text-ds-caption rounded-ds-full bg-neutral-800 hover:bg-neutral-700 text-neutral-300 transition-colors duration-ds-fast"
        >
          None
        </button>
        <button
          onClick={() => selectPreset('minimal')}
          className="px-ds-3 py-ds-1 text-ds-caption rounded-ds-full bg-neutral-800 hover:bg-neutral-700 text-neutral-300 transition-colors duration-ds-fast"
        >
          GPS Only
        </button>
        <button
          onClick={() => selectPreset('basic')}
          className="px-ds-3 py-ds-1 text-ds-caption rounded-ds-full bg-neutral-800 hover:bg-neutral-700 text-neutral-300 transition-colors duration-ds-fast"
        >
          Basic
        </button>
        <button
          onClick={() => selectPreset('full')}
          className="px-ds-3 py-ds-1 text-ds-caption rounded-ds-full bg-neutral-800 hover:bg-neutral-700 text-neutral-300 transition-colors duration-ds-fast"
        >
          Full
        </button>
      </div>

      {/* Field groups */}
      {policy?.field_groups && Object.entries(policy.field_groups).map(([groupKey, fields]) => (
        <div key={groupKey} className="bg-neutral-900 rounded-ds-lg overflow-hidden">
          <div className="px-ds-4 py-ds-2 bg-neutral-800/50 border-b border-neutral-700">
            <h3 className="text-ds-body-sm font-medium text-neutral-300">
              {GROUP_LABELS[groupKey] || groupKey}
            </h3>
          </div>
          <div className="divide-y divide-neutral-800/50">
            {fields.map((field) => (
              <div key={field} className="px-ds-4 py-ds-3 flex items-center justify-between">
                <span className="text-ds-body-sm text-neutral-200">
                  {FIELD_LABELS[field] || field}
                </span>
                <div className="flex items-center gap-ds-4">
                  {/* Production toggle */}
                  <label className="flex items-center gap-ds-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={allowProduction.has(field)}
                      onChange={() => toggleProduction(field)}
                      className="w-4 h-4 rounded border-neutral-600 bg-neutral-700 text-accent-600 focus:ring-accent-500 focus:ring-offset-neutral-900"
                    />
                    <span className="text-ds-caption text-neutral-400">Production</span>
                  </label>

                  {/* Fans toggle */}
                  <label className={`flex items-center gap-ds-2 ${
                    allowProduction.has(field) ? 'cursor-pointer' : 'cursor-not-allowed opacity-50'
                  }`}>
                    <input
                      type="checkbox"
                      checked={allowFans.has(field)}
                      onChange={() => toggleFans(field)}
                      disabled={!allowProduction.has(field)}
                      className="w-4 h-4 rounded border-neutral-600 bg-neutral-700 text-status-success focus:ring-green-500 focus:ring-offset-neutral-900"
                    />
                    <span className="text-ds-caption text-neutral-400">Fans</span>
                  </label>
                </div>
              </div>
            ))}
          </div>
        </div>
      ))}

      {/* Save button */}
      <button
        onClick={savePolicy}
        disabled={isSaving}
        className="w-full py-ds-3 rounded-ds-lg bg-accent-600 hover:bg-accent-500 disabled:bg-accent-800 text-white font-medium transition-colors duration-ds-fast flex items-center justify-center gap-ds-2"
      >
        {isSaving ? (
          <>
            <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
            Saving...
          </>
        ) : (
          'Save Sharing Policy'
        )}
      </button>

      {/* Info about defaults */}
      <div className="text-ds-caption text-neutral-500 text-center">
        If no policy is set, fans see nothing and production sees GPS only (safe defaults).
      </div>
    </div>
  )
}
