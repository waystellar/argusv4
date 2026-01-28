/**
 * Telemetry data tile component
 *
 * FIXED: P2-2 - Parameterized telemetry thresholds
 *
 * HIGH CONTRAST design for outdoor visibility.
 * Includes stale data detection and color-coded thresholds.
 * Thresholds are now configurable via central config or per-tile override.
 */
import { useMemo } from 'react'
import {
  type Threshold,
  type TelemetryThresholds,
  getThreshold,
} from '../../config/telemetryThresholds'

interface TelemetryTileProps {
  label: string
  value: string | number
  unit: string
  small?: boolean
  lastUpdateMs?: number  // Timestamp of last data update
  thresholdKey?: keyof TelemetryThresholds  // Key to look up thresholds
  customThreshold?: Threshold  // FIXED: P2-2 - Allow per-tile threshold override
  vehicleProfile?: string  // FIXED: P2-2 - Vehicle profile for threshold lookup
}

export default function TelemetryTile({
  label,
  value,
  unit,
  small,
  lastUpdateMs,
  thresholdKey,
  customThreshold,
  vehicleProfile,
}: TelemetryTileProps) {
  // Check if data is stale (>5 seconds old)
  const isStale = useMemo(() => {
    if (!lastUpdateMs) return false
    const age = Date.now() - lastUpdateMs
    return age > 5000 // 5 seconds
  }, [lastUpdateMs])

  // FIXED: P2-2 - Get threshold from centralized config with profile and override support
  const threshold = useMemo(() => {
    if (!thresholdKey) return null
    return getThreshold(thresholdKey, vehicleProfile, customThreshold)
  }, [thresholdKey, vehicleProfile, customThreshold])

  // Determine value color based on thresholds
  const valueColorClass = useMemo(() => {
    if (!threshold || typeof value !== 'number') return 'text-white'

    const numValue = typeof value === 'string' ? parseFloat(value) : value
    if (isNaN(numValue)) return 'text-white'

    // Check high thresholds
    if (threshold.danger && numValue >= threshold.danger) {
      return 'telemetry-value-danger'
    }
    if (threshold.warning && numValue >= threshold.warning) {
      return 'telemetry-value-warning'
    }

    // Check low thresholds
    if (threshold.dangerBelow && numValue <= threshold.dangerBelow) {
      return 'telemetry-value-danger'
    }
    if (threshold.warningBelow && numValue <= threshold.warningBelow) {
      return 'telemetry-value-warning'
    }

    return 'text-white'
  }, [value, threshold])

  // Format display value
  const displayValue = useMemo(() => {
    if (value === null || value === undefined || value === '') return '--'
    if (typeof value === 'number') {
      // Round to reasonable precision
      if (Number.isInteger(value)) return value.toString()
      return value.toFixed(1)
    }
    return value
  }, [value])

  return (
    <div className={`telemetry-tile ${small ? 'telemetry-tile-small' : ''} ${isStale ? 'telemetry-tile-stale' : ''}`}>
      {isStale && <span className="stale-indicator">STALE</span>}

      <span className="telemetry-label">{label}</span>

      <div className="flex items-baseline gap-2">
        <span className={`telemetry-value ${valueColorClass}`}>
          {displayValue}
        </span>
        {unit && (
          <span className="text-base text-gray-300 font-medium">{unit}</span>
        )}
      </div>
    </div>
  )
}

/**
 * Skeleton loader for telemetry tile
 */
export function TelemetryTileSkeleton({ small }: { small?: boolean }) {
  return (
    <div className={`telemetry-tile ${small ? 'telemetry-tile-small' : ''}`}>
      <div className="skeleton-text w-16 mb-2"></div>
      <div className="flex items-baseline gap-2">
        <div className={`skeleton ${small ? 'h-6 w-16' : 'h-10 w-24'}`}></div>
        <div className="skeleton-text w-8"></div>
      </div>
    </div>
  )
}

// Re-export Threshold type for consumers
export type { Threshold }
