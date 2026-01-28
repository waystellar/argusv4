/**
 * Zustand store for event state management
 *
 * FIXED: P1-6 - Added timestamp comparison to prevent SSE snapshot collision
 * FIXED: P2-3 - Added leaderboard state for SSE streaming
 * FIXED: P2-6 - Added checkpoint crossing notifications
 * PR-2 UX: Added per-vehicle staleness tracking
 *
 * The issue was that when SSE sends a snapshot followed by real-time updates,
 * the snapshot could overwrite newer position data. Now we compare timestamps
 * and only update if the incoming data is newer.
 */
import { create } from 'zustand'
import type { VehiclePosition, LeaderboardEntry } from '../api/client'

// PR-2 UX: Default thresholds for staleness detection
export const FRESHNESS_THRESHOLDS = {
  fresh: 10000, // 10 seconds - data is fresh
  stale: 30000, // 30 seconds - data is stale but vehicle may still be active
  offline: 60000, // 60 seconds - consider vehicle offline
}

export type FreshnessState = 'fresh' | 'stale' | 'offline'

// FIXED: P2-6 - Checkpoint crossing data for notifications
export interface CheckpointCrossing {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  checkpoint_id: number
  checkpoint_name?: string
  lap_number?: number
  crossing_time_ms: number
  id: string // Unique ID for React key
}

interface EventState {
  // Positions
  positions: Map<string, VehiclePosition>
  setPositions: (positions: VehiclePosition[]) => void
  updatePosition: (position: Partial<VehiclePosition> & { vehicle_id: string }) => void
  clearPositions: () => void

  // Leaderboard (FIXED: P2-3 - SSE streaming support)
  leaderboard: LeaderboardEntry[]
  leaderboardTimestamp: number | null
  setLeaderboard: (entries: LeaderboardEntry[], timestamp?: number) => void
  clearLeaderboard: () => void

  // Checkpoint crossings (FIXED: P2-6 - Notifications)
  recentCrossings: CheckpointCrossing[]
  addCrossing: (crossing: Omit<CheckpointCrossing, 'id'>) => void
  clearCrossings: () => void

  // Visibility
  hiddenVehicles: Set<string>
  setVehicleVisibility: (vehicleId: string, visible: boolean) => void

  // Selection
  selectedVehicleId: string | null
  setSelectedVehicle: (vehicleId: string | null) => void

  // Filtered positions (excludes hidden)
  getVisiblePositions: () => VehiclePosition[]

  // PR-2 UX: Per-vehicle staleness tracking
  getVehicleFreshness: (vehicleId: string) => FreshnessState
  getStaleVehicles: (thresholdMs?: number) => string[]
  getVehicleStats: () => { fresh: number; stale: number; offline: number }
}

