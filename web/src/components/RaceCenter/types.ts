/**
 * Shared types for Race Center components
 */
import type { Event, VehiclePosition, LeaderboardEntry } from '../../api/client'

export type RaceCenterTab = 'overview' | 'standings' | 'watch' | 'tracker'

export interface RaceCenterProps {
  eventId: string
  event: Event
  positions: VehiclePosition[]
  leaderboard: LeaderboardEntry[]
  favorites: Set<string>
  onToggleFavorite: (vehicleId: string) => void
  onVehicleSelect: (vehicleId: string) => void
  selectedVehicleId: string | null
  courseGeoJSON?: GeoJSON.FeatureCollection | null
  isConnected: boolean
  cameras?: CameraFeed[]
}

export interface CameraFeed {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  camera_name: string
  youtube_url: string | null
  is_live: boolean
}

export interface TabProps {
  eventId: string
  event?: Event
  positions: VehiclePosition[]
  leaderboard: LeaderboardEntry[]
  favorites: Set<string>
  onToggleFavorite: (vehicleId: string) => void
  onVehicleSelect: (vehicleId: string) => void
  selectedVehicleId: string | null
  courseGeoJSON?: GeoJSON.FeatureCollection | null
  isConnected: boolean
  cameras?: CameraFeed[]
}
