import { useTranslation } from "react-i18next";
import type { Route } from "../types/api";

// A prominent, assertive notice shown when no fully camera-free route exists and the
// planner fell back to the fewest-cameras route. It makes unmistakably clear that the
// route is NOT camera-free — it still passes within view of some camera(s). Renders
// nothing for a fully-clean route, so call sites can mount it unconditionally.
export function RouteNotice({ route }: { route: Route }) {
  const { t } = useTranslation();
  if (route.is_fully_clean) return null;

  return (
    <p className="route-notice" role="alert">
      {t("result.notCameraFree")}
    </p>
  );
}
