import { useQuery } from "@tanstack/react-query";
import { apiGet } from "./apiClient";

export interface CameraPin {
  id: number;
  location: { lat: number; lng: number };
  // Camera point projected onto the road it watches, so the dot renders on the
  // road instead of floating beside it. null when the camera isn't snapped yet.
  snapped_location: { lat: number; lng: number } | null;
  // The monitored road stretch ([lng, lat] pairs), for highlighting what's watched.
  segment: [number, number][] | null;
  // Compass bearing the camera faces (0–359); null means omnidirectional (360°).
  facing_direction: number | null;
  camera_type: string | null;
  confidence: number;
  verification_status: string;
}

interface CamerasResponse {
  cameras: CameraPin[];
}

// bbox: "minLng,minLat,maxLng,maxLat". `zoom` is the current map zoom: when it's
// below the backend's detail threshold the response omits the heavy per-camera
// segment geometry (lighter payload zoomed out). Omitted (null) → full detail.
export function useCameras(bbox: string | null, zoom: number | null = null) {
  return useQuery({
    queryKey: ["cameras", bbox, zoom],
    queryFn: ({ signal }) =>
      apiGet<CamerasResponse>("/cameras", { bbox: bbox!, ...(zoom != null ? { zoom } : {}) }, signal),
    enabled: Boolean(bbox),
    staleTime: 300_000,
  });
}
