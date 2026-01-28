/**
 * MapLibre GL map component with vehicle markers
 *
 * FIXED: P1-4 - Added clustering for 50+ vehicles
 * FIXED: P2-1 - Added vehicle highlight on selection
 * FIXED: P2-4 - Added map legend
 *
 * Includes mobile-friendly touch controls:
 * - Lock/Unlock toggle to prevent scroll trapping
 * - Two-finger pan requirement when locked
 * - Automatic clustering when vehicle count exceeds threshold
 * - Visual highlight for selected vehicle
 * - Collapsible legend explaining markers
 */
import { useEffect, useRef, useState, useCallback } from 'react'
import maplibregl from 'maplibre-gl'
import type { VehiclePosition } from '../../api/client'
import { useThemeStore, type ResolvedTheme } from '../../stores/themeStore'

// Map tile sources for different themes
// FIXED: Section A - Support light/dark/auto theme switching
const TILE_SOURCES = {
  dark: {
    url: 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>',
  },
  sunlight: {
    url: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>',
  },
}

// Topo tile source (OpenTopoMap - contours, hillshade, trails)
const TOPO_TILE_SOURCE = {
  urls: [
    'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
    'https://b.tile.opentopomap.org/{z}/{x}/{y}.png',
    'https://c.tile.opentopomap.org/{z}/{x}/{y}.png',
  ],
  attribution: '&copy; <a href="https://opentopomap.org">OpenTopoMap</a> (<a href="https://creativecommons.org/licenses/by-sa/3.0/">CC-BY-SA</a>) &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  maxzoom: 17,
}

type MapLayer = 'topo' | 'streets'

interface MapProps {
  positions: VehiclePosition[]
  onVehicleClick?: (vehicleId: string) => void
  selectedVehicleId?: string | null // FIXED: P2-1 - Support highlighting selected vehicle
  courseGeoJSON?: GeoJSON.FeatureCollection | null // Course line to display on map
}

// Vehicle marker colors by position
const POSITION_COLORS: Record<number, string> = {
  1: '#FFD700', // Gold
  2: '#C0C0C0', // Silver
  3: '#CD7F32', // Bronze
}
const DEFAULT_COLOR = '#4d94ff'

// Threshold for enabling clustering
const CLUSTER_THRESHOLD = 15

// FIXED: P2-5 - Stale data threshold (5 seconds)
const STALE_THRESHOLD_MS = 5000

// Helper to check if position data is stale
function isPositionStale(pos: VehiclePosition): boolean {
  if (!pos.last_update_ms) return false
  return Date.now() - pos.last_update_ms > STALE_THRESHOLD_MS
}

// Convert positions to GeoJSON for clustering
// FIXED: P2-5 - Added stale status to GeoJSON properties
function positionsToGeoJSON(positions: VehiclePosition[]): GeoJSON.FeatureCollection<GeoJSON.Point> {
  return {
    type: 'FeatureCollection',
    features: positions.map((pos, index) => ({
      type: 'Feature' as const,
      properties: {
        vehicle_id: pos.vehicle_id,
        vehicle_number: pos.vehicle_number,
        team_name: pos.team_name,
        rank: index + 1, // Rank based on sort order
        heading_deg: pos.heading_deg,
        is_stale: isPositionStale(pos) ? 1 : 0, // P2-5: Include stale status
      },
      geometry: {
        type: 'Point' as const,
        coordinates: [pos.lon, pos.lat],
      },
    })),
  }
}

/**
 * FIXED: P2-4 - Map Legend Component
 * Collapsible legend explaining marker colors and clustering
 */
