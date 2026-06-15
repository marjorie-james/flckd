import { useEffect, useId, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import type { Coordinate } from "../types/api";

interface Props {
  origin: Coordinate;
  destination: Coordinate;
}

// User-initiated handoff to Apple/Google Maps (FR-012b). Shows an explicit
// warning that the route's locations will be shared with the external provider
// BEFORE leaving the app.
export function ExternalMapsHandoff({ origin, destination }: Props) {
  const { t } = useTranslation();
  const [confirming, setConfirming] = useState(false);
  const warningId = useId();
  const dialogRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const wasConfirming = useRef(false);

  // Move focus into the dialog when it opens; restore it to the trigger on close,
  // so keyboard and screen-reader users land on the warning and return to where
  // they were instead of the document top.
  useEffect(() => {
    if (confirming) {
      dialogRef.current?.querySelector<HTMLElement>("a, button")?.focus();
    } else if (wasConfirming.current) {
      triggerRef.current?.focus();
    }
    wasConfirming.current = confirming;
  }, [confirming]);

  const appleUrl =
    `https://maps.apple.com/?saddr=${origin.lat},${origin.lng}` +
    `&daddr=${destination.lat},${destination.lng}&dirflg=d`;
  const googleUrl =
    `https://www.google.com/maps/dir/?api=1&origin=${origin.lat},${origin.lng}` +
    `&destination=${destination.lat},${destination.lng}&travelmode=driving`;

  if (!confirming) {
    return (
      <button ref={triggerRef} type="button" className="open-in-maps-btn" onClick={() => setConfirming(true)}>
        {t("result.openInMaps")}
      </button>
    );
  }

  return (
    <div
      ref={dialogRef}
      className="handoff-warning"
      role="alertdialog"
      aria-labelledby={warningId}
      onKeyDown={(e) => { if (e.key === "Escape") setConfirming(false); }}
    >
      <p id={warningId}>{t("handoff.warning")}</p>
      <a href={appleUrl} target="_blank" rel="noreferrer noopener">
        {t("handoff.apple")}
      </a>
      <a href={googleUrl} target="_blank" rel="noreferrer noopener">
        {t("handoff.google")}
      </a>
      <button type="button" onClick={() => setConfirming(false)}>
        {t("handoff.cancel")}
      </button>
    </div>
  );
}
