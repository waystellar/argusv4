/**
 * Hook to show toast notifications for checkpoint crossings
 *
 * FIXED: P2-6 - Checkpoint crossing notifications
 *
 * Watches for new checkpoint crossings in the event store and shows
 * toast notifications. Can be configured to show all crossings or
 * only those for specific vehicles (tracked/selected).
 */
import { useEffect, useRef } from 'react'
import { useEventStore } from '../stores/eventStore'
import { useToast } from './useToast'

interface UseCheckpointNotificationsOptions {
  /** Only show notifications for these vehicle IDs */
  vehicleIds?: string[]
  /** Show all crossing notifications (default: false, only shows for selected vehicle) */
  showAll?: boolean
  /** Enable notifications (default: true) */
  enabled?: boolean
}

export function useCheckpointNotifications(options: UseCheckpointNotificationsOptions = {}) {
  const { vehicleIds, showAll = false, enabled = true } = options
  const toast = useToast()
  const recentCrossings = useEventStore((state) => state.recentCrossings)
  const selectedVehicleId = useEventStore((state) => state.selectedVehicleId)

  // Track which crossings we've already notified about
  const notifiedIdsRef = useRef<Set<string>>(new Set())

  useEffect(() => {
    if (!enabled || recentCrossings.length === 0) return

    for (const crossing of recentCrossings) {
      // Skip if already notified
      if (notifiedIdsRef.current.has(crossing.id)) continue

      // Determine if we should show this notification
      let shouldShow = showAll

      if (!shouldShow && vehicleIds?.length) {
        shouldShow = vehicleIds.includes(crossing.vehicle_id)
      }

      if (!shouldShow && selectedVehicleId) {
        shouldShow = crossing.vehicle_id === selectedVehicleId
      }

      if (shouldShow) {
        // Show the toast notification
        const checkpointLabel = crossing.checkpoint_name || `CP ${crossing.checkpoint_id}`
        const lapInfo = crossing.lap_number ? ` (Lap ${crossing.lap_number})` : ''

        toast.show(
          'info',
          `🏁 #${crossing.vehicle_number} crossed ${checkpointLabel}${lapInfo}`,
          crossing.team_name,
          3000 // Shorter duration for racing notifications
        )
      }

      // Mark as notified (even if not shown, to prevent re-checking)
      notifiedIdsRef.current.add(crossing.id)

      // Clean up old notification IDs to prevent memory growth
      if (notifiedIdsRef.current.size > 100) {
        const idsArray = Array.from(notifiedIdsRef.current)
        notifiedIdsRef.current = new Set(idsArray.slice(-50))
      }
    }
  }, [recentCrossings, enabled, showAll, vehicleIds, selectedVehicleId, toast])

  // Clear notified IDs when vehicle selection changes
  useEffect(() => {
    notifiedIdsRef.current.clear()
  }, [vehicleIds?.join(','), selectedVehicleId])

  return {
    /** Recent crossings from the store */
    recentCrossings,
    /** Clear the notification tracking (useful when switching events) */
    clearNotifications: () => {
      notifiedIdsRef.current.clear()
    },
  }
}