function MapLegend({
  isOpen,
  onToggle,
  showClusters,
}: {
  isOpen: boolean
  onToggle: () => void
  showClusters: boolean
}) {
  return (
    <div className="absolute bottom-2 left-2 z-10">
      {/* Toggle button */}
      <button
        onClick={onToggle}
        className="bg-black/80 text-white text-xs px-2 py-1.5 rounded-lg flex items-center gap-1.5 hover:bg-black/90 transition-colors"
        aria-expanded={isOpen}
        aria-label="Toggle map legend"
      >
        <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
        </svg>
        <span>Legend</span>
        <svg
          className={`w-3 h-3 transition-transform ${isOpen ? 'rotate-180' : ''}`}
          fill="none" viewBox="0 0 24 24" stroke="currentColor"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 15l7-7 7 7" />
        </svg>
      </button>

      {/* Legend content */}
      {isOpen && (
        <div className="mt-1 bg-black/90 text-white text-xs rounded-lg p-3 min-w-[160px] space-y-2">
          {/* Position markers */}
          <div>
            <div className="font-semibold text-gray-400 uppercase text-[10px] tracking-wide mb-1.5">
              Positions
            </div>
            <div className="space-y-1.5">
              <LegendItem color="#FFD700" label="1st Place" textColor="#000" />
              <LegendItem color="#C0C0C0" label="2nd Place" textColor="#000" />
              <LegendItem color="#CD7F32" label="3rd Place" textColor="#000" />
              <LegendItem color="#4d94ff" label="Other" textColor="#fff" />
            </div>
          </div>

          {/* Cluster explanation (only when clustering active) */}
          {showClusters && (
            <div className="border-t border-gray-700 pt-2">
              <div className="font-semibold text-gray-400 uppercase text-[10px] tracking-wide mb-1.5">
                Clusters
              </div>
              <div className="space-y-1.5">
                <ClusterItem color="#4d94ff" label="< 10 vehicles" />
                <ClusterItem color="#ff9800" label="10-29 vehicles" />
                <ClusterItem color="#f44336" label="30+ vehicles" />
              </div>
              <div className="text-[10px] text-gray-500 mt-1.5">
                Tap cluster to expand
              </div>
            </div>
          )}

          {/* Selected vehicle */}
          <div className="border-t border-gray-700 pt-2">
            <div className="flex items-center gap-2">
              <div
                className="w-5 h-5 rounded-full flex items-center justify-center text-[8px] font-bold"
                style={{
                  background: '#4d94ff',
                  border: '2px solid white',
                  boxShadow: '0 0 0 3px rgba(255,255,255,0.8), 0 0 10px rgba(77,148,255,0.9)',
                }}
              >
                #
              </div>
              <span className="text-gray-300">Selected</span>
            </div>
          </div>

          {/* FIXED: P2-5 - Stale data indication */}
          <div className="border-t border-gray-700 pt-2">
            <div className="flex items-center gap-2">
              <div
                className="w-5 h-5 rounded-full flex items-center justify-center text-[8px] font-bold relative"
                style={{
                  background: '#4d94ff',
                  border: '2px solid #ef4444',
                  opacity: 0.5,
                }}
              >
                #
                <div
                  className="absolute -top-0.5 -right-0.5 w-2 h-2 bg-red-500 rounded-full border border-white"
                />
              </div>
              <span className="text-gray-300">Stale ({'>'}5s old)</span>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function LegendItem({ color, label, textColor }: { color: string; label: string; textColor: string }) {
  return (
    <div className="flex items-center gap-2">
      <div
        className="w-5 h-5 rounded-full flex items-center justify-center text-[8px] font-bold"
        style={{ background: color, border: '2px solid white', color: textColor }}
      >
        #
      </div>
      <span className="text-gray-300">{label}</span>
    </div>
  )
}

function ClusterItem({ color, label }: { color: string; label: string }) {
  return (
    <div className="flex items-center gap-2">
      <div
        className="w-5 h-5 rounded-full flex items-center justify-center text-[9px] font-bold text-white"
        style={{ background: color, border: '2px solid white' }}
      >
        5
      </div>
      <span className="text-gray-300">{label}</span>
    </div>
  )
}

export default function Map({ positions, onVehicleClick, selectedVehicleId, courseGeoJSON }: MapProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<maplibregl.Map | null>(null)
  const markersRef = useRef(new globalThis.Map<string, maplibregl.Marker>())
  const clusteringEnabledRef = useRef(false)
  // FIXED: P2-1 - Track previously selected vehicle to remove highlight
  const prevSelectedRef = useRef<string | null>(null)

  // FIXED: Section A - Subscribe to theme for tile source switching
  const resolvedTheme = useThemeStore((state) => state.resolvedTheme)
  const prevThemeRef = useRef<ResolvedTheme | null>(null)

  // Map lock state for mobile - locked by default to allow page scrolling
  const [isMapLocked, setIsMapLocked] = useState(true)
  const [showUnlockHint, setShowUnlockHint] = useState(false)
  // FIXED: P2-4 - Map legend state
  const [showLegend, setShowLegend] = useState(false)
  // Map layer: topo (default for race viewing) or streets
  const [mapLayer, setMapLayer] = useState<MapLayer>('topo')
  const prevLayerRef = useRef<MapLayer>('topo')

  // Determine if we should use clustering based on vehicle count
  const shouldCluster = positions.length >= CLUSTER_THRESHOLD

  // Listen for "Center on Race" custom event
  useEffect(() => {
    const handleCenterOnRace = (event: CustomEvent<{ positions: VehiclePosition[], courseGeoJSON?: GeoJSON.FeatureCollection | null }>) => {
      const map = mapRef.current
      if (!map) return

      const bounds = new maplibregl.LngLatBounds()
      let hasBounds = false

      // Add course bounds if available
      if (event.detail.courseGeoJSON) {
        event.detail.courseGeoJSON.features.forEach((feature) => {
          if (feature.geometry.type === 'LineString') {
            feature.geometry.coordinates.forEach((coord) => {
              bounds.extend(coord as [number, number])
              hasBounds = true
            })
          } else if (feature.geometry.type === 'Point') {
            bounds.extend(feature.geometry.coordinates as [number, number])
            hasBounds = true
          }
        })
      }

      // Add vehicle positions
      if (event.detail.positions.length > 0) {
        event.detail.positions.forEach((pos) => {
          bounds.extend([pos.lon, pos.lat])
          hasBounds = true
        })
      }

      // Fit to bounds if we have any
      if (hasBounds && !bounds.isEmpty()) {
        map.fitBounds(bounds, {
          padding: { top: 60, bottom: 60, left: 40, right: 40 },
          maxZoom: 14,
          duration: 800,
        })
      }
    }

    window.addEventListener('argus:centerOnRace', handleCenterOnRace as EventListener)
    return () => {
      window.removeEventListener('argus:centerOnRace', handleCenterOnRace as EventListener)
    }
  }, [])

  // FIXED: P2-1 - Highlight selected vehicle marker
  useEffect(() => {
    // Remove highlight from previously selected marker
    if (prevSelectedRef.current && prevSelectedRef.current !== selectedVehicleId) {
      const prevMarker = markersRef.current.get(prevSelectedRef.current)
      if (prevMarker) {
        const el = prevMarker.getElement()
        el.classList.remove('marker-selected')
        const inner = el.querySelector('.marker-inner') as HTMLElement
        if (inner) {
          inner.style.boxShadow = '0 2px 8px rgba(0,0,0,0.4)'
          inner.style.transform = inner.style.transform.replace(' scale(1.3)', '')
        }
      }
    }

    // Add highlight to newly selected marker
    if (selectedVehicleId) {
      const marker = markersRef.current.get(selectedVehicleId)
      if (marker) {
        const el = marker.getElement()
        el.classList.add('marker-selected')
        const inner = el.querySelector('.marker-inner') as HTMLElement
        if (inner) {
          // Enlarged with bright glow effect
          inner.style.boxShadow = '0 0 0 4px rgba(255,255,255,0.8), 0 0 20px rgba(77,148,255,0.9)'
          if (!inner.style.transform.includes('scale(1.3)')) {
            inner.style.transform = (inner.style.transform || '') + ' scale(1.3)'
          }
        }

        // Pan to selected vehicle
        const map = mapRef.current
        if (map) {
          const pos = positions.find((p) => p.vehicle_id === selectedVehicleId)
          if (pos) {
            map.easeTo({
              center: [pos.lon, pos.lat],
              duration: 500,
            })
          }
        }
      }
    }

    prevSelectedRef.current = selectedVehicleId || null
  }, [selectedVehicleId, positions])

  // Get tile source for current theme
  const getTileSource = useCallback((theme: ResolvedTheme) => {
    return TILE_SOURCES[theme] || TILE_SOURCES.dark
  }, [])

  // Build MapLibre style object for the current layer + theme
  const buildStyle = useCallback((layer: MapLayer, theme: ResolvedTheme): maplibregl.StyleSpecification => {
    if (layer === 'topo') {
      return {
        version: 8,
        sources: {
          'base-tiles': {
            type: 'raster',
            tiles: TOPO_TILE_SOURCE.urls,
            tileSize: 256,
            attribution: TOPO_TILE_SOURCE.attribution,
            maxzoom: TOPO_TILE_SOURCE.maxzoom,
          }
        },
        layers: [{
          id: 'base-tiles',
          type: 'raster',
          source: 'base-tiles',
          minzoom: 0,
          maxzoom: TOPO_TILE_SOURCE.maxzoom,
        }]
      }
    }
    const tileSource = getTileSource(theme)
    return {
      version: 8,
      sources: {
        'base-tiles': {
          type: 'raster',
          tiles: [tileSource.url],
          tileSize: 256,
          attribution: tileSource.attribution,
        }
      },
      layers: [{
        id: 'base-tiles',
        type: 'raster',
        source: 'base-tiles',
        minzoom: 0,
        maxzoom: 19,
      }]
    }
  }, [getTileSource])

  // Initialize map
  useEffect(() => {
    if (!containerRef.current || mapRef.current) return

    // Use topo tiles by default for race viewing
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: buildStyle(mapLayer, resolvedTheme),
      center: [-116.38, 34.12], // Default to KOH area
      zoom: 12,
      attributionControl: false,
      // Disable interactions when locked (will be controlled dynamically)
      dragPan: false,
      scrollZoom: false,
      touchZoomRotate: false,
      doubleClickZoom: false,
    })

    // Add zoom controls (always visible)
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right')

    mapRef.current = map
    prevThemeRef.current = resolvedTheme

    return () => {
      map.remove()
      mapRef.current = null
    }
  }, [])

  // Handle map lock state changes
  useEffect(() => {
    const map = mapRef.current
    if (!map) return

    if (isMapLocked) {
      map.dragPan.disable()
      map.scrollZoom.disable()
      map.touchZoomRotate.disable()
      map.doubleClickZoom.disable()
    } else {
      map.dragPan.enable()
      map.scrollZoom.enable()
      map.touchZoomRotate.enable()
      map.doubleClickZoom.enable()
    }
  }, [isMapLocked])

  // Display course line on map when available
  useEffect(() => {
    const map = mapRef.current
    if (!map || !courseGeoJSON) return

    const addCourseLayer = () => {
      // Remove existing course layers if present
      if (map.getLayer('course-line')) map.removeLayer('course-line')
      if (map.getLayer('course-line-outline')) map.removeLayer('course-line-outline')
      if (map.getSource('course')) map.removeSource('course')

      // Add course source
      map.addSource('course', {
        type: 'geojson',
        data: courseGeoJSON,
      })

      // Add outline layer (wider, darker line behind main line)
      map.addLayer({
        id: 'course-line-outline',
        type: 'line',
        source: 'course',
        layout: {
          'line-join': 'round',
          'line-cap': 'round',
        },
        paint: {
          'line-color': '#000000',
          'line-width': 6,
          'line-opacity': 0.5,
        },
      })

      // Add main course line
      map.addLayer({
        id: 'course-line',
        type: 'line',
        source: 'course',
        layout: {
          'line-join': 'round',
          'line-cap': 'round',
        },
        paint: {
          'line-color': '#ff6b35', // Orange course line
          'line-width': 3,
          'line-opacity': 0.9,
        },
      })

      // Fit map to course bounds
      const bounds = new maplibregl.LngLatBounds()
      courseGeoJSON.features.forEach((feature) => {
        if (feature.geometry.type === 'LineString') {
          feature.geometry.coordinates.forEach((coord) => {
            bounds.extend(coord as [number, number])
          })
        } else if (feature.geometry.type === 'Point') {
          bounds.extend(feature.geometry.coordinates as [number, number])
        }
      })

      if (!bounds.isEmpty()) {
        map.fitBounds(bounds, { padding: 50, maxZoom: 14 })
      }
    }

    if (map.loaded()) {
      addCourseLayer()
    } else {
      map.once('load', addCourseLayer)
    }
  }, [courseGeoJSON])

  // Show hint when user tries to interact with locked map
  const handleMapTouch = useCallback(() => {
    if (isMapLocked) {
      setShowUnlockHint(true)
      setTimeout(() => setShowUnlockHint(false), 2000)
    }
  }, [isMapLocked])

  // Setup clustering layers (called once when map loads)
  const setupClusteringLayers = useCallback((map: maplibregl.Map) => {
    // Add GeoJSON source with clustering enabled
    map.addSource('vehicles', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features: [] },
      cluster: true,
      clusterMaxZoom: 14, // Max zoom to cluster points
      clusterRadius: 50, // Radius of each cluster
    })

    // Cluster circles
    map.addLayer({
      id: 'clusters',
      type: 'circle',
      source: 'vehicles',
      filter: ['has', 'point_count'],
      paint: {
        'circle-color': [
          'step',
          ['get', 'point_count'],
          '#4d94ff', // Blue for small clusters
          10, '#ff9800', // Orange for medium
          30, '#f44336', // Red for large
        ],
        'circle-radius': [
          'step',
          ['get', 'point_count'],
          20, // Small cluster
          10, 25, // Medium cluster
          30, 35, // Large cluster
        ],
        'circle-stroke-width': 3,
        'circle-stroke-color': '#fff',
      },
    })

    // Cluster count labels
    map.addLayer({
      id: 'cluster-count',
      type: 'symbol',
      source: 'vehicles',
      filter: ['has', 'point_count'],
      layout: {
        'text-field': '{point_count_abbreviated}',
        'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
        'text-size': 14,
      },
      paint: {
        'text-color': '#ffffff',
      },
    })

    // Individual vehicle points (unclustered)
    // FIXED: P2-5 - Added stale marker styling with reduced opacity and red stroke
    map.addLayer({
      id: 'unclustered-point',
      type: 'circle',
      source: 'vehicles',
      filter: ['!', ['has', 'point_count']],
      paint: {
        'circle-color': [
          'match',
          ['get', 'rank'],
          1, '#FFD700', // Gold
          2, '#C0C0C0', // Silver
          3, '#CD7F32', // Bronze
          '#4d94ff', // Default blue
        ],
        'circle-radius': 12,
        'circle-stroke-width': 2,
        // P2-5: Red stroke for stale markers, white for fresh
        'circle-stroke-color': [
          'case',
          ['==', ['get', 'is_stale'], 1],
          '#ef4444', // Red for stale
          '#fff', // White for fresh
        ],
        // P2-5: Reduced opacity for stale markers
        'circle-opacity': [
          'case',
          ['==', ['get', 'is_stale'], 1],
          0.5, // 50% opacity for stale
          1, // Full opacity for fresh
        ],
      },
    })

    // Vehicle number labels for unclustered points
    // FIXED: P2-5 - Added opacity for stale markers
    map.addLayer({
      id: 'unclustered-label',
      type: 'symbol',
      source: 'vehicles',
      filter: ['!', ['has', 'point_count']],
      layout: {
        'text-field': ['get', 'vehicle_number'],
        'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
        'text-size': 10,
        'text-allow-overlap': true,
      },
      paint: {
        'text-color': [
          'match',
          ['get', 'rank'],
          1, '#000', // Dark on gold
          2, '#000', // Dark on silver
          3, '#000', // Dark on bronze
          '#fff', // White on blue
        ],
        // P2-5: Reduced opacity for stale markers
        'text-opacity': [
          'case',
          ['==', ['get', 'is_stale'], 1],
          0.5, // 50% opacity for stale
          1, // Full opacity for fresh
        ],
      },
    })

    // Click on cluster to zoom in
    map.on('click', 'clusters', async (e) => {
      const features = map.queryRenderedFeatures(e.point, { layers: ['clusters'] })
      if (!features.length) return

      const clusterId = features[0].properties?.cluster_id
      const source = map.getSource('vehicles') as maplibregl.GeoJSONSource

      try {
        const zoom = await source.getClusterExpansionZoom(clusterId)
        map.easeTo({
          center: (features[0].geometry as GeoJSON.Point).coordinates as [number, number],
          zoom: zoom,
        })
      } catch (err) {
        console.error('Error expanding cluster:', err)
      }
    })

    // Click on unclustered point
    map.on('click', 'unclustered-point', (e) => {
      const features = map.queryRenderedFeatures(e.point, { layers: ['unclustered-point'] })
      if (features.length > 0) {
        const vehicleId = features[0].properties?.vehicle_id
        if (vehicleId && onVehicleClick) {
          onVehicleClick(vehicleId)
        }
      }
    })

    // Change cursor on hover
    map.on('mouseenter', 'clusters', () => {
      map.getCanvas().style.cursor = 'pointer'
    })
    map.on('mouseleave', 'clusters', () => {
      map.getCanvas().style.cursor = ''
    })
    map.on('mouseenter', 'unclustered-point', () => {
      map.getCanvas().style.cursor = 'pointer'
    })
    map.on('mouseleave', 'unclustered-point', () => {
      map.getCanvas().style.cursor = ''
    })
  }, [onVehicleClick])

  // FIXED: Section A - Update map tiles when theme changes
  // (Moved after setupClusteringLayers to fix use-before-declaration)
  // Rebuild tiles when theme changes (only affects streets layer)
  useEffect(() => {
    const map = mapRef.current
    if (!map) return
    // Skip if theme hasn't changed, or if we're on topo (theme doesn't affect topo tiles)
    if (prevThemeRef.current === resolvedTheme) return
    if (mapLayer === 'topo') {
      prevThemeRef.current = resolvedTheme
      return
    }

    const center = map.getCenter()
    const zoom = map.getZoom()
    map.setStyle(buildStyle(mapLayer, resolvedTheme))
    map.setCenter(center)
    map.setZoom(zoom)

    if (clusteringEnabledRef.current) {
      map.once('style.load', () => setupClusteringLayers(map))
    }

    prevThemeRef.current = resolvedTheme
  }, [resolvedTheme, mapLayer, buildStyle, setupClusteringLayers])

  // Rebuild tiles when layer changes (topo ↔ streets)
  useEffect(() => {
    const map = mapRef.current
    if (!map || prevLayerRef.current === mapLayer) return

    const center = map.getCenter()
    const zoom = map.getZoom()
    map.setStyle(buildStyle(mapLayer, resolvedTheme))
    map.setCenter(center)
    map.setZoom(zoom)

    if (clusteringEnabledRef.current) {
      map.once('style.load', () => setupClusteringLayers(map))
    }

    prevLayerRef.current = mapLayer
  }, [mapLayer, resolvedTheme, buildStyle, setupClusteringLayers])

  // Update markers when positions change
  useEffect(() => {
    const map = mapRef.current
    if (!map) return

    // Sort positions by update time (most recent first = higher rank)
    const sortedPositions = [...positions].sort(
      (a, b) => (b.last_update_ms || 0) - (a.last_update_ms || 0)
    )

    // Handle clustering mode
    if (shouldCluster) {
      // Remove individual markers if switching from non-clustered mode
      if (!clusteringEnabledRef.current) {
        markersRef.current.forEach((marker) => marker.remove())
        markersRef.current.clear()

        // Setup clustering layers if not already done
        if (!map.getSource('vehicles')) {
          map.once('load', () => setupClusteringLayers(map))
          if (map.loaded()) {
            setupClusteringLayers(map)
          }
        }
        clusteringEnabledRef.current = true
      }

      // Update the GeoJSON source
      const source = map.getSource('vehicles') as maplibregl.GeoJSONSource
      if (source) {
        source.setData(positionsToGeoJSON(sortedPositions))
      }
    } else {
      // Non-clustering mode: use individual markers
      if (clusteringEnabledRef.current) {
        // Remove clustering layers if switching from clustered mode
        if (map.getLayer('cluster-count')) map.removeLayer('cluster-count')
        if (map.getLayer('clusters')) map.removeLayer('clusters')
        if (map.getLayer('unclustered-label')) map.removeLayer('unclustered-label')
        if (map.getLayer('unclustered-point')) map.removeLayer('unclustered-point')
        if (map.getSource('vehicles')) map.removeSource('vehicles')
        clusteringEnabledRef.current = false
      }

      const currentIds = new Set(positions.map((p) => p.vehicle_id))

      // Remove markers for vehicles no longer present
      markersRef.current.forEach((marker, id) => {
        if (!currentIds.has(id)) {
          marker.remove()
          markersRef.current.delete(id)
        }
      })

      // Update or create markers
      sortedPositions.forEach((pos, index) => {
        let marker = markersRef.current.get(pos.vehicle_id)

        // FIXED: P2-5 - Check if position data is stale
        const stale = isPositionStale(pos)

        if (marker) {
          // Update existing marker position
          marker.setLngLat([pos.lon, pos.lat])
          // FIXED: P2-5 - Update stale status for existing marker
          updateMarkerStaleStatus(marker, stale)
        } else {
          // Create new marker with stale status
          const el = createMarkerElement(pos, index + 1, stale)

          marker = new maplibregl.Marker({ element: el })
            .setLngLat([pos.lon, pos.lat])
            .addTo(map)

          // Add click handler
          el.addEventListener('click', () => {
            onVehicleClick?.(pos.vehicle_id)
          })

          markersRef.current.set(pos.vehicle_id, marker)
        }

        // Update rotation if heading available
        if (pos.heading_deg !== null) {
          const el = marker.getElement()
          const inner = el.querySelector('.marker-inner') as HTMLElement
          if (inner) {
            // FIXED: P2-5 - Preserve stale opacity when rotating
            const currentOpacity = inner.style.opacity || '1'
            inner.style.transform = `rotate(${pos.heading_deg}deg)`
            inner.style.opacity = currentOpacity
          }
        }
      })
    }

    // Fit bounds to all positions on first load
    if (positions.length > 0 && !map.loaded()) {
      const bounds = new maplibregl.LngLatBounds()
      positions.forEach((pos) => bounds.extend([pos.lon, pos.lat]))
      map.fitBounds(bounds, { padding: 50, maxZoom: 14 })
    }
  }, [positions, onVehicleClick, shouldCluster, setupClusteringLayers])

  return (
    <div className="relative w-full h-full">
      {/* Map container */}
      <div
        ref={containerRef}
        className="w-full h-full"
        style={{ touchAction: isMapLocked ? 'pan-y' : 'none' }}
        onTouchStart={handleMapTouch}
      />

      {/* Lock/Unlock button - visible on all screen sizes */}
      <button
        onClick={() => setIsMapLocked(!isMapLocked)}
        className={`map-lock-button ${isMapLocked ? '' : 'map-lock-button-locked'}`}
        aria-label={isMapLocked ? 'Unlock map for panning' : 'Lock map to allow scrolling'}
      >
        {isMapLocked ? (
          <>
            <LockIcon />
            <span className="hidden sm:inline">Click to Pan</span>
            <span className="sm:hidden">Tap to Pan</span>
          </>
        ) : (
          <>
            <UnlockIcon />
            <span>Lock Map</span>
          </>
        )}
      </button>

      {/* Unlock hint overlay */}
      {showUnlockHint && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none z-10">
          <div className="bg-black/80 text-white px-4 py-2 rounded-lg text-sm font-medium animate-pulse">
            Tap "Tap to Pan" to interact with map
          </div>
        </div>
      )}

      {/* Lock overlay when map is locked - visual indicator only */}
      {isMapLocked && (
        <div className="absolute inset-0 pointer-events-none" />
      )}

      {/* Layer toggle (Topo / Streets) */}
      <div className="absolute top-2 left-2 z-10 flex flex-col gap-1.5">
        <div className="bg-black/80 rounded-lg flex overflow-hidden text-xs font-medium">
          <button
            onClick={() => setMapLayer('topo')}
            className={`px-2.5 py-1.5 transition-colors ${
              mapLayer === 'topo'
                ? 'bg-blue-600 text-white'
                : 'text-gray-300 hover:text-white hover:bg-white/10'
            }`}
            aria-pressed={mapLayer === 'topo'}
          >
            Topo
          </button>
          <button
            onClick={() => setMapLayer('streets')}
            className={`px-2.5 py-1.5 transition-colors ${
              mapLayer === 'streets'
                ? 'bg-blue-600 text-white'
                : 'text-gray-300 hover:text-white hover:bg-white/10'
            }`}
            aria-pressed={mapLayer === 'streets'}
          >
            Streets
          </button>
        </div>

        {/* Clustering indicator */}
        {shouldCluster && (
          <div className="bg-black/70 text-white text-xs px-2 py-1 rounded-lg flex items-center gap-1.5">
            <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
            </svg>
            <span>{positions.length} vehicles (clustered)</span>
          </div>
        )}
      </div>

      {/* FIXED: P2-4 - Map Legend */}
      <MapLegend
        isOpen={showLegend}
        onToggle={() => setShowLegend(!showLegend)}
        showClusters={shouldCluster}
      />
    </div>
  )
}

