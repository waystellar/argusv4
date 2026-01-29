/**
 * MAP-STYLE-2 + CLOUD-MAP-1: Centralized basemap configuration.
 *
 * Single source of truth for all map tile settings across the app.
 * Used by the shared Map component and the admin CourseMap.
 *
 * Layer stack (bottom to top):
 *   1. Background color (#f2efe9) — visible while tiles load
 *   2. CARTO Positron (light) — reliable base, always loads
 *   3. OpenTopoMap overlay — topographic contours + terrain shading
 *
 * When OpenTopoMap is up, the topo overlay renders on top of CARTO
 * giving the full topographic look. When OpenTopoMap is down, CARTO
 * Positron shows through as a clean light map — never a blank canvas.
 *
 * - forceLightMap flag prevents any theme-driven overrides.
 */
import type { StyleSpecification } from 'maplibre-gl'

export const basemapConfig = {
  /** Always render light tiles, ignoring the app's dark/sunlight theme. */
  forceLightMap: true,

  /** Reliable base layer — CARTO Positron (light). Always available. */
  base: {
    tiles: [
      'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      'https://b.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      'https://c.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    ],
    attribution:
      '&copy; <a href="https://carto.com/">CARTO</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    minzoom: 0,
    maxzoom: 20,
    tileSize: 256,
  },

  /** Topo overlay — OpenTopoMap with load-balanced mirrors.
   *  Renders contour lines and terrain shading on top of the base. */
  topo: {
    tiles: [
      'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
      'https://b.tile.opentopomap.org/{z}/{x}/{y}.png',
      'https://c.tile.opentopomap.org/{z}/{x}/{y}.png',
    ],
    attribution:
      '&copy; <a href="https://opentopomap.org">OpenTopoMap</a> (<a href="https://creativecommons.org/licenses/by-sa/3.0/">CC-BY-SA</a>)',
    minzoom: 0,
    maxzoom: 17,
    tileSize: 256,
    /** Opacity < 1 lets CARTO base show through if topo has holes or fails. */
    opacity: 0.9,
  },

  /** Background color matching OpenTopoMap's land color.
   *  Visible while tiles load or if both tile servers are unavailable. */
  backgroundColor: '#f2efe9',
} as const

/** Build a MapLibre StyleSpecification from the centralized basemap config. */
export function buildBasemapStyle(): StyleSpecification {
  return {
    version: 8,
    sources: {
      'base-tiles': {
        type: 'raster',
        tiles: basemapConfig.base.tiles as unknown as string[],
        tileSize: basemapConfig.base.tileSize,
        attribution: basemapConfig.base.attribution,
        maxzoom: basemapConfig.base.maxzoom,
      },
      'topo-tiles': {
        type: 'raster',
        tiles: basemapConfig.topo.tiles as unknown as string[],
        tileSize: basemapConfig.topo.tileSize,
        attribution: basemapConfig.topo.attribution,
        maxzoom: basemapConfig.topo.maxzoom,
      },
    },
    layers: [
      {
        id: 'background',
        type: 'background',
        paint: { 'background-color': basemapConfig.backgroundColor },
      },
      {
        id: 'base-tiles',
        type: 'raster',
        source: 'base-tiles',
        minzoom: basemapConfig.base.minzoom,
        maxzoom: basemapConfig.base.maxzoom,
      },
      {
        id: 'topo-tiles',
        type: 'raster',
        source: 'topo-tiles',
        minzoom: basemapConfig.topo.minzoom,
        maxzoom: basemapConfig.topo.maxzoom,
        paint: { 'raster-opacity': basemapConfig.topo.opacity },
      },
    ],
  }
}
