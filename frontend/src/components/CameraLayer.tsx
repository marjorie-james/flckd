import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import maplibregl from "maplibre-gl";
import { useCameras, type CameraPin } from "../services/cameraApi";
import { useDebounce } from "../hooks/useDebounce";
import { prefersReducedMotion } from "../utils/reducedMotion";
import { escapeHtml } from "../lib/escapeHtml";

// Renders the known cameras in the current viewport, clustered. Reference data
// only — never user data. Self-contained: given the live map it computes its own
// viewport bbox (debounced on moveend), fetches via useCameras, and manages the
// clustered GeoJSON source + layers, the watched-stretch lines, cluster-expand,
// and a details popup.
//
// Each camera is drawn ON the road it watches (snapped_location), with the
// monitored stretch faintly highlighted. Directional cameras get a vision cone
// pointing the way they face; omnidirectional (360°) cameras get a halo ring.

const SOURCE_ID = "cameras";
const SEGMENT_SOURCE = "camera-segments";
const SEGMENT_LAYER = "camera-segment-lines";
const CLUSTER_LAYER = "camera-clusters";
const CLUSTER_COUNT_LAYER = "camera-cluster-count";
const RING_LAYER = "camera-360-ring";
const POINT_LAYER = "camera-points";
const CONE_LAYER = "camera-cones";
// Route line id (from MapView) — camera layers go *below* it so they never
// obscure the planned route (FR-009).
const ROUTE_LAYER = "route-line";

// Cone icon ids (one per state so we can colour without SDF tinting).
const CONE_CONFIRMED = "cam-cone-confirmed";
const CONE_SUSPECT = "cam-cone-suspect";

const CLUSTER_RADIUS = 50;
const CLUSTER_MAX_ZOOM = 16;
const BBOX_DEBOUNCE_MS = 300;
// Mirrors the backend's per-request limit (CamerasController::VIEWPORT_LIMIT);
// reaching it means the viewport count may under-represent the true total
// (FR-011 — surfaced, not silent).
const SERVER_CAP = 5_000;
// The watched-stretch lines are NOT clustered (a clustered source holds points
// only), so they would otherwise be drawn for every camera at every zoom — the
// real render cost when the viewport holds many cameras. Gate them to higher
// zoom: the monitored stretch is only legible once you're looking at a
// neighbourhood, and by then few cameras are in view. Below this, only the
// clustered dots render.
const SEGMENT_MIN_ZOOM = 14;
// A camera is "suspect" (styled distinctly) when disputed or low-confidence (FR-008).
const LOW_CONFIDENCE = 0.5;

const CONFIRMED_COLOR = "#c0392b";
const SUSPECT_COLOR = "#f59e0b";
// Brighter than the dot/segment so the vision cone stands out against both the
// dark map and the (same-hue) watched-stretch line.
const CONE_CONFIRMED_COLOR = "#ff5a4d";
const CONE_SUSPECT_COLOR = "#fbbf24";

function isSuspect(c: CameraPin): boolean {
  return c.verification_status === "disputed" || c.confidence < LOW_CONFIDENCE;
}

function toFeatureCollection(cameras: CameraPin[]): GeoJSON.FeatureCollection<GeoJSON.Point> {
  return {
    type: "FeatureCollection",
    features: cameras.map((c) => {
      const at = c.snapped_location ?? c.location; // draw on the road it watches
      const directional = typeof c.facing_direction === "number";
      return {
        type: "Feature",
        geometry: { type: "Point", coordinates: [at.lng, at.lat] },
        properties: {
          id: c.id,
          camera_type: c.camera_type,
          confidence: c.confidence,
          verification_status: c.verification_status,
          suspect: isSuspect(c),
          directional,
          // 0 is a harmless placeholder for omnidirectional cameras; the cone
          // layer is filtered to directional features so it's never rendered.
          facing_direction: directional ? (c.facing_direction as number) : 0,
        },
      };
    }),
  };
}

// One LineString per camera for the monitored road stretch it watches.
function toSegmentCollection(cameras: CameraPin[]): GeoJSON.FeatureCollection<GeoJSON.LineString> {
  return {
    type: "FeatureCollection",
    features: cameras
      .filter((c) => c.segment && c.segment.length >= 2)
      .map((c) => ({
        type: "Feature",
        geometry: { type: "LineString", coordinates: c.segment as [number, number][] },
        properties: { suspect: isSuspect(c) },
      })),
  };
}

