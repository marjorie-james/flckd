import { useEffect, useId, useState } from "react";
import { useTranslation } from "react-i18next";
import { useGeocodeSearch, MIN_QUERY_LENGTH } from "../services/geocodeApi";
import { useGeolocation } from "../hooks/useGeolocation";
import { useDebounce } from "../hooks/useDebounce";
import { AddressAutocomplete } from "./AddressAutocomplete";
import type { Coordinate, GeocodeResult } from "../types/api";

interface Props {
  // The confirmed address labels travel alongside the coordinates so the page can
  // show them on the printable directions sheet (the Route response carries no
  // human-readable origin/destination). Captured at plan time so later edits to
  // the inputs can't desync the printed trip.
  onPlan: (
    origin: Coordinate,
    destination: Coordinate,
    labels: { origin: string; destination: string },
  ) => void;
  planning: boolean;
  // Announced whenever the starting location is set (suggestion pick or "use my
  // location") or cleared — lets the parent recenter the map (feature 007).
  onOriginChange?: (origin: Coordinate | null) => void;
}

// Mobile-first input panel: origin + destination with geocode autocomplete
// and a "use my location" shortcut.
export function RoutePanel({ onPlan, planning, onOriginChange }: Props) {
  const { t, i18n } = useTranslation();
  // Stable id so the geolocation error can be tied to the origin field via
  // aria-describedby — announced when the field gains focus, not only as a
  // one-shot alert when it appears (WCAG 3.3.1).
  const geoErrorId = useId();
  const [originText, setOriginText] = useState("");
  const [destText, setDestText] = useState("");
  const [origin, setOrigin] = useState<Coordinate | null>(null);
  const [destination, setDestination] = useState<Coordinate | null>(null);

  const geo = useGeolocation();
  // Debounce the search query so the API isn't hit on every keystroke.
  // Pass "" when a coordinate is already locked so the query stays disabled.
  const debouncedOriginQ = useDebounce(origin ? "" : originText, 300, MIN_QUERY_LENGTH);
  const debouncedDestQ = useDebounce(destination ? "" : destText, 300, MIN_QUERY_LENGTH);
  const originResults = useGeocodeSearch(debouncedOriginQ, i18n.language);
  const destResults = useGeocodeSearch(debouncedDestQ, i18n.language);

  // When the device location arrives, use it as the origin (manual entry stays
  // available if the user declines — FR-017). Syncing this external, async
  // geolocation result into the editable origin fields is a legitimate effect:
  // the values remain user-editable state afterward, so they can't be derived.
  /* eslint-disable react-hooks/set-state-in-effect */
  useEffect(() => {
    if (geo.coordinate) {
      setOrigin(geo.coordinate);
      setOriginText(`${geo.coordinate.lat.toFixed(5)}, ${geo.coordinate.lng.toFixed(5)}`);
      onOriginChange?.(geo.coordinate);
    }
  }, [geo.coordinate, onOriginChange]);
  /* eslint-enable react-hooks/set-state-in-effect */

  const pickOrigin = (r: GeocodeResult) => {
    const coord = { lat: r.lat, lng: r.lng };
    setOriginText(r.label);
    setOrigin(coord);
    // Tell the parent so the map recenters on the selected address (feature 007).
    onOriginChange?.(coord);
  };
  const pickDestination = (r: GeocodeResult) => {
    setDestText(r.label);
    setDestination({ lat: r.lat, lng: r.lng });
  };

  const canPlan = Boolean(origin && destination) && !planning;
  const originSuggestions = originResults.data?.results ?? [];
  const destSuggestions = destResults.data?.results ?? [];

  // Map the geolocation hook's stable error code to localized copy so a denied /
  // unavailable / timed-out / unsupported request isn't a silent no-op.
  const geoErrorKey: Record<string, string> = {
    denied: "errors.locationDenied",
    unavailable: "errors.locationUnavailable",
    timeout: "errors.locationTimeout",
    unsupported: "errors.locationUnsupported",
  };
  const geoErrorMessage = geo.error ? t(geoErrorKey[geo.error] ?? "errors.generic") : null;

  return (
    <form
      className="route-panel"
      onSubmit={(e) => {
        e.preventDefault();
        if (origin && destination)
          onPlan(origin, destination, { origin: originText, destination: destText });
      }}
    >
      <AddressAutocomplete
        id="origin-input"
        required
        describedById={geoErrorMessage ? geoErrorId : undefined}
        label={t("form.origin")}
        value={originText}
        onValueChange={(v) => {
          setOriginText(v);
          // Editing a confirmed address unsets it (and clears the marker).
          // Guarded so plain typing — origin already null — does not notify the
          // parent on every keystroke (spec FR-005).
          if (origin) {
            setOrigin(null);
            onOriginChange?.(null);
          }
        }}
        suggestions={originSuggestions}
        onSelect={pickOrigin}
        open={!origin && debouncedOriginQ.trim().length >= MIN_QUERY_LENGTH}
        loading={originResults.isFetching}
        error={originResults.isError}
        trailing={
          <button
            type="button"
            className="geo-btn"
            onClick={geo.request}
            disabled={geo.loading}
            aria-label={t("form.useMyLocation")}
            title={t("form.useMyLocation")}
          >
            <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" />
            </svg>
          </button>
        }
      />

      {geoErrorMessage && (
        <p id={geoErrorId} className="field-error" role="alert">
          {geoErrorMessage}
        </p>
      )}

      <AddressAutocomplete
        id="dest-input"
        required
        label={t("form.destination")}
        value={destText}
        onValueChange={(v) => {
          setDestText(v);
          setDestination(null);
        }}
        suggestions={destSuggestions}
        onSelect={pickDestination}
        open={!destination && debouncedDestQ.trim().length >= MIN_QUERY_LENGTH}
        loading={destResults.isFetching}
        error={destResults.isError}
      />

      <button type="submit" disabled={!canPlan}>
        {planning ? t("form.planning") : t("form.plan")}
      </button>
    </form>
  );
}
