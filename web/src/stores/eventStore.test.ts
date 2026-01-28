/**
 * PR-2 UX: Event Store Tests - Staleness Tracking
 *
 * Tests for:
 * 1. Per-vehicle freshness state calculation
 * 2. Stale vehicle detection
 * 3. Vehicle statistics
 */
import { describe, it, expect, beforeEach } from 'vitest'
import { useEventStore, FRESHNESS_THRESHOLDS } from './eventStore'

// Helper to reset store between tests
function resetStore() {
  useEventStore.setState({
    positions: new Map(),
    leaderboard: [],
    leaderboardTimestamp: null,
    recentCrossings: [],
    hiddenVehicles: new Set(),
    selectedVehicleId: null,
  })
}

describe('eventStore - staleness tracking', () => {
  beforeEach(() => {
    resetStore()
  })

  describe('FRESHNESS_THRESHOLDS', () => {
    it('should have correct default thresholds', () => {
      expect(FRESHNESS_THRESHOLDS.fresh).toBe(10000) // 10s
      expect(FRESHNESS_THRESHOLDS.stale).toBe(30000) // 30s
      expect(FRESHNESS_THRESHOLDS.offline).toBe(60000) // 60s
    })
  })

  describe('getVehicleFreshness', () => {
    it('should return "offline" for unknown vehicle', () => {
      const state = useEventStore.getState()
      const freshness = state.getVehicleFreshness('unknown_vehicle')
      expect(freshness).toBe('offline')
    })

    it('should return "offline" for vehicle without timestamp', () => {
      const state = useEventStore.getState()
      state.setPositions([
        {
          vehicle_id: 'veh_1',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Test',
          // No last_update_ms
        } as any,
      ])

      const freshness = useEventStore.getState().getVehicleFreshness('veh_1')
      expect(freshness).toBe('offline')
    })

    it('should return "fresh" for recently updated vehicle', () => {
      const state = useEventStore.getState()
      const now = Date.now()

      state.setPositions([
        {
          vehicle_id: 'veh_1',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Test',
          last_update_ms: now - 5000, // 5 seconds ago
        } as any,
      ])

      const freshness = useEventStore.getState().getVehicleFreshness('veh_1')
      expect(freshness).toBe('fresh')
    })

    it('should return "stale" for vehicle updated 15-30 seconds ago', () => {
      const state = useEventStore.getState()
      const now = Date.now()

      state.setPositions([
        {
          vehicle_id: 'veh_1',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Test',
          last_update_ms: now - 20000, // 20 seconds ago
        } as any,
      ])

      const freshness = useEventStore.getState().getVehicleFreshness('veh_1')
      expect(freshness).toBe('stale')
    })

    it('should return "offline" for vehicle updated more than 60 seconds ago', () => {
      const state = useEventStore.getState()
      const now = Date.now()

      state.setPositions([
        {
          vehicle_id: 'veh_1',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Test',
          last_update_ms: now - 90000, // 90 seconds ago
        } as any,
      ])

      const freshness = useEventStore.getState().getVehicleFreshness('veh_1')
      expect(freshness).toBe('offline')
    })
  })

  describe('getStaleVehicles', () => {
    it('should return empty array when no vehicles', () => {
      const state = useEventStore.getState()
      const stale = state.getStaleVehicles()
      expect(stale).toEqual([])
    })

    it('should return stale vehicles', () => {
      const state = useEventStore.getState()
      const now = Date.now()

      state.setPositions([
        {
          vehicle_id: 'veh_fresh',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Fresh',
          last_update_ms: now - 5000, // 5s ago
        } as any,
        {
          vehicle_id: 'veh_stale',
          vehicle_number: '2',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Stale',
          last_update_ms: now - 45000, // 45s ago
        } as any,
      ])

      const stale = useEventStore.getState().getStaleVehicles()
      expect(stale).toContain('veh_stale')
      expect(stale).not.toContain('veh_fresh')
    })

    it('should respect custom threshold', () => {
      const state = useEventStore.getState()
      const now = Date.now()

      state.setPositions([
        {
          vehicle_id: 'veh_1',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Test',
          last_update_ms: now - 15000, // 15s ago
        } as any,
      ])

      // With 30s threshold (default), should not be stale
      const stale30 = useEventStore.getState().getStaleVehicles(30000)
      expect(stale30).not.toContain('veh_1')

      // With 10s threshold, should be stale
      const stale10 = useEventStore.getState().getStaleVehicles(10000)
      expect(stale10).toContain('veh_1')
    })
  })

  describe('getVehicleStats', () => {
    it('should return all zeros when no vehicles', () => {
      const state = useEventStore.getState()
      const stats = state.getVehicleStats()
      expect(stats).toEqual({ fresh: 0, stale: 0, offline: 0 })
    })

    it('should correctly categorize vehicles', () => {
      const state = useEventStore.getState()
      const now = Date.now()

      state.setPositions([
        {
          vehicle_id: 'veh_fresh',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Fresh',
          last_update_ms: now - 5000, // 5s ago - fresh
        } as any,
        {
          vehicle_id: 'veh_stale',
          vehicle_number: '2',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Stale',
          last_update_ms: now - 20000, // 20s ago - stale
        } as any,
        {
          vehicle_id: 'veh_offline',
          vehicle_number: '3',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Offline',
          last_update_ms: now - 90000, // 90s ago - offline
        } as any,
        {
          vehicle_id: 'veh_no_ts',
          vehicle_number: '4',
          lat: 34.0,
          lon: -116.0,
          team_name: 'No Timestamp',
          // No last_update_ms - counts as offline
        } as any,
      ])

      const stats = useEventStore.getState().getVehicleStats()
      expect(stats.fresh).toBe(1)
      expect(stats.stale).toBe(1)
      expect(stats.offline).toBe(2) // veh_offline + veh_no_ts
    })
  })
})

