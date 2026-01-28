/**
 * Permission toggle for a single telemetry field
 *
 * UI-10 Update: Refactored to use design system tokens
 */

interface PermissionToggleProps {
  fieldName: string
  level: string
  onChange: (level: string) => void
}

// FIXED: Field labels match backend field names (Issue #5 from audit)
const FIELD_LABELS: Record<string, string> = {
  // GPS fields
  lat: 'Latitude',
  lon: 'Longitude',
  speed_mps: 'Speed',
  heading_deg: 'Heading',
  // Engine telemetry
  rpm: 'RPM',
  gear: 'Gear',
  coolant_temp: 'Coolant Temperature',
  oil_pressure: 'Oil Pressure',
  fuel_pressure: 'Fuel Pressure',
  throttle_pct: 'Throttle Position',
  // NOTE: Suspension labels removed - not currently in use
  // Biometrics
  heart_rate: 'Heart Rate',
  heart_rate_zone: 'HR Zone',
}

const LEVELS = [
  { value: 'public', label: 'Public', color: 'bg-status-success' },
  { value: 'premium', label: 'Premium', color: 'bg-status-warning' },
  { value: 'private', label: 'Private', color: 'bg-status-error' },
  { value: 'hidden', label: 'Hidden', color: 'bg-neutral-600' },
]

export default function PermissionToggle({ fieldName, level, onChange }: PermissionToggleProps) {
  const label = FIELD_LABELS[fieldName] || fieldName.replace(/_/g, ' ')

  return (
    <div className="flex items-center justify-between p-ds-3">
      <div className="flex-1">
        <div className="text-ds-body font-medium text-neutral-50">{label}</div>
      </div>

      <div className="flex gap-ds-1">
        {LEVELS.map((lvl) => (
          <button
            key={lvl.value}
            onClick={() => onChange(lvl.value)}
            className={`px-ds-3 py-ds-1 text-ds-caption rounded-ds-md transition-colors duration-ds-fast ${
              level === lvl.value
                ? `${lvl.color} text-white`
                : 'bg-neutral-800 text-neutral-400 hover:bg-neutral-700'
            }`}
          >
            {lvl.label}
          </button>
        ))}
      </div>
    </div>
  )
}
