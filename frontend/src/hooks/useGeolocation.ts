import { useState, useCallback } from "react";
import type { Coordinate } from "../types/api";

// Stable, locale-independent error codes (the browser's err.message is
// locale-dependent and inconsistent). The UI maps these to localized copy.
export type GeolocationErrorCode =
  | "unsupported"
  | "denied"
  | "unavailable"
  | "timeout"
  | "error";

interface GeolocationState {
  coordinate: Coordinate | null;
  loading: boolean;
  error: GeolocationErrorCode | null;
}

// Maps the W3C GeolocationPositionError numeric codes to our stable codes.
function codeFor(err: GeolocationPositionError): GeolocationErrorCode {
  switch (err.code) {
    case err.PERMISSION_DENIED:
      return "denied";
    case err.POSITION_UNAVAILABLE:
      return "unavailable";
    case err.TIMEOUT:
      return "timeout";
    default:
      return "error";
  }
}

// Requests the device location on demand (never automatically). If the user
// declines, the UI falls back to manual origin entry (FR-017).
export function useGeolocation() {
  const [state, setState] = useState<GeolocationState>({
    coordinate: null,
    loading: false,
    error: null,
  });

  const request = useCallback(() => {
    if (!("geolocation" in navigator)) {
      setState({ coordinate: null, loading: false, error: "unsupported" });
      return;
    }
    setState((s) => ({ ...s, loading: true, error: null }));
    navigator.geolocation.getCurrentPosition(
      (pos) =>
        setState({
          coordinate: { lat: pos.coords.latitude, lng: pos.coords.longitude },
          loading: false,
          error: null,
        }),
      (err) => setState({ coordinate: null, loading: false, error: codeFor(err) }),
      { enableHighAccuracy: true, timeout: 10_000 }
    );
  }, []);

  return { ...state, request };
}