describe('eventStore - position management', () => {
  beforeEach(() => {
    resetStore()
  })

  describe('setPositions', () => {
    it('should set positions from snapshot', () => {
      const state = useEventStore.getState()
      state.setPositions([
        {
          vehicle_id: 'veh_1',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Test',
          last_update_ms: Date.now(),
        } as any,
      ])

      const positions = useEventStore.getState().positions
      expect(positions.size).toBe(1)
      expect(positions.get('veh_1')?.vehicle_number).toBe('1')
    })

    it('should not overwrite newer data with older snapshot', () => {
      const state = useEventStore.getState()
      const now = Date.now()

      // First: Set a position
      state.setPositions([
        {
          vehicle_id: 'veh_1',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Test',
          last_update_ms: now,
        } as any,
      ])

      // Then: Try to set older data
      useEventStore.getState().setPositions([
        {
          vehicle_id: 'veh_1',
          vehicle_number: '1',
          lat: 35.0, // Different lat
          lon: -116.0,
          team_name: 'Test',
          last_update_ms: now - 1000, // 1s older
        } as any,
      ])

      // Should keep the newer data (lat=34.0)
      const positions = useEventStore.getState().positions
      expect(positions.get('veh_1')?.lat).toBe(34.0)
    })
  })

  describe('updatePosition', () => {
    it('should update existing position', () => {
      const state = useEventStore.getState()
      const now = Date.now()

      state.setPositions([
        {
          vehicle_id: 'veh_1',
          vehicle_number: '1',
          lat: 34.0,
          lon: -116.0,
          team_name: 'Test',
          last_update_ms: now,
        } as any,
      ])

      useEventStore.getState().updatePosition({
        vehicle_id: 'veh_1',
        lat: 34.5,
        last_update_ms: now + 1000,
      })

      const positions = useEventStore.getState().positions
      expect(positions.get('veh_1')?.lat).toBe(34.5)
    })
  })
})
