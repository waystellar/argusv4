/**
 * API client for Argus backend
 */

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

export interface Event {
  event_id: string
  name: string
  status: 'upcoming' | 'in_progress' | 'finished'
  scheduled_start: string | null
  total_laps: number
  course_distance_m: number | null
  course_geojson: GeoJSON.FeatureCollection | null
  vehicle_count: number
  created_at: string
}

export interface VehiclePosition {
  vehicle_id: string
  vehicle_number: string
  team_name: string
  lat: number
  lon: number
  speed_mps: number | null
  heading_deg: number | null
  last_checkpoint: number | null
  last_update_ms: number
}

export interface LeaderboardEntry {
  position: number
  vehicle_id: string
  vehicle_number: string
  team_name: string
  driver_name: string | null
  last_checkpoint: number
  last_checkpoint_name: string | null
  delta_to_leader_ms: number
  delta_formatted: string
}

export interface Leaderboard {
  event_id: string
  ts: string
  entries: LeaderboardEntry[]
}

async function fetchAPI<T>(endpoint: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${endpoint}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options?.headers,
    },
  })

  if (!response.ok) {
    throw new Error(`API error: ${response.status}`)
  }

  return response.json()
}

export const api = {
  // Events
  // FIXED: P1-2 - Added getEvents for event discovery
  getEvents: (status?: string) =>
    fetchAPI<Event[]>(`/events${status ? `?status=${status}` : ''}`),
  getEvent: (eventId: string) => fetchAPI<Event>(`/events/${eventId}`),

  // Positions
  getLatestPositions: (eventId: string) =>
    fetchAPI<{ event_id: string; vehicles: VehiclePosition[] }>(
      `/events/${eventId}/positions/latest`
    ),

  // Leaderboard
  getLeaderboard: (eventId: string) =>
    fetchAPI<Leaderboard>(`/events/${eventId}/leaderboard`),
}