export const useEventStore = create<EventState>((set, get) => ({
  // Positions
  positions: new Map(),

  /**
   * Set positions from snapshot.
   * FIXED: P1-6 - Only update positions if the snapshot data is newer than existing data.
   * This prevents snapshot from overwriting real-time updates that arrived first.
   */
  setPositions: (positions) => {
    set((state) => {
      const newPositions = new Map(state.positions)

      for (const pos of positions) {
        const existing = newPositions.get(pos.vehicle_id)

        // Only update if:
        // 1. No existing position for this vehicle, OR
        // 2. Incoming position has a newer (or same) timestamp
        if (!existing ||
            !existing.last_update_ms ||
            !pos.last_update_ms ||
            pos.last_update_ms >= existing.last_update_ms) {
          newPositions.set(pos.vehicle_id, pos)
        }
        // If existing is newer, keep it (skip the snapshot data for this vehicle)
      }

      return { positions: newPositions }
    })
  },

  /**
   * Update a single position from real-time event.
   * FIXED: P1-6 - Only update if incoming data is newer than existing.
   */
  updatePosition: (position) => {
    set((state) => {
      const newPositions = new Map(state.positions)
      const existing = newPositions.get(position.vehicle_id)

      if (existing) {
        // Only update if incoming is newer (or has no timestamp)
        const incomingTs = position.last_update_ms || 0
        const existingTs = existing.last_update_ms || 0

        if (incomingTs >= existingTs) {
          newPositions.set(position.vehicle_id, { ...existing, ...position })
        }
        // If existing is newer, ignore this update (it's stale)
      } else {
        // No existing position, add the new one
        newPositions.set(position.vehicle_id, position as VehiclePosition)
      }

      return { positions: newPositions }
    })
  },

  /**
   * Clear all positions (used when switching events or disconnecting)
   */
  clearPositions: () => {
    set({ positions: new Map() })
  },

  // Leaderboard (FIXED: P2-3 - SSE streaming support)
  leaderboard: [],
  leaderboardTimestamp: null,

  /**
   * Set leaderboard from SSE or API.
   * Only updates if incoming data is newer (or no timestamp provided).
   */
  setLeaderboard: (entries, timestamp) => {
    set((state) => {
      // If we have timestamps, only update if incoming is newer
      if (timestamp && state.leaderboardTimestamp && timestamp < state.leaderboardTimestamp) {
        return state // Ignore stale data
      }
      return {
        leaderboard: entries,
        leaderboardTimestamp: timestamp || Date.now(),
      }
    })
  },

  /**
   * Clear leaderboard (used when switching events)
   */
  clearLeaderboard: () => {
    set({ leaderboard: [], leaderboardTimestamp: null })
  },

  // Checkpoint crossings (FIXED: P2-6 - Notifications)
  recentCrossings: [],

  /**
   * Add a checkpoint crossing for notification.
   * Keeps only the last 20 crossings to prevent memory issues.
   */
  addCrossing: (crossing) => {
    set((state) => {
      const id = `cx-${Date.now()}-${crossing.vehicle_id}`
      const newCrossing: CheckpointCrossing = { ...crossing, id }
      const crossings = [newCrossing, ...state.recentCrossings].slice(0, 20)
      return { recentCrossings: crossings }
    })
  },

  /**
   * Clear crossings (used when switching events)
   */
  clearCrossings: () => {
    set({ recentCrossings: [] })
  },

  // Visibility
  hiddenVehicles: new Set(),

  setVehicleVisibility: (vehicleId, visible) => {
    set((state) => {
      const hidden = new Set(state.hiddenVehicles)
      if (visible) {
        hidden.delete(vehicleId)
      } else {
        hidden.add(vehicleId)
      }
      return { hiddenVehicles: hidden }
    })
  },

  // Selection
  selectedVehicleId: null,
  setSelectedVehicle: (vehicleId) => set({ selectedVehicleId: vehicleId }),

  // Filtered
  getVisiblePositions: () => {
    const { positions, hiddenVehicles } = get()
    return Array.from(positions.values()).filter(
      (pos) => !hiddenVehicles.has(pos.vehicle_id)
    )
  },

  // PR-2 UX: Get freshness state for a single vehicle
  getVehicleFreshness: (vehicleId) => {
    const { positions } = get()
    const pos = positions.get(vehicleId)
    if (!pos || !pos.last_update_ms) return 'offline'

    const age = Date.now() - pos.last_update_ms
    if (age <= FRESHNESS_THRESHOLDS.fresh) return 'fresh'
    if (age <= FRESHNESS_THRESHOLDS.stale) return 'stale'
    return 'offline'
  },

  // PR-2 UX: Get all vehicles that are stale (no updates beyond threshold)
  getStaleVehicles: (thresholdMs = FRESHNESS_THRESHOLDS.stale) => {
    const { positions } = get()
    const now = Date.now()
    const stale: string[] = []
    positions.forEach((pos, vid) => {
      if (!pos.last_update_ms || now - pos.last_update_ms > thresholdMs) {
        stale.push(vid)
      }
    })
    return stale
  },

  // PR-2 UX: Get counts of vehicles by freshness state
  getVehicleStats: () => {
    const { positions } = get()
    const now = Date.now()
    let fresh = 0
    let stale = 0
    let offline = 0

    positions.forEach((pos) => {
      if (!pos.last_update_ms) {
        offline++
        return
      }
      const age = now - pos.last_update_ms
      if (age <= FRESHNESS_THRESHOLDS.fresh) {
        fresh++
      } else if (age <= FRESHNESS_THRESHOLDS.stale) {
        stale++
      } else {
        offline++
      }
    })

    return { fresh, stale, offline }
  },
}))