// A vision-cone icon. The apex sits at the BOTTOM-centre and the cone fans up to
// the top, so with icon-anchor "bottom" the apex pins to the camera point and the
// cone extends its full length outward (well past the dot) — rotating to the
// bearing the camera faces. Alpha fades toward the tip so it reads as a beam.
// Built as raw RGBA — no canvas — so it renders crisply at pixelRatio 2.
const CONE_PX = 48;
function buildCone(rgb: [number, number, number]): {
  width: number;
  height: number;
  data: Uint8Array;
} {
  const n = CONE_PX;
  const data = new Uint8Array(n * n * 4);
  const apex: [number, number] = [n / 2, n - 1];
  const left: [number, number] = [n / 2 - n * 0.3, 1];
  const right: [number, number] = [n / 2 + n * 0.3, 1];
  const maxDist = n - 2;
  const sign = (px: number, py: number, a: number[], b: number[]) =>
    (px - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (py - b[1]);
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const d1 = sign(x, y, apex, left);
      const d2 = sign(x, y, left, right);
      const d3 = sign(x, y, right, apex);
      const inside = !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
      const i = (y * n + x) * 4;
      data[i] = rgb[0];
      data[i + 1] = rgb[1];
      data[i + 2] = rgb[2];
      // Bright along its length, fading toward the tip (the far end of vision).
      const dist = Math.hypot(x - apex[0], y - apex[1]);
      data[i + 3] = inside ? Math.round(225 - (dist / maxDist) * 130) : 0;
    }
  }
  return { width: n, height: n, data };
}

