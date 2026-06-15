import { useEffect, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import type { StyleSpecification } from "maplibre-gl";
import { decodePolyline } from "../lib/polyline";
import type { Coordinate, RegionBounds, Route } from "../types/api";
import { prefersReducedMotion } from "../utils/reducedMotion";
import { CameraLayer } from "./CameraLayer";
import { tilesBase } from "../config";
import baseStyle from "../../public/map-style.json";

// Self-hosted vector tiles only — no third-party tile/CDN requests (FR-012a).
//
// MapLibre v5+ loads its worker from a blob: URL. Relative tile/font URLs in the
// style (e.g. /tiles/{z}/{x}/{y}.mvt) won't resolve from the worker's blob origin.
// We therefore build the style object here with absolute URLs (window.location.origin
// at call time) and pass the object directly to the Map constructor.
//
// Also: v5 defaults to globe projection, but our self-hosted tile data requires
// mercator. Keep projection: mercator; the map is then framed on the covered
// region (regionBounds, fetched from the backend).
//
// Layers come from public/map-style.json (single source of truth). Only the
// three runtime fields that need absolute URLs — glyphs, tiles, and projection
// — are patched here.
//
// glyphs and tiles can live on different origins: fonts are served by the
// frontend static host (page origin), while tiles come from tilesBase() — the
// same origin by default, but optionally a separate tiles CDN (tiles carry no
// user data; see config.ts).
function buildStyle(glyphOrigin: string, tilesOrigin: string): StyleSpecification {
  return {
    ...baseStyle,
    projection: { type: "mercator" },
    glyphs: glyphOrigin + "/fonts/{fontstack}/{range}.pbf",
    sources: {
      ...baseStyle.sources,
      openmaptiles: {
        ...baseStyle.sources.openmaptiles,
        tiles: [tilesOrigin + "/tiles/{z}/{x}/{y}.mvt"],
      },
    },
  } as unknown as StyleSpecification;
}

const ROUTE_SOURCE = "route";
const ROUTE_LAYER = "route-line";

// The fastest non-avoiding route, drawn as a dashed, muted comparison line
// beneath the primary route (feature 009-comparison-route).
const COMPARISON_SOURCE = "comparison";
const COMPARISON_LAYER = "comparison-line";

// Starting-address marker + recenter (feature 007-zoom-to-origin).
const ORIGIN_SOURCE = "origin";
const ORIGIN_LAYER = "origin-point";
// Fixed street-level zoom: shows the address's block and surrounding streets
// without zooming to the rooftop (the "responsibly" requirement — spec FR-002).
const ORIGIN_ZOOM = 16;
// Bounded animation length for the recenter; matches the route fitBounds duration
// for UX consistency (spec FR-003).
const ORIGIN_FLY_MS = 600;

interface Props {
  route: Route | null;
  // The confirmed starting location; when set, the map recenters on it and shows
  // a single marker. null/undefined removes the marker and leaves the map put.
  origin?: Coordinate | null;
  // Whether to draw the fastest-route comparison line (only ever drawn when the
  // avoiding route actually costs extra time). Defaults to shown.
  showComparison?: boolean;
  // Bounding box [[w,s],[e,n]] of the covered region; the map frames to it on
  // load. null until the backend bounds arrive (or if none exist), leaving the
  // map at its neutral initial view.
  regionBounds?: RegionBounds | null;
}

// One LineString FeatureCollection-free helper: a single LineString Feature.
function lineFeature(coordinates: [number, number][]): GeoJSON.Feature<GeoJSON.LineString> {
  return { type: "Feature", properties: {}, geometry: { type: "LineString", coordinates } };
}

// A coordinate is usable only when both components are finite numbers.
function isUsableCoordinate(c: Coordinate | null | undefined): c is Coordinate {
  return !!c && Number.isFinite(c.lat) && Number.isFinite(c.lng);
}

function originFeatures(origin: Coordinate | null | undefined): GeoJSON.FeatureCollection<GeoJSON.Point> {
  if (!isUsableCoordinate(origin)) return { type: "FeatureCollection", features: [] };
  return {
    type: "FeatureCollection",
    features: [{ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [origin.lng, origin.lat] } }],
  };
}

