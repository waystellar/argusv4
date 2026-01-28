/**
 * Tracker Tab - Vehicle list with real-time GPS data
 *
 * Features:
 * - List of all vehicles with position data
 * - Favorites at top
 * - Speed and last update time
 * - Stale data indicators
 * - Click to center on map
 *
 * UI-4 Update: Refactored to use design system tokens and components
 */
import { useState, useMemo } from 'react'
import { FavoriteButton } from '../../hooks/useFavorites'
import { Badge, EmptyState as DSEmptyState } from '../ui'
import type { TabProps } from './types'
import type { VehiclePosition } from '../../api/client'

// Stale threshold for position data
const STALE_THRESHOLD_MS = 30000 // 30 seconds

type SortOption = 'favorites' | 'number' | 'speed' | 'recent'

const SORT_OPTIONS: { id: SortOption; label: string }[] = [
  { id: 'favorites', label: 'Favorites First' },
  { id: 'number', label: 'Vehicle #' },
  { id: 'speed', label: 'Speed' },
  { id: 'recent', label: 'Most Recent' },
]

export default function TrackerTab({
  eventId: _eventId,
  positions,
  favorites,
  onToggleFavorite,
  onVehicleSelect,
  selectedVehicleId,
  isConnected,
}: TabProps) {
  const [sortBy, setSortBy] = useState<SortOption>('favorites')
  const [searchQuery, setSearchQuery] = useState('')

  // Filter and sort vehicles
  const sortedVehicles = useMemo(() => {
    let filtered = positions

    // Search filter
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase().trim()
      filtered = filtered.filter((v) =>
        v.vehicle_number.toLowerCase().includes(query) ||
        v.team_name.toLowerCase().includes(query)
      )
    }

    // Sort
    return [...filtered].sort((a, b) => {
      switch (sortBy) {
        case 'favorites': {
          const aFav = favorites.has(a.vehicle_id) ? 0 : 1
          const bFav = favorites.has(b.vehicle_id) ? 0 : 1
          if (aFav !== bFav) return aFav - bFav
          return parseInt(a.vehicle_number) - parseInt(b.vehicle_number)
        }
        case 'number':
          return parseInt(a.vehicle_number) - parseInt(b.vehicle_number)
        case 'speed':
          return (b.speed_mps || 0) - (a.speed_mps || 0)
        case 'recent':
          return (b.last_update_ms || 0) - (a.last_update_ms || 0)
        default:
          return 0
      }
    })
  }, [positions, favorites, sortBy, searchQuery])

  const staleCount = useMemo(() => {
    const now = Date.now()
    return positions.filter((p) => p.last_update_ms && now - p.last_update_ms > STALE_THRESHOLD_MS).length
  }, [positions])

  return (
    <div className="flex flex-col h-full bg-neutral-950">
      {/* Header with search and sort */}
      <div className="p-ds-4 bg-neutral-900 border-b border-neutral-800 space-y-ds-3">
        {/* Search input */}
        <div className="relative">
          <div className="absolute left-ds-3 top-1/2 -translate-y-1/2 pointer-events-none">
            <svg className="w-5 h-5 text-neutral-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search vehicle # or team..."
            className="w-full min-h-[44px] pl-10 pr-10 py-ds-2 bg-neutral-800 border border-neutral-700 rounded-ds-lg text-neutral-50 text-ds-body placeholder-neutral-500 focus:outline-none focus:border-accent-500 focus:ring-1 focus:ring-accent-500/50 transition-colors duration-ds-fast"
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              className="absolute right-ds-3 top-1/2 -translate-y-1/2 w-6 h-6 flex items-center justify-center text-neutral-500 hover:text-neutral-300 transition-colors duration-ds-fast"
              aria-label="Clear search"
            >
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          )}
        </div>

        {/* Sort options */}
        <div className="flex gap-ds-2 overflow-x-auto pb-ds-1 -mx-ds-1 px-ds-1">
          {SORT_OPTIONS.map((opt) => (
            <button
              key={opt.id}
              onClick={() => setSortBy(opt.id)}
              className={`shrink-0 min-h-[36px] px-ds-4 py-ds-1 rounded-ds-full text-ds-body-sm font-medium transition-colors duration-ds-fast ${
                sortBy === opt.id
                  ? 'bg-accent-600 text-white'
                  : 'bg-neutral-800 text-neutral-300 hover:bg-neutral-700'
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>

        {/* Stats row */}
        <div className="flex items-center justify-between text-ds-caption">
          <span className="text-neutral-500">
            {sortedVehicles.length === positions.length
              ? `${positions.length} vehicles tracked`
              : `${sortedVehicles.length} of ${positions.length} vehicles`}
          </span>
          <div className="flex items-center gap-ds-3">
            {staleCount > 0 && (
              <Badge variant="warning" size="sm">{staleCount} stale</Badge>
            )}
            <Badge
              variant={isConnected ? 'success' : 'warning'}
              size="sm"
              dot
              pulse={!isConnected}
            >
              {isConnected ? 'Live' : 'Reconnecting'}
            </Badge>
          </div>
        </div>
      </div>

      {/* Vehicle list */}
      <div className="flex-1 overflow-y-auto pb-safe bg-neutral-950">
        {positions.length === 0 ? (
          <div className="p-ds-4">
            <DSEmptyState
              icon={
                <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                    d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                    d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
              }
              title="Waiting for vehicles"
              description="Vehicle locations appear when trucks start transmitting"
            />
          </div>
        ) : sortedVehicles.length === 0 ? (
          <div className="p-ds-4">
            <DSEmptyState
              icon={
                <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                    d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
              }
              title="No matches found"
              description={`No vehicles match "${searchQuery}"`}
              action={{
                label: 'Clear search',
                onClick: () => setSearchQuery(''),
                variant: 'secondary',
              }}
            />
          </div>
        ) : (
          <div className="divide-y divide-neutral-800/50">
            {sortedVehicles.map((vehicle) => (
              <VehicleRow
                key={vehicle.vehicle_id}
                vehicle={vehicle}
                isFavorite={favorites.has(vehicle.vehicle_id)}
                onToggleFavorite={onToggleFavorite}
                onClick={() => onVehicleSelect(vehicle.vehicle_id)}
                isSelected={vehicle.vehicle_id === selectedVehicleId}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

/**
 * Vehicle row with GPS data - using design system tokens
 */
function VehicleRow({
  vehicle,
  isFavorite,
  onToggleFavorite,
  onClick,
  isSelected,
}: {
  vehicle: VehiclePosition
  isFavorite: boolean
  onToggleFavorite: (vehicleId: string) => void
  onClick: () => void
  isSelected: boolean
}) {
  const now = Date.now()
  const isStale = vehicle.last_update_ms && now - vehicle.last_update_ms > STALE_THRESHOLD_MS
  const lastUpdateSec = vehicle.last_update_ms ? Math.floor((now - vehicle.last_update_ms) / 1000) : null
  const speedMph = vehicle.speed_mps ? (vehicle.speed_mps * 2.237).toFixed(0) : null

  return (
    <div
      className={`flex items-center gap-ds-3 px-ds-4 py-ds-3 transition-colors duration-ds-fast ${
        isSelected ? 'bg-accent-600/20' : 'hover:bg-neutral-900/50'
      }`}
    >
      {/* Clickable main area */}
      <button
        onClick={onClick}
        className="flex-1 flex items-center gap-ds-3 min-h-[44px] text-left"
      >
        {/* Vehicle badge */}
        <div
          className={`w-12 h-12 rounded-ds-lg flex items-center justify-center shrink-0 ${
            isStale
              ? 'bg-status-warning/20 border border-status-warning/50'
              : 'bg-neutral-700'
          }`}
        >
          <span className={`text-ds-title font-bold ${isStale ? 'text-status-warning' : 'text-neutral-50'}`}>
            #{vehicle.vehicle_number}
          </span>
        </div>

        {/* Vehicle info */}
        <div className="flex-1 min-w-0">
          <div className="text-ds-body font-medium text-neutral-50 truncate">
            {vehicle.team_name}
          </div>
          <div className="flex items-center gap-ds-3 text-ds-body-sm">
            {/* Speed */}
            {speedMph && (
              <span className="text-neutral-400 flex items-center gap-ds-1">
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
                {speedMph} mph
              </span>
            )}
            {/* Last checkpoint */}
            {vehicle.last_checkpoint !== null && (
              <span className="text-neutral-500">
                CP{vehicle.last_checkpoint}
              </span>
            )}
          </div>
        </div>

        {/* Status */}
        <div className="text-right shrink-0">
          {isStale ? (
            <div className="flex items-center gap-ds-1 text-status-warning text-ds-body-sm">
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <span>Stale</span>
            </div>
          ) : lastUpdateSec !== null ? (
            <div className="text-neutral-500 text-ds-body-sm">
              {lastUpdateSec < 5 ? (
                <span className="text-status-success">Just now</span>
              ) : lastUpdateSec < 60 ? (
                `${lastUpdateSec}s ago`
              ) : (
                `${Math.floor(lastUpdateSec / 60)}m ago`
              )}
            </div>
          ) : null}

          {/* Heading indicator */}
          {vehicle.heading_deg !== null && !isStale && (
            <div className="text-ds-caption text-neutral-600 mt-0.5">
              {getCompassDirection(vehicle.heading_deg)}
            </div>
          )}
        </div>
      </button>

      {/* Favorite button */}
      <FavoriteButton
        vehicleId={vehicle.vehicle_id}
        isFavorite={isFavorite}
        onToggle={onToggleFavorite}
        size="md"
      />
    </div>
  )
}

/**
 * Convert heading degrees to compass direction
 */
function getCompassDirection(heading: number): string {
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
  const index = Math.round(heading / 45) % 8
  return directions[index]
}
