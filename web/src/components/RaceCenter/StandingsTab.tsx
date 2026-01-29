/**
 * Standings Tab - Full leaderboard with search and filters
 *
 * Features:
 * - Full leaderboard (not truncated)
 * - Search by vehicle number or team name
 * - Class filter placeholder (for future use)
 * - Favorites integration with star buttons
 *
 * UI-4 Update: Refactored to use design system tokens and components
 */
import { useState, useMemo } from 'react'
import { FavoriteButton } from '../../hooks/useFavorites'
import { Badge, EmptyState as DSEmptyState } from '../ui'
import type { TabProps } from './types'
import type { LeaderboardEntry } from '../../api/client'

// Class filter options (placeholder for future feature)
const CLASS_FILTERS = [
  { id: 'all', label: 'All Classes' },
  { id: 'unlimited', label: 'Unlimited' },
  { id: 'stock', label: 'Stock' },
  { id: 'modified', label: 'Modified' },
] as const

export default function StandingsTab({
  eventId: _eventId,
  leaderboard,
  favorites,
  onToggleFavorite,
  onVehicleSelect,
  selectedVehicleId,
  isConnected,
}: TabProps) {
  const [searchQuery, setSearchQuery] = useState('')
  const [selectedClass, setSelectedClass] = useState<string>('all')

  // Filter entries based on search and class
  const filteredEntries = useMemo(() => {
    let filtered = leaderboard

    // Search filter
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase().trim()
      filtered = filtered.filter((entry) => {
        const vehicleNum = entry.vehicle_number.toLowerCase()
        if (vehicleNum.includes(query) || `#${vehicleNum}`.includes(query)) {
          return true
        }
        if (entry.team_name.toLowerCase().includes(query)) {
          return true
        }
        if (entry.driver_name?.toLowerCase().includes(query)) {
          return true
        }
        return false
      })
    }

    // Class filter (placeholder - no class data in entries yet)
    // When class data is added to LeaderboardEntry, uncomment:
    // if (selectedClass !== 'all') {
    //   filtered = filtered.filter((e) => e.vehicle_class === selectedClass)
    // }

    return filtered
  }, [leaderboard, searchQuery, selectedClass])

  return (
    <div className="flex flex-col h-full bg-neutral-950">
      {/* Sticky Header with search and filters */}
      <div className="sticky top-0 z-10 p-ds-4 bg-neutral-900 border-b border-neutral-800 space-y-ds-3">
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

        {/* Class filter chips (placeholder) */}
        <div className="flex gap-ds-2 overflow-x-auto pb-ds-1 -mx-ds-1 px-ds-1">
          {CLASS_FILTERS.map((cls) => (
            <button
              key={cls.id}
              onClick={() => setSelectedClass(cls.id)}
              disabled={cls.id !== 'all'}
              className={`shrink-0 min-h-[36px] px-ds-4 py-ds-1 rounded-ds-full text-ds-body-sm font-medium transition-colors duration-ds-fast ${
                selectedClass === cls.id
                  ? 'bg-accent-600 text-white'
                  : cls.id === 'all'
                  ? 'bg-neutral-800 text-neutral-300 hover:bg-neutral-700'
                  : 'bg-neutral-800/50 text-neutral-500 cursor-not-allowed opacity-50'
              }`}
            >
              {cls.label}
            </button>
          ))}
        </div>

        {/* Stats row */}
        <div className="flex items-center justify-between text-ds-caption text-neutral-500">
          <span>
            {filteredEntries.length === leaderboard.length
              ? `${leaderboard.length} vehicles`
              : `${filteredEntries.length} of ${leaderboard.length} vehicles`}
          </span>
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

      {/* Leaderboard list */}
      <div className="flex-1 overflow-y-auto pb-safe">
        {leaderboard.length === 0 ? (
          <div className="p-ds-4">
            <DSEmptyState
              icon={
                <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                    d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                </svg>
              }
              title="No entrants registered"
              description="Standings will appear once vehicles are registered for this event."
            />
          </div>
        ) : filteredEntries.length === 0 ? (
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
            {filteredEntries.map((entry) => (
              <StandingsRow
                key={entry.vehicle_id}
                entry={entry}
                isFavorite={favorites.has(entry.vehicle_id)}
                onToggleFavorite={onToggleFavorite}
                onClick={() => onVehicleSelect(entry.vehicle_id)}
                isSelected={entry.vehicle_id === selectedVehicleId}
                isHighlighted={searchQuery.trim().length > 0}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

/**
 * Standings row with favorite button - consistent 56px row height
 */
function StandingsRow({
  entry,
  isFavorite,
  onToggleFavorite,
  onClick,
  isSelected,
  isHighlighted,
}: {
  entry: LeaderboardEntry
  isFavorite: boolean
  onToggleFavorite: (vehicleId: string) => void
  onClick: () => void
  isSelected: boolean
  isHighlighted: boolean
}) {
  const notStarted = entry.last_checkpoint === 0
  const positionColor = notStarted
    ? { bg: 'rgb(var(--color-neutral-800) / 1)', text: 'rgb(var(--color-neutral-500) / 1)' }
    : getPositionColor(entry.position)
  const isLeader = entry.position === 1 && !notStarted

  return (
    <div
      className={`flex items-center gap-ds-3 px-ds-4 py-ds-3 transition-colors duration-ds-fast ${
        isSelected
          ? 'bg-accent-600/20'
          : isHighlighted
          ? 'bg-accent-900/10'
          : 'hover:bg-neutral-900/50'
      }`}
    >
      {/* Clickable main area */}
      <button
        onClick={onClick}
        className="flex-1 flex items-center gap-ds-3 min-h-[44px] text-left"
      >
        {/* Position badge */}
        <div
          className="w-10 h-10 rounded-full flex items-center justify-center text-ds-body-sm font-bold shrink-0"
          style={{ backgroundColor: positionColor.bg, color: positionColor.text }}
        >
          {notStarted ? '—' : entry.position}
        </div>

        {/* Vehicle info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-baseline gap-ds-2">
            <span className="text-ds-title text-neutral-50">
              #{entry.vehicle_number}
            </span>
          </div>
          <div className="text-ds-body-sm text-neutral-400 truncate">{entry.team_name}</div>
          {entry.driver_name && (
            <div className="text-ds-caption text-neutral-500 truncate">{entry.driver_name}</div>
          )}
        </div>

        {/* Delta to leader */}
        <div className="text-right shrink-0">
          <div
            className={`font-mono text-ds-body font-bold tabular-nums ${
              isLeader ? 'text-status-warning' : 'text-neutral-200'
            }`}
          >
            {isLeader ? 'LEADER' : entry.delta_formatted}
          </div>
          <div className="text-ds-caption text-neutral-500">
            {entry.last_checkpoint_name || `CP${entry.last_checkpoint}`}
          </div>
          {entry.miles_remaining != null && (
            <div className="text-ds-caption text-neutral-400 tabular-nums">
              {entry.miles_remaining.toFixed(1)} mi remaining
            </div>
          )}
        </div>
      </button>

      {/* Favorite button - separate from main click area */}
      <FavoriteButton
        vehicleId={entry.vehicle_id}
        isFavorite={isFavorite}
        onToggle={onToggleFavorite}
        size="md"
      />
    </div>
  )
}

/**
 * Get position badge colors using design system colors
 */
function getPositionColor(position: number): { bg: string; text: string } {
  switch (position) {
    case 1:
      return { bg: 'rgb(var(--color-status-warning) / 1)', text: 'rgb(var(--color-neutral-950) / 1)' } // Gold
    case 2:
      return { bg: 'rgb(203 213 225 / 1)', text: 'rgb(var(--color-neutral-950) / 1)' } // Silver (neutral-300)
    case 3:
      return { bg: 'rgb(180 83 9 / 1)', text: 'white' } // Bronze (amber-700)
    default:
      return { bg: 'rgb(var(--color-neutral-700) / 1)', text: 'rgb(var(--color-neutral-50) / 1)' }
  }
}