// FIXED: P2-5 - Create marker element with optional stale styling
function createMarkerElement(pos: VehiclePosition, rank: number, isStale: boolean): HTMLElement {
  const color = POSITION_COLORS[rank] || DEFAULT_COLOR

  const el = document.createElement('div')
  el.className = `vehicle-marker cursor-pointer ${isStale ? 'marker-stale' : ''}`
  el.style.cssText = `
    width: 36px;
    height: 36px;
    display: flex;
    align-items: center;
    justify-content: center;
  `

  // FIXED: P2-5 - Stale markers get reduced opacity and warning border
  const staleStyles = isStale ? `
    opacity: 0.5;
    border-color: #ef4444;
    animation: pulse-stale 1.5s ease-in-out infinite;
  ` : ''

  el.innerHTML = `
    <div class="marker-inner" style="
      width: 28px;
      height: 28px;
      background: ${color};
      border: 2px solid ${isStale ? '#ef4444' : 'white'};
      border-radius: 50%;
      box-shadow: 0 2px 8px rgba(0,0,0,0.4);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 10px;
      font-weight: bold;
      color: ${rank <= 3 ? '#000' : '#fff'};
      transition: transform 0.3s ease, opacity 0.3s ease, border-color 0.3s ease;
      ${staleStyles}
    ">
      ${pos.vehicle_number}
    </div>
    ${isStale ? `<div class="stale-indicator" style="
      position: absolute;
      top: -2px;
      right: -2px;
      width: 8px;
      height: 8px;
      background: #ef4444;
      border-radius: 50%;
      border: 1px solid white;
      animation: pulse 1.5s ease-in-out infinite;
    "></div>` : ''}
  `

  return el
}

// FIXED: P2-5 - Update marker stale status
function updateMarkerStaleStatus(marker: maplibregl.Marker, isStale: boolean): void {
  const el = marker.getElement()
  const inner = el.querySelector('.marker-inner') as HTMLElement
  let staleIndicator = el.querySelector('.stale-indicator') as HTMLElement

  if (isStale) {
    el.classList.add('marker-stale')
    if (inner) {
      inner.style.opacity = '0.5'
      inner.style.borderColor = '#ef4444'
    }
    // Add stale indicator if not present
    if (!staleIndicator) {
      staleIndicator = document.createElement('div')
      staleIndicator.className = 'stale-indicator'
      staleIndicator.style.cssText = `
        position: absolute;
        top: -2px;
        right: -2px;
        width: 8px;
        height: 8px;
        background: #ef4444;
        border-radius: 50%;
        border: 1px solid white;
        animation: pulse 1.5s ease-in-out infinite;
      `
      el.appendChild(staleIndicator)
    }
  } else {
    el.classList.remove('marker-stale')
    if (inner) {
      inner.style.opacity = '1'
      inner.style.borderColor = 'white'
    }
    // Remove stale indicator if present
    if (staleIndicator) {
      staleIndicator.remove()
    }
  }
}

// Lock icon SVG
function LockIcon() {
  return (
    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
        d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
    </svg>
  )
}

// Unlock icon SVG
function UnlockIcon() {
  return (
    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
        d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z" />
    </svg>
  )
}
