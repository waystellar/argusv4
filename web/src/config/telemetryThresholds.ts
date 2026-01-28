/**
 * Telemetry threshold configuration
 *
 * FIXED: P2-2 - Parameterized telemetry thresholds
 * PR-2 SCHEMA: Canonical field names aligned across Edge/Cloud/Web
 *
 * These thresholds define warning and danger levels for telemetry values.
 * Teams can customize these per-vehicle or use defaults.
 */

export interface Threshold {
  warning?: number      // Value at which to show warning color
  danger?: number       // Value at which to show danger color
  warningBelow?: number // For values that are bad when LOW (e.g., oil pressure)
  dangerBelow?: number
}

// PR-2 SCHEMA: Canonical field names from cloud schema
export interface TelemetryThresholds {
  rpm: Threshold
  gear: Threshold
  throttle_pct: Threshold
  coolant_temp_c: Threshold    // Canonical: Celsius
  oil_pressure_psi: Threshold  // Canonical: PSI
  fuel_pressure_psi: Threshold // Canonical: PSI
  speed_mph: Threshold         // CAN-reported speed
  heart_rate: Threshold
  heart_rate_zone: Threshold
  // NOTE: Suspension removed - not currently in use
}

/**
 * Default thresholds for common racing telemetry.
 * These are conservative defaults suitable for most off-road vehicles.
 * PR-2 SCHEMA: Uses canonical field names
 */
export const DEFAULT_THRESHOLDS: TelemetryThresholds = {
  rpm: {
    warning: 6500,
    danger: 7500,
  },
  gear: {
    // No thresholds - informational only
  },
  throttle_pct: {
    // No thresholds - full range is normal
  },
  coolant_temp_c: {
    warning: 100,  // °C
    danger: 110,
  },
  oil_pressure_psi: {
    warningBelow: 30,  // psi
    dangerBelow: 20,
  },
  fuel_pressure_psi: {
    warningBelow: 40,  // psi
    dangerBelow: 30,
  },
  speed_mph: {
    // No thresholds - full range is normal
  },
  heart_rate: {
    warning: 170,  // bpm
    danger: 190,
  },
  heart_rate_zone: {
    warning: 4,  // Zone 4+
    danger: 5,   // Zone 5
  },
  // NOTE: Suspension removed - not currently in use
}

/**
 * Preset threshold profiles for different vehicle types.
 * Teams can select a profile that matches their vehicle.
 * PR-2 SCHEMA: Uses canonical field names
 */
export const THRESHOLD_PROFILES: Record<string, Partial<TelemetryThresholds>> = {
  // High-performance desert truck
  trophy_truck: {
    rpm: { warning: 7000, danger: 8000 },
    coolant_temp_c: { warning: 105, danger: 115 },
    oil_pressure_psi: { warningBelow: 25, dangerBelow: 15 },
  },
  // UTV / Side-by-side
  utv: {
    rpm: { warning: 8000, danger: 9000 },
    coolant_temp_c: { warning: 95, danger: 105 },
    oil_pressure_psi: { warningBelow: 20, dangerBelow: 10 },
  },
  // Stock class vehicles
  stock: {
    rpm: { warning: 5500, danger: 6500 },
    coolant_temp_c: { warning: 95, danger: 105 },
    oil_pressure_psi: { warningBelow: 35, dangerBelow: 25 },
  },
  // Motorcycles / ATVs
  moto: {
    rpm: { warning: 10000, danger: 12000 },
    coolant_temp_c: { warning: 90, danger: 100 },
    heart_rate: { warning: 180, danger: 200 },
  },
}

/**
 * Get thresholds for a specific key, with optional override.
 * Merges: custom override > vehicle profile > defaults
 */
export function getThreshold(
  key: keyof TelemetryThresholds,
  profileName?: string,
  customOverride?: Threshold
): Threshold {
  // Start with default
  let threshold = DEFAULT_THRESHOLDS[key] || {}

  // Apply profile if specified
  if (profileName && THRESHOLD_PROFILES[profileName]) {
    const profile = THRESHOLD_PROFILES[profileName]
    if (profile[key]) {
      threshold = { ...threshold, ...profile[key] }
    }
  }

  // Apply custom override
  if (customOverride) {
    threshold = { ...threshold, ...customOverride }
  }

  return threshold
}

/**
 * Local storage key for custom thresholds
 */
const CUSTOM_THRESHOLDS_KEY = 'argus_telemetry_thresholds'

/**
 * Save custom thresholds to local storage
 */
export function saveCustomThresholds(thresholds: Partial<TelemetryThresholds>): void {
  try {
    localStorage.setItem(CUSTOM_THRESHOLDS_KEY, JSON.stringify(thresholds))
  } catch (e) {
    console.warn('Failed to save custom thresholds:', e)
  }
}

/**
 * Load custom thresholds from local storage
 */
export function loadCustomThresholds(): Partial<TelemetryThresholds> | null {
  try {
    const stored = localStorage.getItem(CUSTOM_THRESHOLDS_KEY)
    if (stored) {
      return JSON.parse(stored)
    }
  } catch (e) {
    console.warn('Failed to load custom thresholds:', e)
  }
  return null
}
