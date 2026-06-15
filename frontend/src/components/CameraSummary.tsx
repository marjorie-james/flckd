import { useTranslation } from "react-i18next";
import type { Route } from "../types/api";
import { routeStatus } from "../utils/routeStatus";

interface Props {
  route: Route;
}

// US4: surfaces how many cameras were avoided and lists any unavoidable cameras
// remaining on the route. The avoidance status (avoided / already-clean / minimum
// exposure) comes from the shared routeStatus helper so it can't drift from
// RouteResult's rendering of the same distinction. The minimum-exposure case is
// announced prominently by RouteNotice, so here it shows only the remaining-camera
// detail (no redundant status pill).
export function CameraSummary({ route }: Props) {
  const { t } = useTranslation();
  const status = routeStatus(route);
  return (
    <div className="camera-summary">
      {status === "avoided" && (
        <span className="avoided-badge">
          {t("result.avoided", { count: route.cameras_avoided_count })}
        </span>
      )}
      {status === "alreadyClean" && (
        <span className="avoided-badge clean">{t("result.alreadyClean")}</span>
      )}
      {route.remaining_cameras.length > 0 && (
        <details>
          <summary className="exposed">
            {t("result.remaining", { count: route.remaining_cameras.length })}
          </summary>
          <ul>
            {route.remaining_cameras.map((c, i) => (
              <li key={i}>{t("result.remainingItem", { id: c.osm_way_id })}</li>
            ))}
          </ul>
        </details>
      )}
    </div>
  );
}
