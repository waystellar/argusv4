/**
 * Overview Tab - Race Center home view
 *
 * Shows:
 * - Interactive map with "Center on Race" button
 * - Favorites quick row (if any)
 * - Top 10 mini leaderboard
 * - Featured vehicle tile (leader or selected)
 *
 * UI-4 Update: Refactored to use design system tokens and components
 */
import { useMemo, useCallback } from 'react'
import RaceMap from '../Map/Map'
import { FavoriteButton } from '../../hooks/useFavorites'
import { Badge, Alert, EmptyState as DSEmptyState } from '../ui'
import type { TabProps } from './types'
import type { VehiclePosition, LeaderboardEntry } from '../../api/client'

// Stale threshold for position data
const STALE_THRESHOLD_MS = 30000 // 30 seconds

interface OverviewTabProps extends TabProps {
  onCenterOnRace?: () => void
}

export default function OverviewTab({
  eventId: _eventId,
  positions,
  leaderboard,
  favorites,
  onToggleFavorite,
  onVehicleSelect,
  selectedVehicleId,
  courseGeoJSON,
  isConnected: _isConnected,
}: OverviewTabProps) {
  // Get favorite vehicles with position data
  const favoriteVehicles = useMemo(() => {
    const posMap = new Map(positions.map(p => [p.vehicle_id, p] as [string, VehiclePosition]))
    return Array.from(favorites)
      .map(vid => posMap.get(vid))
      .filter((p): p is VehiclePosition => p !== undefined)
      .slice(0, 6) // Limit to 6 favorites in quick row
  }, [favorites, positions])

  // Get top 10 from leaderboard
  const top10 = useMemo(() => leaderboard.slice(0, 10), [leaderboard])

  // Featured vehicle: selected or leader
  const featuredEntry = useMemo(() => {
    if (selectedVehicleId) {
      return leaderboard.find(e => e.vehicle_id === selectedVehicleId)
    }
    return leaderboard[0] // Leader
  }, [leaderboard, selectedVehicleId])

  // Check if any position data is stale
  const hasStaleData = useMemo(() => {
    const now = Date.now()
    return positions.some(p => p.last_update_ms && now - p.last_update_ms > STALE_THRESHOLD_MS)
  }, [positions])

  return (
    <div className="flex flex-col h-full overflow-hidden bg-neutral-950">
      {/* Map Section - Takes ~50% on mobile */}
      <div className="relative flex-1 min-h-[200px] max-h-[50vh]">
        <RaceMap
          positions={positions}
          onVehicleClick={onVehicleSelect}
          selectedVehicleId={selectedVehicleId}
          courseGeoJSON={courseGeoJSON}
        />

        {/* Center on Race Button */}
        <CenterOnRaceButton
          positions={positions}
          courseGeoJSON={courseGeoJSON}
        />

        {/* Stale Data Warning */}
        {hasStaleData && (
          <div className="absolute top-ds-2 left-ds-2 right-14 z-10">
            <Alert variant="warning" className="py-ds-1 px-ds-3 text-ds-caption">
              Some positions are stale (30s+)
            </Alert>
          </div>
        )}
      </div>

      {/* Bottom content - scrollable */}
      <div className="flex-1 overflow-y-auto bg-neutral-950 pb-safe">
        {/* Favorites Quick Row */}
        {favoriteVehicles.length > 0 && (
          <FavoritesQuickRow
            vehicles={favoriteVehicles}
            onVehicleClick={onVehicleSelect}
            selectedVehicleId={selectedVehicleId}
          />
        )}

        {/* Featured Vehicle Tile */}
        {featuredEntry && (
          <FeaturedVehicleTile
            entry={featuredEntry}
            isFavorite={favorites.has(featuredEntry.vehicle_id)}
            onToggleFavorite={onToggleFavorite}
            onClick={() => onVehicleSelect(featuredEntry.vehicle_id)}
          />
        )}

        {/* Top 10 Mini Leaderboard */}
        <div className="px-ds-4 py-ds-3">
          <div className="flex items-center justify-between mb-ds-2">
            <h3 className="text-ds-body-sm font-semibold text-neutral-400 uppercase tracking-wide">
              Top 10
            </h3>
            {top10.length > 0 && (
              <span className="text-ds-caption text-neutral-500">
                {positions.length} active
              </span>
            )}
          </div>

          {top10.length === 0 ? (
            <DSEmptyState
              icon={
                <svg className="w-12 h-12" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                    d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                </svg>
              }
              title="Waiting for race data"
              description="Standings appear when vehicles cross checkpoints"
            />
          ) : (
            <div className="space-y-ds-1">
              {top10.map((entry) => (
                <MiniLeaderboardRow
                  key={entry.vehicle_id}
                  entry={entry}
                  isFavorite={favorites.has(entry.vehicle_id)}
                  onToggleFavorite={onToggleFavorite}
                  onClick={() => onVehicleSelect(entry.vehicle_id)}
                  isSelected={entry.vehicle_id === selectedVehicleId}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

/**
 * Center on Race Button - Fits map to course or vehicles
 */
function CenterOnRaceButton({
  positions,
  courseGeoJSON,
}: {
  positions: VehiclePosition[]
  courseGeoJSON?: GeoJSON.FeatureCollection | null
}) {
  const handleCenter = useCallback(() => {
    window.dispatchEvent(new CustomEvent('argus:centerOnRace', {
      detail: { positions, courseGeoJSON }
    }))
  }, [positions, courseGeoJSON])

  return (
    <button
      onClick={handleCenter}
      className="absolute top-ds-2 right-ds-2 z-10 min-w-[44px] min-h-[44px] bg-neutral-950/80 hover:bg-neutral-950/90 text-neutral-50 rounded-ds-lg px-ds-3 py-ds-2 flex items-center gap-ds-2 text-ds-body-sm font-medium transition-colors duration-ds-fast"
      aria-label="Center map on race"
    >
      <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
          d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
      </svg>
      <span className="hidden sm:inline">Center</span>
    </button>
  )
}

/**
 * Favorites Quick Row - Horizontal scroll of starred vehicles
 */
function FavoritesQuickRow({
  vehicles,
  onVehicleClick,
  selectedVehicleId,
}: {
  vehicles: VehiclePosition[]
  onVehicleClick: (vehicleId: string) => void
  selectedVehicleId: string | null
}) {
  return (
    <div className="px-ds-4 py-ds-3 border-b border-neutral-800">
      <h3 className="text-ds-caption font-semibold text-status-warning uppercase tracking-wide mb-ds-2 flex items-center gap-ds-1">
        <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
          <path d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
        </svg>
        Favorites
      </h3>
      <div className="flex gap-ds-2 overflow-x-auto pb-ds-1 -mx-ds-1 px-ds-1">
        {vehicles.map((vehicle) => (
          <button
            key={vehicle.vehicle_id}
            onClick={() => onVehicleClick(vehicle.vehicle_id)}
            className={`shrink-0 min-w-[80px] min-h-[44px] px-ds-3 py-ds-2 rounded-ds-lg border-2 transition-all duration-ds-fast ${
              vehicle.vehicle_id === selectedVehicleId
                ? 'bg-accent-600/30 border-accent-500 text-neutral-50'
                : 'bg-neutral-800/50 border-neutral-700 text-neutral-300 hover:border-neutral-600'
            }`}
          >
            <div className="text-ds-title font-bold">#{vehicle.vehicle_number}</div>
            <div className="text-ds-caption text-neutral-500 truncate max-w-[70px]">
              {vehicle.team_name}
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}

/**
 * Featured Vehicle Tile - Highlight for leader or selected vehicle
 */
function FeaturedVehicleTile({
  entry,
  isFavorite,
  onToggleFavorite,
  onClick,
}: {
  entry: LeaderboardEntry
  isFavorite: boolean
  onToggleFavorite: (vehicleId: string) => void
  onClick: () => void
}) {
  const isLeader = entry.position === 1

  return (
    <button
      onClick={onClick}
      className="w-full px-ds-4 py-ds-3 border-b border-neutral-800 flex items-center gap-ds-4 hover:bg-neutral-900/50 transition-colors duration-ds-fast text-left"
    >
      {/* Position Badge */}
      <div
        className={`w-14 h-14 rounded-ds-lg flex items-center justify-center text-xl font-black shrink-0 ${
          isLeader
            ? 'bg-status-warning text-neutral-950'
            : 'bg-accent-600 text-white'
        }`}
      >
        P{entry.position}
      </div>

      {/* Info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-ds-2">
          <span className="text-ds-display text-neutral-50">#{entry.vehicle_number}</span>
          {isLeader && (
            <Badge variant="warning" size="sm">LEADER</Badge>
          )}
        </div>
        <div className="text-ds-body-sm text-neutral-400 truncate">{entry.team_name}</div>
        <div className="text-ds-caption text-neutral-500 mt-0.5">
          {entry.last_checkpoint_name || `Checkpoint ${entry.last_checkpoint}`}
        </div>
      </div>

      {/* Delta */}
      <div className="text-right shrink-0">
        <div className={`font-mono text-ds-title font-bold ${isLeader ? 'text-status-warning' : 'text-neutral-200'}`}>
          {isLeader ? '--:--' : entry.delta_formatted}
        </div>
        {!isLeader && (
          <div className="text-ds-caption text-neutral-500">to leader</div>
        )}
      </div>

      {/* Favorite Button */}
      <FavoriteButton
        vehicleId={entry.vehicle_id}
        isFavorite={isFavorite}
        onToggle={onToggleFavorite}
        size="md"
      />
    </button>
  )
}

/**
 * Mini Leaderboard Row - Compact row for top 10
 */
function MiniLeaderboardRow({
  entry,
  isFavorite,
  onToggleFavorite,
  onClick,
  isSelected,
}: {
  entry: LeaderboardEntry
  isFavorite: boolean
  onToggleFavorite: (vehicleId: string) => void
  onClick: () => void
  isSelected: boolean
}) {
  const positionColor = getPositionColor(entry.position)

  return (
    <button
      onClick={onClick}
      className={`w-full min-h-[48px] px-ds-3 py-ds-2 rounded-ds-lg flex items-center gap-ds-3 transition-colors duration-ds-fast text-left ${
        isSelected
          ? 'bg-accent-600/20 ring-1 ring-accent-500/50'
          : 'hover:bg-neutral-900/50 active:bg-neutral-900/50'
      }`}
    >
      {/* Position */}
      <div
        className="w-8 h-8 rounded-full flex items-center justify-center text-ds-body-sm font-bold shrink-0"
        style={{ backgroundColor: positionColor.bg, color: positionColor.text }}
      >
        {entry.position}
      </div>

      {/* Vehicle info */}
      <div className="flex-1 min-w-0">
        <span className="text-ds-body font-bold text-neutral-50">#{entry.vehicle_number}</span>
        <span className="text-ds-body-sm text-neutral-500 ml-ds-2 truncate hidden sm:inline">{entry.team_name}</span>
      </div>

      {/* Delta */}
      <div className="font-mono text-ds-body-sm text-neutral-300 tabular-nums">
        {entry.position === 1 ? 'LEADER' : entry.delta_formatted}
      </div>

      {/* Favorite */}
      <FavoriteButton
        vehicleId={entry.vehicle_id}
        isFavorite={isFavorite}
        onToggle={onToggleFavorite}
        size="sm"
      />
    </button>
  )
}

/**
 * Get position badge colors
 */
function getPositionColor(position: number): { bg: string; text: string } {
  switch (position) {
    case 1:
      return { bg: '#FFD700', text: '#000' } // Gold
    case 2:
      return { bg: '#C0C0C0', text: '#000' } // Silver
    case 3:
      return { bg: '#CD7F32', text: '#000' } // Bronze
    default:
      return { bg: '#404060', text: '#fff' } // Neutral
  }
}