function hexToRgb(hex: string): [number, number, number] {
  const v = parseInt(hex.slice(1), 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

function registerConeImages(map: maplibregl.Map): void {
  if (!map.hasImage(CONE_CONFIRMED)) {
    map.addImage(CONE_CONFIRMED, buildCone(hexToRgb(CONE_CONFIRMED_COLOR)), { pixelRatio: 2 });
  }
  if (!map.hasImage(CONE_SUSPECT)) {
    map.addImage(CONE_SUSPECT, buildCone(hexToRgb(CONE_SUSPECT_COLOR)), { pixelRatio: 2 });
  }
}

// camera_type is free-form text from upstream sources (e.g. OSM camera:type tags),
// so it MUST be escaped (escapeHtml) before going into setHTML or it's a DOM-XSS vector.

// Minimal shape of i18next's `t` — enough to localize the popup strings without
// pulling in the full TFunction generics.
type Translate = (key: string, opts?: Record<string, unknown>) => string;

const COMPASS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
function cardinal(bearing: number): string {
  return COMPASS[Math.round(((bearing % 360) + 360) % 360 / 45) % 8];
}

function directionLabel(directional: unknown, facing: unknown, t: Translate): string {
  if (directional && typeof facing === "number") {
    return t("cameras.popup.faces", { cardinal: cardinal(facing), deg: Math.round(facing) });
  }
  return t("cameras.popup.omnidirectional");
}

function popupHtml(
  p: {
    camera_type?: string | null;
    confidence?: number;
    verification_status?: string;
    directional?: unknown;
    facing_direction?: unknown;
  },
  t: Translate,
): string {
  const unknown = t("cameras.popup.unknown");
  const pct = typeof p.confidence === "number" ? `${Math.round(p.confidence * 100)}%` : "—";
  const type = escapeHtml(p.camera_type ?? unknown);
  const status = escapeHtml(p.verification_status ?? unknown);
  const dir = escapeHtml(directionLabel(p.directional, p.facing_direction, t));
  // Reference fields only (FR-014), escaped — no user data, no markup injection.
  // Labels come from the locale files (trusted), values are user/source data (escaped).
  const row = (label: string, value: string) =>
    `<div class="camera-popup__row"><span class="camera-popup__k">${label}</span>` +
    `<span class="camera-popup__v">${value}</span></div>`;
  return (
    `<div class="camera-popup">` +
    `<div class="camera-popup__title">${t("cameras.popup.title")}</div>` +
    row(t("cameras.popup.direction"), dir) +
    row(t("cameras.popup.type"), type) +
    row(t("cameras.popup.confidence"), pct) +
    row(t("cameras.popup.status"), status) +
    `</div>`
  );
}

export function CameraLayer({ map }: { map: maplibregl.Map | null }) {
  const { t } = useTranslation();
  // 1. Viewport bbox on settle (moveend), debounced so rapid moves coalesce (FR-002/003).
  const [rawBbox, setRawBbox] = useState("");
  useEffect(() => {
    if (!map) return;
    const update = () => {
      const b = map.getBounds();
      setRawBbox(`${b.getWest()},${b.getSouth()},${b.getEast()},${b.getNorth()}`);
    };
    update(); // frame the current view immediately
    map.on("moveend", update);
    return () => {
      map.off("moveend", update);
    };
  }, [map]);
  const bbox = useDebounce(rawBbox, BBOX_DEBOUNCE_MS);
  const { data } = useCameras(bbox || null);

  // 2. Clustered source + layers; setData on every viewport result (FR-001/004/010).
  useEffect(() => {
    if (!map) return;
    const cameras = data?.cameras ?? [];
    const points = toFeatureCollection(cameras);
    const segments = toSegmentCollection(cameras);

    const apply = () => {
      const pointSrc = map.getSource(SOURCE_ID) as maplibregl.GeoJSONSource | undefined;
      const segSrc = map.getSource(SEGMENT_SOURCE) as maplibregl.GeoJSONSource | undefined;
      if (pointSrc && segSrc) {
        segSrc.setData(segments);
        pointSrc.setData(points);
        return;
      }

      registerConeImages(map);
      // Insert below the route line when present, so cameras never cover the route.
      const beforeId = map.getLayer(ROUTE_LAYER) ? ROUTE_LAYER : undefined;

      // Clustered point source first (the primary camera source).
      map.addSource(SOURCE_ID, {
        type: "geojson",
        data: points,
        cluster: true,
        clusterRadius: CLUSTER_RADIUS,
        clusterMaxZoom: CLUSTER_MAX_ZOOM,
      });
      map.addSource(SEGMENT_SOURCE, { type: "geojson", data: segments });

      // Layers, bottom → top. The watched road stretch is drawn first (faint), so
      // the dots, rings and cones all sit on top of it.
      map.addLayer(
        {
          id: SEGMENT_LAYER,
          type: "line",
          source: SEGMENT_SOURCE,
          // Only draw the (unclustered) watched stretches once zoomed in, so a
          // dense viewport renders just the clustered dots (see SEGMENT_MIN_ZOOM).
          minzoom: SEGMENT_MIN_ZOOM,
          layout: { "line-join": "round", "line-cap": "round" },
          paint: {
            "line-color": ["case", ["get", "suspect"], SUSPECT_COLOR, CONFIRMED_COLOR],
            "line-width": 4,
            "line-opacity": 0.35,
          },
        },
        beforeId,
      );
      // Halo ring marking omnidirectional (360°) cameras, beneath the dot.
      map.addLayer(
        {
          id: RING_LAYER,
          type: "circle",
          source: SOURCE_ID,
          filter: ["all", ["!", ["has", "point_count"]], ["!", ["get", "directional"]]],
          paint: {
            "circle-radius": 11,
            "circle-color": "rgba(0,0,0,0)",
            "circle-stroke-width": 2,
            "circle-stroke-color": ["case", ["get", "suspect"], SUSPECT_COLOR, CONFIRMED_COLOR],
            "circle-stroke-opacity": 0.7,
          },
        },
        beforeId,
      );
      map.addLayer(
        {
          id: CLUSTER_LAYER, type: "circle", source: SOURCE_ID, filter: ["has", "point_count"],
          paint: { "circle-color": "#2563eb", "circle-radius": ["step", ["get", "point_count"], 14, 10, 18, 50, 24], "circle-stroke-width": 2, "circle-stroke-color": "#fff" },
        }, beforeId);
      map.addLayer(
        {
          id: CLUSTER_COUNT_LAYER, type: "symbol", source: SOURCE_ID, filter: ["has", "point_count"],
          layout: { "text-field": ["get", "point_count_abbreviated"], "text-size": 12 },
          paint: { "text-color": "#fff" },
        }, beforeId);
      map.addLayer(
        {
          id: POINT_LAYER, type: "circle", source: SOURCE_ID, filter: ["!", ["has", "point_count"]],
          // Disputed / low-confidence (suspect) render amber; confirmed render red (FR-008).
          paint: { "circle-radius": 6, "circle-color": ["case", ["get", "suspect"], SUSPECT_COLOR, CONFIRMED_COLOR], "circle-stroke-width": 1.5, "circle-stroke-color": "#fff" },
        }, beforeId);
      // Vision cone for directional cameras, rotated to the bearing they face.
      map.addLayer(
        {
          id: CONE_LAYER,
          type: "symbol",
          source: SOURCE_ID,
          filter: ["all", ["!", ["has", "point_count"]], ["get", "directional"]],
          layout: {
            "icon-image": ["case", ["get", "suspect"], CONE_SUSPECT, CONE_CONFIRMED],
            "icon-rotate": ["get", "facing_direction"],
            "icon-rotation-alignment": "map",
            "icon-anchor": "bottom",
            "icon-allow-overlap": true,
            "icon-ignore-placement": true,
            "icon-size": 1.1,
          },
        },
        beforeId,
      );
    };

    // Only the initial addSource/addLayer needs the style loaded; setData does not.
    // Once the source exists we must not re-gate on isStyleLoaded() (see MapView).
    if (map.getSource(SOURCE_ID) || map.isStyleLoaded()) apply();
    else map.once("load", apply);

    // Surface a truncated viewport rather than silently under-counting (FR-011).
    if (cameras.length >= SERVER_CAP) {
      console.warn(`[cameras] viewport returned the ${SERVER_CAP}-camera cap; counts may under-represent.`);
    }

    // Cancel any deferred apply on unmount/re-run: "load" only ever fires once, so
    // a stranded handler would run on a removed map or with a stale data closure.
    return () => {
      map.off("load", apply);
    };
  }, [map, data]);

  // 3. Interaction: cluster → expand (reduced-motion aware, FR-005); point → details popup (FR-006).
  const popupRef = useRef<maplibregl.Popup | null>(null);
  useEffect(() => {
    if (!map) return;

    const onClusterClick = (e: maplibregl.MapLayerMouseEvent) => {
      // The layer-scoped click event already carries the clicked cluster.
      const feature = e.features?.[0];
      const clusterId = feature?.properties?.cluster_id;
      const src = map.getSource(SOURCE_ID) as maplibregl.GeoJSONSource | undefined;
      if (!feature || clusterId == null || !src) return;
      const center = (feature.geometry as GeoJSON.Point).coordinates as [number, number];
      Promise.resolve(src.getClusterExpansionZoom(clusterId))
        .then((zoom) => {
          if (prefersReducedMotion()) map.jumpTo({ center, zoom });
          else map.easeTo({ center, zoom });
        })
        .catch(() => {});
    };

    const onPointClick = (e: maplibregl.MapLayerMouseEvent) => {
      const f = e.features?.[0];
      if (!f) return;
      const center = (f.geometry as GeoJSON.Point).coordinates.slice() as [number, number];
      popupRef.current?.remove();
      popupRef.current = new maplibregl.Popup({ closeOnClick: true, className: "camera-popup-shell" })
        .setLngLat(center)
        .setHTML(popupHtml(f.properties as Record<string, unknown>, t))
        .addTo(map);
    };

    // One document listener for the layer's lifetime dismisses the open popup via
    // keyboard (Esc), not pointer only (FR-015 / SC-010). The built-in close
    // button stays keyboard-focusable too.
    const closeOnEsc = (ev: KeyboardEvent) => {
      if (ev.key === "Escape") popupRef.current?.remove();
    };
    document.addEventListener("keydown", closeOnEsc);

    // Both the dot and its cone open the same popup.
    map.on("click", CLUSTER_LAYER, onClusterClick);
    map.on("click", POINT_LAYER, onPointClick);
    map.on("click", CONE_LAYER, onPointClick);
    return () => {
      map.off("click", CLUSTER_LAYER, onClusterClick);
      map.off("click", POINT_LAYER, onPointClick);
      map.off("click", CONE_LAYER, onPointClick);
      document.removeEventListener("keydown", closeOnEsc);
      popupRef.current?.remove();
    };
    // `t` is in deps so popups rebind to the active language after a language switch.
  }, [map, t]);

  return null;
}
