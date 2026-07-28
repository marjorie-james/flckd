import { useEffect, useId, useMemo, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import type { Route } from "../types/api";
import { decodePolyline } from "../lib/polyline";
import { buildGpx } from "../lib/gpx";

interface Props {
  route: Route;
}

// Export the planned route as a GPX track the user can navigate in a
// track-following app. Unlike the old "open in Maps" handoff, this is FAITHFUL
// (the other app follows flckd's exact camera-avoided line, not its own route)
// and fully LOCAL (the file is built in the browser; no coordinates are sent to
// any third party — flckd's anonymity model has no transmission exception).
//
// The one residual risk is the file itself: once saved it holds the user's exact
// start, destination, and path. So download is gated behind an explicit warning
// (mirroring the old handoff's confirm step) that explains the risk AND how to
// use the file, before the file is ever created.
export function RouteExport({ route }: Props) {
  const { t } = useTranslation();
  const [confirming, setConfirming] = useState(false);
  const warningId = useId();
  const howtoId = useId();
  const dialogRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const wasConfirming = useRef(false);

  // This dialog is deliberately NOT modal: nothing outside it is inert or
  // aria-hidden, so claiming aria-modal="true" would tell assistive tech the rest
  // of the page is unavailable when it is still fully readable in browse mode.
  // What it does instead is the honest set: focus moves in on open, returns to the
  // trigger on close, and Escape cancels.
  useEffect(() => {
    if (confirming) {
      // Focus the dialog itself, NOT its first button. The first button is the
      // destructive "Download", and pre-arming it means a keyboard user's
      // reflexive Enter writes their exact route to disk without ever choosing to.
      // Landing on the container also lets the screen reader read the dialog's
      // name + description (the warning and how-to) before the user acts.
      dialogRef.current?.focus();
    } else if (wasConfirming.current) {
      triggerRef.current?.focus();
    }
    wasConfirming.current = confirming;
  }, [confirming]);

  // Escape cancels. There is no Tab trap: tabbing out of a non-modal dialog is
  // correct behaviour, and it matches what the page actually exposes to AT.
  const onDialogKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "Escape") setConfirming(false);
  };

  // decodePolyline returns [lng, lat] pairs. Memoized so toggling the warning
  // open/closed doesn't re-decode the whole polyline each render. A route needs
  // at least two points to be a meaningful track; if geometry is missing, render
  // nothing.
  const coords = useMemo(() => decodePolyline(route.geometry), [route.geometry]);
  if (coords.length < 2) return null;

  const download = () => {
    const gpx = buildGpx(coords);
    const url = URL.createObjectURL(new Blob([gpx], { type: "application/gpx+xml" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = "flckd-route.gpx"; // neutral filename — no addresses/PII
    // The anchor must be in the document for click() to trigger a download in
    // some browsers (notably Firefox).
    document.body.appendChild(a);
    a.click();
    a.remove();
    // Defer revocation: revoking synchronously right after click() can cancel the
    // still-in-flight download in some browsers (Firefox/Safari) and race headless
    // download capture. Release the URL on the next macrotask instead.
    setTimeout(() => URL.revokeObjectURL(url), 0);
    setConfirming(false);
  };

  if (!confirming) {
    return (
      <button ref={triggerRef} type="button" className="export-gpx-btn" onClick={() => setConfirming(true)}>
        {t("result.exportGpx")}
      </button>
    );
  }

  return (
    <div
      ref={dialogRef}
      className="export-warning"
      role="alertdialog"
      aria-labelledby={warningId}
      aria-describedby={howtoId}
      tabIndex={-1}
      onKeyDown={onDialogKeyDown}
    >
      <p id={warningId} className="export-risk">{t("gpx.warning")}</p>
      <p id={howtoId} className="export-howto">{t("gpx.howto")}</p>
      <button type="button" className="export-confirm" onClick={download}>
        {t("gpx.download")}
      </button>
      <button type="button" onClick={() => setConfirming(false)}>
        {t("gpx.cancel")}
      </button>
    </div>
  );
}
