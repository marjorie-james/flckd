import { useState } from "react";
import { useTranslation } from "react-i18next";
import { MapView } from "../components/MapView";
import { RoutePanel } from "../components/RoutePanel";
import { RouteResult } from "../components/RouteResult";
import { RouteNotice } from "../components/RouteNotice";
import { CameraSummary } from "../components/CameraSummary";
import { LanguageSwitcher } from "../components/LanguageSwitcher";
import { usePlanRoute } from "../services/routeApi";
import { useCoverageBounds } from "../services/coverageApi";
import { ApiError } from "../services/apiClient";
import type { Coordinate, RouteRequest } from "../types/api";

// Mobile-first single-page flow: header → map → input panel → result.
export function PlanRoutePage() {
  const { t, i18n } = useTranslation();
  const [endpoints, setEndpoints] = useState<{ origin: Coordinate; destination: Coordinate } | null>(
    null
  );
  // The confirmed starting location, lifted here so MapView can recenter on it
  // the moment the user selects an address (feature 007).
  const [origin, setOrigin] = useState<Coordinate | null>(null);
  // Whether the fastest-route comparison line is shown. Defaults to shown and
  // resets on every new plan so a dismissal doesn't carry over to a fresh route
  // (FR-002a, FR-009).
  const [showComparison, setShowComparison] = useState(true);

  // The plan is a cached, cancelable query keyed on the trip: submitting sets the
  // endpoints (which starts it). Identical trips come from cache; a superseded
  // in-flight plan is aborted, not raced. Avoidance is always maximal — the planner
  // returns a fully camera-free route when one exists, and otherwise automatically
  // falls back to the fewest-cameras route (surfaced by RouteNotice).
  const planRequest: RouteRequest | null = endpoints
    ? { ...endpoints, locale: i18n.language }
    : null;
  const plan = usePlanRoute(planRequest);

  // The covered region's bounding box, fetched once, so the map opens framed on
  // whatever region this deployment covers (no hardcoded launch state).
  const coverage = useCoverageBounds();

  const handlePlan = (nextOrigin: Coordinate, destination: Coordinate) => {
    setShowComparison(true);
    setEndpoints({ origin: nextOrigin, destination });
  };

  const errorMessage = plan.error
    ? plan.error instanceof ApiError
      ? t(`errors.${plan.error.code}`, { defaultValue: t("errors.generic") })
      : t("errors.generic")
    : null;

  // On error we show NO route — the map and result clear and only the message
  // remains. (A route past some cameras is a success with a notice, not an error.)
  const route = plan.isError ? null : plan.data ?? null;
  // A fetch is in flight (initial plan or a live re-plan with existing data).
  const busy = plan.isFetching;

  return (
    <div className="plan-page">
      <header className="app-header">
        <h1>{t("app.title")}</h1>
        <LanguageSwitcher />
      </header>

      {/* Two regions side by side on wide screens (map dominant + a scrollable
          control rail), stacked full-width on narrow screens. The arrangement is
          purely CSS (App.css); the DOM order — map, then controls, then results —
          is the same in both layouts. */}
      <main className="layout-body">
        {/* The map is a supplementary visual; the route is fully available as text
            below (status, stats, turn-by-turn directions). It's a labelled region
            (not role="img") because MapLibre renders interactive controls inside —
            an image must not contain focusable descendants. */}
        <div className="map-container" role="region" aria-label={t("map.ariaLabel")}>
          <MapView
            route={route}
            origin={origin}
            showComparison={showComparison}
            regionBounds={coverage.data?.bounds ?? null}
          />
        </div>

        <div className="content-pane">
          <RoutePanel onPlan={handlePlan} planning={busy} onOriginChange={setOrigin} />

          {/* Polite live region so screen readers announce the planned route or an
              error when it appears. */}
          <div className="result-section" aria-live="polite">
            {errorMessage && <p className="error" role="alert">{errorMessage}</p>}
            {route && endpoints && (
              <>
                <RouteNotice route={route} />
                <CameraSummary route={route} />
                <RouteResult
                  route={route}
                  origin={endpoints.origin}
                  destination={endpoints.destination}
                  showComparison={showComparison}
                  onToggleComparison={() => setShowComparison((v) => !v)}
                />
              </>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
