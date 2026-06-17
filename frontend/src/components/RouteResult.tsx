import { useTranslation } from "react-i18next";
import type { Route } from "../types/api";
import { routeStatus } from "../utils/routeStatus";
import { routeTotals } from "../utils/routeTotals";
import { RouteExport } from "./RouteExport";
import { PrintableDirections } from "./PrintableDirections";

interface Props {
  route: Route;
  // The confirmed origin/destination address labels for this trip, shown on the
  // printable directions sheet. Optional with empty defaults so existing call
  // sites/tests that don't wire the print sheet still render.
  originLabel?: string;
  destinationLabel?: string;
  // Whether the comparison (fastest) route is currently drawn on the map. The
  // show/hide toggle below flips it. Optional with a sensible default so existing
  // call sites/tests render without wiring the comparison.
  showComparison?: boolean;
  onToggleComparison?: () => void;
}

// Shows the planned route summary: clean/minimum-exposure status, the route's
// travel time and distance, avoided and remaining camera counts, the
// fastest-route trade-off (added time + distance and what the fastest route
// would expose), a show/hide control for the comparison line, localized
// directions, and a faithful GPX export of the camera-avoided route.
export function RouteResult({
  route,
  originLabel = "",
  destinationLabel = "",
  showComparison = true,
  onToggleComparison,
}: Props) {
  const { t } = useTranslation();
  const fc = route.fastest_comparison;
  const addedMin = Math.round(fc.added_duration_s / 60);
  const addedKm = (fc.added_distance_m / 1000).toFixed(1);
  const { travelMin, km } = routeTotals(route);
  // The comparison is only meaningful when avoidance costs extra time; when it's
  // free we show a single route and no positive trade-off figures (FR-006).
  const hasCost = fc.added_duration_s > 0;

  // The avoidance status comes from the shared routeStatus helper (so this and
  // CameraSummary render the same distinction). The minimum-exposure message is
  // surfaced by CameraSummary, so here we only show the positive status pill.
  const status = routeStatus(route);

  // Resolve the coverage warning first; an unknown code falls back to "" and we
  // render nothing rather than an empty <p class="coverage-warning">.
  const coverageWarning = route.coverage_warning
    ? t(`errors.${route.coverage_warning}`, { defaultValue: "" })
    : "";

  return (
    <section className="route-result">
      {status === "avoided" && <p className="status clean">{t("result.fullyClean")}</p>}
      {status === "alreadyClean" && <p className="status clean">{t("result.alreadyClean")}</p>}

      <ul className="stats">
        <li>{t("result.travelTime", { minutes: travelMin })}</li>
        <li>{t("result.distance", { km })}</li>
        {status === "avoided" && (
          <li>{t("result.avoided", { count: route.cameras_avoided_count })}</li>
        )}
        {route.remaining_cameras.length > 0 && (
          <li>{t("result.remaining", { count: route.remaining_cameras.length })}</li>
        )}
        {hasCost && addedMin > 0 && <li>{t("result.addedTime", { minutes: addedMin })}</li>}
        {hasCost && <li className="added-distance">{t("result.addedDistance", { km: addedKm })}</li>}
        {hasCost && fc.cameras_passed_count > 0 && (
          <li className="fastest-exposes">
            {t("result.fastestExposes", { count: fc.cameras_passed_count })}
          </li>
        )}
      </ul>

      {hasCost && (
        <button
          type="button"
          className="comparison-toggle"
          aria-pressed={showComparison}
          onClick={onToggleComparison}
        >
          {showComparison ? t("result.hideComparison") : t("result.showComparison")}
        </button>
      )}

      {coverageWarning && <p className="coverage-warning">{coverageWarning}</p>}

      <div className="directions-header">
        <h3>{t("result.directions")}</h3>
        <PrintableDirections
          route={route}
          originLabel={originLabel}
          destinationLabel={destinationLabel}
        />
      </div>
      <ol className="directions">
        {route.maneuvers.map((m, i) => (
          <li key={i}>{m.localized_text}</li>
        ))}
      </ol>

      <RouteExport route={route} />
    </section>
  );
}
