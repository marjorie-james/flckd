import { useTranslation } from "react-i18next";
import type { Route } from "../types/api";
import { routeTotals } from "../utils/routeTotals";

interface Props {
  route: Route;
  originLabel: string;
  destinationLabel: string;
}

// An icon-only control that opens the browser's native print dialog, plus a
// print-only rendering of the directions designed to be read at arm's length
// while driving.
//
// Everything here is LOCAL: window.print() hands the page to the user's own
// printer/PDF target and sends nothing to any server — flckd's anonymity model
// has no transmission exception. The on-screen app chrome (map, panel, controls,
// camera notices) is hidden for print via the `@media print` rules in App.css;
// only `.printable-directions` is shown on paper. Camera/coverage notices are
// deliberately omitted from the sheet (it's a clean driving aid, not a warning).
//
// The Route response has no human-readable endpoints, so the confirmed origin and
// destination labels are passed in (lifted from the address inputs at plan time).
export function PrintableDirections({ route, originLabel, destinationLabel }: Props) {
  const { t } = useTranslation();
  const { travelMin, km } = routeTotals(route);

  return (
    <>
      <button
        type="button"
        className="print-btn"
        onClick={() => window.print()}
        aria-label={t("print.action")}
        title={t("print.action")}
      >
        <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M19 8H5c-1.66 0-3 1.34-3 3v6h4v4h12v-4h4v-6c0-1.66-1.34-3-3-3zm-3 11H8v-5h8v5zm3-7c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm-1-9H6v3h12V3z" />
        </svg>
      </button>

      {/* Print-only sheet. It is display:none on screen (App.css) and revealed
          only under @media print. aria-hidden keeps this print copy out of the
          on-screen accessibility tree so the directions aren't announced twice. */}
      <div className="printable-directions" aria-hidden="true">
        <h2 className="print-heading">{t("print.heading")}</h2>
        <p className="print-trip">
          <span className="print-from">
            {t("print.from")}: {originLabel}
          </span>
          <span className="print-to">
            {t("print.to")}: {destinationLabel}
          </span>
        </p>
        <p className="print-totals">
          {t("result.travelTime", { minutes: travelMin })} · {t("result.distance", { km })}
        </p>
        <ol className="print-steps">
          {route.maneuvers.map((m, i) => (
            <li key={i}>{m.localized_text}</li>
          ))}
        </ol>
        <p className="print-notice">{t("print.privacyNotice")}</p>
      </div>
    </>
  );
}
