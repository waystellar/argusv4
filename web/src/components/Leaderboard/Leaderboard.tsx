/**
 * Leaderboard component showing race standings
 *
 * FIXED: P1-3 - Added search/filter functionality
 *
 * Mobile-optimized with:
 * - Prominent "Gap to Leader" display
 * - Hidden team name on small screens
 * - Larger touch targets
 * - Monospace font for easy number scanning
 * - Search/filter by vehicle number or team name
 */
import { useState, useMemo } from 'react'
import type { LeaderboardEntry } from '../../api/client'

interface LeaderboardProps {
  entries: LeaderboardEntry[]
  onVehicleClick?: (vehicleId: string) => void
  showSearch?: boolean // Allow disabling search for compact views
}

/**
 * Search input component for filtering leaderboard
 */
function LeaderboardSearch({
  value,
  onChange,
  resultCount,
  totalCount,
}: {
  value: string
  onChange: (value: string) => void
  resultCount: number
  totalCount: number
}) {
  return (
    <div className="relative mb-2">
      <div className="flex items-center gap-2">
        {/* Search icon */}
        <div className="absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none">
          <svg className="w-4 h-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>

        {/* Search input */}
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="Search # or team..."
          className="w-full pl-9 pr-8 py-2 bg-gray-800/50 border border-gray-700 rounded-lg text-white text-sm placeholder-gray-500 focus:outline-none focus:border-primary-500 focus:ring-1 focus:ring-primary-500/50"
        />

        {/* Clear button */}
        {value && (
          <button
            onClick={() => onChange('')}
            className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300"
          >
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        )}
      </div>

      {/* Result count when filtering */}
      {value && (
        <div className="text-xs text-gray-500 mt-1 px-1">
          {resultCount === 0 ? (
            'No matches found'
          ) : (
            `Showing ${resultCount} of ${totalCount}`
          )}
        </div>
      )}
    </div>
  )
}

export default function Leaderboard({ entries, onVehicleClick, showSearch = true }: LeaderboardProps) {
  const [searchQuery, setSearchQuery] = useState('')

  // Filter entries based on search query
  const filteredEntries = useMemo(() => {
    if (!searchQuery.trim()) return entries

    const query = searchQuery.toLowerCase().trim()
    return entries.filter((entry) => {
      // Match vehicle number (with or without #)
      const vehicleNum = entry.vehicle_number.toLowerCase()
      if (vehicleNum.includes(query) || `#${vehicleNum}`.includes(query)) {
        return true
      }
      // Match team name
      if (entry.team_name.toLowerCase().includes(query)) {
        return true
      }
      // Match driver name
      if (entry.driver_name?.toLowerCase().includes(query)) {
        return true
      }
      return false
    })
  }, [entries, searchQuery])

  if (entries.length === 0) {
    return (
      <div className="text-center text-gray-400 py-8">
        <div className="text-lg mb-1">Waiting for vehicles...</div>
        <div className="text-sm text-gray-500">Standings appear when vehicles cross checkpoints</div>
      </div>
    )
  }

  return (
    <div>
      {/* Search input - only show if there are enough entries to warrant search */}
      {showSearch && entries.length >= 5 && (
        <LeaderboardSearch
          value={searchQuery}
          onChange={setSearchQuery}
          resultCount={filteredEntries.length}
          totalCount={entries.length}
        />
      )}

      {/* Filtered results */}
      {filteredEntries.length === 0 ? (
        <div className="text-center text-gray-500 py-6">
          <div className="text-sm">No vehicles match "{searchQuery}"</div>
          <button
            onClick={() => setSearchQuery('')}
            className="mt-2 text-primary-400 text-sm hover:underline"
          >
            Clear search
          </button>
        </div>
      ) : (
        <div className="divide-y divide-gray-700/30">
          {filteredEntries.map((entry) => (
            <LeaderboardRow
              key={entry.vehicle_id}
              entry={entry}
              onClick={() => onVehicleClick?.(entry.vehicle_id)}
              highlight={searchQuery.trim().length > 0}
            />
          ))}
        </div>
      )}
    </div>
  )
}

interface LeaderboardRowProps {
  entry: LeaderboardEntry
  onClick?: () => void
  highlight?: boolean // Visual feedback when entry matches search
}

function LeaderboardRow({ entry, onClick, highlight }: LeaderboardRowProps) {
  const positionColor = getPositionColor(entry.position)
  const isLeader = entry.position === 1

  return (
    <button
      onClick={onClick}
      className={`leaderboard-row w-full px-2 py-3 sm:py-2 flex items-center gap-3 hover:bg-surface-lighter active:bg-surface-lighter transition-colors text-left ${
        highlight ? 'bg-primary-900/20' : ''
      }`}
    >
      {/* Position badge - larger on mobile */}
      <div
        className="leaderboard-position w-10 h-10 sm:w-8 sm:h-8 rounded-full flex items-center justify-center text-base sm:text-sm font-bold shrink-0"
        style={{ backgroundColor: positionColor.bg, color: positionColor.text }}
      >
        {entry.position}
      </div>

      {/* Vehicle info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-baseline gap-2">
          <span className="leaderboard-vehicle-number text-lg sm:text-base font-bold text-white">
            #{entry.vehicle_number}
          </span>
          {/* Team name - hidden on mobile (<640px) */}
          <span className="leaderboard-team-name hidden sm:inline text-sm text-gray-400 truncate">
            {entry.team_name}
          </span>
        </div>
        {/* Show team name below on mobile only */}
        <div className="sm:hidden text-xs text-gray-500 truncate">{entry.team_name}</div>
        {entry.driver_name && (
          <div className="hidden sm:block text-xs text-gray-500 truncate">{entry.driver_name}</div>
        )}
      </div>

      {/* Gap to Leader - THE most important stat */}
      <div className="text-right shrink-0">
        <div
          className={`leaderboard-delta font-mono text-base sm:text-sm font-bold tabular-nums ${
            isLeader ? 'leaderboard-delta-leader text-primary-400' : 'text-gray-200'
          }`}
          style={{ minWidth: '6ch' }}
        >
          {isLeader ? 'LEADER' : entry.delta_formatted}
        </div>
        <div className="text-[10px] sm:text-xs text-gray-500 uppercase tracking-wide">
          {entry.last_checkpoint_name || `CP${entry.last_checkpoint}`}
        </div>
      </div>

      {/* Chevron - smaller on mobile */}
      <svg className="w-4 h-4 sm:w-5 sm:h-5 text-gray-600 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
      </svg>
    </button>
  )
}

function getPositionColor(position: number): { bg: string; text: string } {
  switch (position) {
    case 1:
      return { bg: '#FFD700', text: '#000' } // Gold
    case 2:
      return { bg: '#C0C0C0', text: '#000' } // Silver
    case 3:
      return { bg: '#CD7F32', text: '#000' } // Bronze
    default:
      return { bg: '#3a3a5a', text: '#fff' } // Default
  }
}
