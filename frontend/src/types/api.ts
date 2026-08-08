// Working types for the app, mirroring the backend API contract
// (specs/.../contracts/openapi.yaml). They keep required fields and app-only
// `shape_index` explicit so consuming components do not need defensive checks.
export interface Coordinate {
  lat: number;
  lng: number;
}

export interface RouteRequest {
  origin: Coordinate;
  destination: Coordinate;
  locale?: string;
}

export interface Maneuver {
  type: string;
  localized_text: string;
  distance_m: number;
  shape_index?: number;
}

export interface FastestComparison {
  distance_m: number;
  duration_s: number;
  added_distance_m: number;
  added_duration_s: number;
  // Encoded polyline (precision 6) of the fastest non-avoiding route, so the
  // client can draw it as the comparison line.
  geometry: string;
  // How many monitored camera segments the fastest route would pass.
  cameras_passed_count: number;
}

export interface RemainingCamera {
  osm_way_id: number;
  location?: Coordinate;
}

export interface Route {
  geometry: string;
  distance_m: number;
  duration_s: number;
  maneuvers: Maneuver[];
  cameras_avoided_count: number;
  remaining_cameras: RemainingCamera[];
  is_fully_clean: boolean;
  fastest_comparison: FastestComparison;
  coverage_warning: string | null;
}

export interface GeocodeResult {
  label: string;
  lat: number;
  lng: number;
  type: string;
  confidence: number;
}

// Bounding box [[west, south], [east, north]] (lng/lat corners) of the covered
// region. The map frames to this on load, so no launch region is hardcoded.
export type RegionBounds = [[number, number], [number, number]];