export function MapView({ route, origin, showComparison = true, regionBounds }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  // The created map promoted to state so child layers (CameraLayer) mount once
  // the instance exists (the ref alone wouldn't trigger a re-render).
  const [map, setMap] = useState<maplibregl.Map | null>(null);
  // Whether the map has already been framed on the covered region (done once,
  // when the backend bounds first arrive).
  const framedRef = useRef(false);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    const style = buildStyle(window.location.origin, tilesBase());
    mapRef.current = new maplibregl.Map({
      container: containerRef.current,
      style,
      // Neutral initial view; the map is framed on the covered region as soon as
      // regionBounds arrive (see the framing effect below). No region is hardcoded.
      center: [0, 0],
      zoom: 1,
    });
    setMap(mapRef.current);
    // End-to-end tests opt in (via window.__E2E__) to read the in-page map's
    // camera/marker state. This is never set in production, so the user's origin
    // coordinate is not exposed on a global in real use (anonymity).
    const w = window as unknown as { __E2E__?: boolean; __flckdMap?: maplibregl.Map };
    if (w.__E2E__) w.__flckdMap = mapRef.current;
    return () => {
      mapRef.current?.remove();
      mapRef.current = null;
      setMap(null);
      if (w.__flckdMap) delete w.__flckdMap;
    };
  }, []);

  // Frame the map on the covered region once its bounds load from the backend
  // (/coverage/bounds). This is what centers the region in the viewport on page
  // load — generically, with no hardcoded launch state. Runs a single time.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || framedRef.current || !regionBounds) return;

    const frame = () => {
      framedRef.current = true;
      map.fitBounds(regionBounds, { padding: 24, duration: 0 });
    };
    if (map.isStyleLoaded()) frame();
    else map.once("load", frame);
    return () => {
      map.off("load", frame);
    };
  }, [regionBounds]);

  // Draw the planned (recommended) route as the primary line and, when avoidance
  // costs extra time and the comparison is enabled, the fastest non-avoiding
  // route as a secondary dashed line beneath it. Frame whatever is shown.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    // No route (e.g. "completely avoid" found none, or an error): clear any drawn route
    // and comparison lines so a stale path never lingers under the message.
    if (!route) {
      const clear = () => {
        (map.getSource(ROUTE_SOURCE) as maplibregl.GeoJSONSource | undefined)?.setData(lineFeature([]));
        (map.getSource(COMPARISON_SOURCE) as maplibregl.GeoJSONSource | undefined)?.setData(lineFeature([]));
      };
      if (map.isStyleLoaded()) clear();
      else map.once("load", clear);
      return () => map.off("load", clear);
    }

    const routeCoords = decodePolyline(route.geometry, 6);
    if (routeCoords.length === 0) return;

    // The comparison line is drawn only when avoidance actually costs time
    // (added_duration_s > 0) and the user hasn't dismissed it (FR-002a/FR-006).
    const fc = route.fastest_comparison;
    const comparisonCoords =
      showComparison && fc.added_duration_s > 0 ? decodePolyline(fc.geometry, 6) : [];

    const draw = () => {
      const routeSrc = map.getSource(ROUTE_SOURCE) as maplibregl.GeoJSONSource | undefined;
      if (routeSrc) {
        routeSrc.setData(lineFeature(routeCoords));
      } else {
        map.addSource(ROUTE_SOURCE, { type: "geojson", data: lineFeature(routeCoords) });
        map.addLayer({
          id: ROUTE_LAYER,
          type: "line",
          source: ROUTE_SOURCE,
          layout: { "line-join": "round", "line-cap": "round" },
          paint: { "line-color": "#818cf8", "line-width": 4, "line-opacity": 0.9 },
        });
      }

      // Comparison line. The layer is created only when there's actually a
      // comparison to draw, so a free (no-penalty) route never adds a second
      // line. Once created, it's emptied via setData when the comparison is
      // hidden or a later plan has no penalty, leaving no stale line (FR-009).
      // It's inserted beneath the route line so the recommended route stays
      // dominant even over shared segments (FR-008).
      const compSrc = map.getSource(COMPARISON_SOURCE) as maplibregl.GeoJSONSource | undefined;
      if (compSrc) {
        compSrc.setData(lineFeature(comparisonCoords));
      } else if (comparisonCoords.length > 0) {
        map.addSource(COMPARISON_SOURCE, { type: "geojson", data: lineFeature(comparisonCoords) });
        map.addLayer(
          {
            id: COMPARISON_LAYER,
            type: "line",
            source: COMPARISON_SOURCE,
            layout: { "line-join": "round", "line-cap": "round" },
            paint: {
              "line-color": "#9ca3af",
              "line-width": 3,
              "line-opacity": 0.7,
              "line-dasharray": [2, 2],
            },
          },
          map.getLayer(ROUTE_LAYER) ? ROUTE_LAYER : undefined, // beneath the route line
        );
      }

      const allCoords = routeCoords.concat(comparisonCoords);
      const bounds = allCoords.reduce(
        (b, c) => b.extend(c),
        new maplibregl.LngLatBounds(allCoords[0], allCoords[0]),
      );
      // Honour reduced-motion (as the origin-recenter and camera-cluster effects
      // already do): snap instead of animating the camera pan.
      map.fitBounds(bounds, { padding: 48, duration: prefersReducedMotion() ? 0 : 600 });
    };

    if (map.isStyleLoaded()) {
      draw();
      return;
    }
    map.once("load", draw);
    return () => {
      map.off("load", draw);
    };
  }, [route, showComparison]);

  // Recenter on the confirmed starting address and show a single marker there.
  // Recentering only touches the self-hosted style/tiles — the coordinate never
  // leaves the client (anonymity, spec FR-009).
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    const apply = () => {
      // The marker lives in one GeoJSON source (same pattern as CameraLayer), so a
      // single setData covers add / move / remove — at most one marker ever exists
      // (spec FR-011/012/013, SC-007).
      const features = originFeatures(origin);
      let existing = map.getSource(ORIGIN_SOURCE) as maplibregl.GeoJSONSource | undefined;
      if (!existing && isUsableCoordinate(origin)) {
        map.addSource(ORIGIN_SOURCE, { type: "geojson", data: features });
        map.addLayer({
          id: ORIGIN_LAYER,
          type: "circle",
          source: ORIGIN_SOURCE,
          paint: {
            "circle-radius": 7,
            "circle-color": "#16a34a",
            "circle-stroke-width": 2,
            "circle-stroke-color": "#fff",
          },
        });
        existing = map.getSource(ORIGIN_SOURCE) as maplibregl.GeoJSONSource | undefined;
      }
      existing?.setData(features);

      // Only move the camera for a usable coordinate; an unset/invalid origin just
      // clears the marker and leaves the view untouched (spec FR-007/013).
      if (isUsableCoordinate(origin)) {
        const target: [number, number] = [origin.lng, origin.lat];
        if (prefersReducedMotion()) {
          map.jumpTo({ center: target, zoom: ORIGIN_ZOOM });
        } else {
          map.flyTo({ center: target, zoom: ORIGIN_ZOOM, duration: ORIGIN_FLY_MS });
        }
      }
    };

    // Only the initial addSource/addLayer needs the style loaded; setData and the
    // camera do not. Crucially, once the source exists we must NOT re-gate on
    // isStyleLoaded() — it transiently returns false right after addSource, and
    // `once("load")` only ever fires once, so a quick follow-up change (e.g. clear)
    // would be dropped forever, stranding a stale marker.
    if (map.getSource(ORIGIN_SOURCE) || map.isStyleLoaded()) {
      apply();
      return;
    }
    map.once("load", apply);
    return () => {
      map.off("load", apply);
    };
  }, [origin]);

  return (
    <div ref={containerRef} className="map-view" style={{ width: "100%", height: "100%" }}>
      {map && <CameraLayer map={map} />}
    </div>
  );
}
