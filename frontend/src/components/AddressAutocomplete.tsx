import { useState } from "react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import type { GeocodeResult } from "../types/api";

interface Props {
  id: string;
  label: string;
  value: string;
  onValueChange: (value: string) => void;
  suggestions: GeocodeResult[];
  onSelect: (result: GeocodeResult) => void;
  // Whether suggestions should be shown for the current input (parent decides:
  // min length reached, no coordinate locked yet, etc.).
  open: boolean;
  // A geocode request is in flight (shows a "searching" row when no results yet).
  loading?: boolean;
  // The geocode request failed (shows an error row instead of a dead input).
  error?: boolean;
  // Id of an external element (e.g. a field-level geolocation error) that also
  // describes this input, merged into aria-describedby so AT conveys it on focus.
  describedById?: string;
  // Whether the field is required (sets aria-required so AT conveys it).
  required?: boolean;
  // Optional trailing control inside the input (e.g. "use my location").
  trailing?: ReactNode;
  // Reserve permanent space below the field for the (overlaid) suggestion list.
  // Used for the last field (destination): the list stays a fixed-position overlay
  // that opens into the reserved gap, so it never covers the submit button below —
  // and the button doesn't move when the list opens/closes.
  reserveDropdownSpace?: boolean;
}

// An accessible address field: an ARIA 1.2 combobox whose suggestions are a
// listbox. Keyboard — ArrowUp/Down move the active option, Enter selects it,
// Escape dismisses the list. Focus stays on the input; the active option is
// conveyed via aria-activedescendant (the combobox pattern), and a polite live
// region announces how many suggestions are available.
export function AddressAutocomplete({ id, label, value, onValueChange, suggestions, onSelect, open, loading = false, error = false, describedById, required = false, trailing, reserveDropdownSpace = false }: Props) {
  const { t } = useTranslation();
  const [active, setActive] = useState(-1);
  const [dismissed, setDismissed] = useState(false);

  // Reset the highlighted option whenever a fresh suggestion set arrives, so a
  // stale index can't point past the new list. Done during render (React's
  // "adjust state when a prop changes" pattern) rather than in an effect.
  const [prevSuggestions, setPrevSuggestions] = useState(suggestions);
  // Toggled on every suggestion-set change so the live region's text always
  // differs from the last announcement — otherwise two different result sets that
  // resolve to the same count string ("5 suggestions available") would not
  // re-announce. The toggled character is a zero-width space: invisible, and not
  // spoken by screen readers.
  const [announceTick, setAnnounceTick] = useState(false);
  if (suggestions !== prevSuggestions) {
    setPrevSuggestions(suggestions);
    setActive(-1);
    setAnnounceTick((t) => !t);
  }

  const hasOptions = suggestions.length > 0;
  // A non-option status row to show when there are no selectable results yet:
  // searching, request failed, or a completed search with zero matches. Without
  // this, a network failure or empty result silently rendered nothing.
  const statusMessage = hasOptions
    ? null
    : error
      ? t("form.searchError")
      : loading
        ? t("form.searching")
        : open
          ? t("form.noMatches")
          : null;

  const expanded = open && !dismissed && (hasOptions || statusMessage !== null);
  const listId = `${id}-listbox`;
  const statusId = `${id}-status`;
  const optionId = (i: number) => `${id}-opt-${i}`;

  // Tie any active error to the input so a screen reader announces it on focus,
  // not just as a transient live-region message (WCAG 3.3.1). On a failed search
  // the status region holds the error text; an external describedById (e.g. a
  // geolocation error) is merged in too. References are dropped when absent so no
  // dangling id is left on the input.
  const describedBy = [error ? statusId : null, describedById].filter(Boolean).join(" ") || undefined;

  const onKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (!expanded) {
      // Re-open a list dismissed via Escape: per the ARIA combobox pattern,
      // Arrow keys bring the listbox back (and move to the first/last option)
      // without the user having to retype. Guarded on `open` + suggestions so
      // we only re-open when the parent would otherwise show the list.
      if ((e.key === "ArrowDown" || e.key === "ArrowUp") && open && suggestions.length > 0) {
        e.preventDefault();
        setDismissed(false);
        setActive(e.key === "ArrowDown" ? 0 : suggestions.length - 1);
      }
      return;
    }
    // Only a status row is showing (no selectable options): nothing to navigate,
    // but Escape can still dismiss it.
    if (!hasOptions) {
      if (e.key === "Escape") { e.preventDefault(); setDismissed(true); }
      return;
    }
    switch (e.key) {
      case "ArrowDown":
        e.preventDefault();
        setActive((i) => (i + 1) % suggestions.length);
        break;
      case "ArrowUp":
        e.preventDefault();
        setActive((i) => (i <= 0 ? suggestions.length - 1 : i - 1));
        break;
      case "Enter":
        if (active >= 0) { e.preventDefault(); onSelect(suggestions[active]); }
        break;
      case "Escape":
        if (expanded) { e.preventDefault(); setDismissed(true); setActive(-1); }
        break;
    }
  };

  // Dismiss an open list when focus leaves the field entirely, so it doesn't
  // linger (aria-expanded stuck true) over the next control. Focus moving within
  // the group — to the trailing button — keeps it; option clicks preventDefault
  // their mousedown so focus never leaves the input during selection.
  const onBlur = (e: React.FocusEvent<HTMLDivElement>) => {
    if (!e.currentTarget.contains(e.relatedTarget as Node | null)) {
      setDismissed(true);
    }
  };

  return (
    <div className={`input-group${reserveDropdownSpace ? " reserve-dropdown" : ""}`} onBlur={onBlur}>
      <label htmlFor={id}>{label}</label>
      <div className="input-wrap">
        <input
          id={id}
          role="combobox"
          aria-expanded={expanded}
          // Only reference the listbox while it actually exists in the DOM
          // (it's rendered only when expanded) — a dangling id is invalid.
          aria-controls={expanded ? listId : undefined}
          aria-autocomplete="list"
          // Both the listbox and its options exist only while expanded, so these
          // references must clear when collapsed (a dangling id is invalid ARIA).
          aria-activedescendant={expanded && active >= 0 ? optionId(active) : undefined}
          aria-describedby={describedBy}
          aria-required={required || undefined}
          value={value}
          // Typing after an Escape dismissal re-opens the list.
          onChange={(e) => { setDismissed(false); onValueChange(e.target.value); }}
          onKeyDown={onKeyDown}
          inputMode="search"
          autoComplete="off"
        />
        {trailing}
      </div>

      {expanded && (
        <ul className="suggestions" role="listbox" id={listId} aria-label={label}>
          {hasOptions
            ? suggestions.map((r, i) => (
                // li is presentational so the listbox's only semantic children are options.
                // Keyed by index too: the geocoder can return several results sharing a
                // label (e.g. multiple points on one street), so the label alone isn't unique.
                <li key={`${r.label}-${i}`} role="presentation">
                  <button
                    type="button"
                    role="option"
                    id={optionId(i)}
                    aria-selected={i === active}
                    tabIndex={-1}
                    // Keep focus on the input (combobox pattern) so the group's
                    // blur-dismiss doesn't fire before the click selects.
                    onMouseDown={(e) => e.preventDefault()}
                    onMouseMove={() => setActive(i)}
                    onClick={() => onSelect(r)}
                  >
                    {r.label}
                  </button>
                </li>
              ))
            : (
                // Non-interactive status row (searching / no matches / error).
                <li role="presentation" className={`suggestion-status${error ? " error" : ""}`}>
                  {statusMessage}
                </li>
              )}
        </ul>
      )}

      <span id={statusId} className="visually-hidden" role="status" aria-live="polite">
        {(hasOptions
          ? t("form.suggestionsAvailable", { count: suggestions.length })
          : statusMessage ?? "") + (announceTick ? "\u200B" : "")}
      </span>
    </div>
  );
}
