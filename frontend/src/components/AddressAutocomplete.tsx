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
}

// An accessible address field: an ARIA 1.2 combobox whose suggestions are a
// listbox. Keyboard — ArrowUp/Down move the active option, Home/End jump to the
// first/last, Enter selects it, Escape dismisses the list. Focus stays on the
// input; the active option is conveyed via aria-activedescendant (the combobox
// pattern), and a polite live region announces how many suggestions are available.
export function AddressAutocomplete({ id, label, value, onValueChange, suggestions, onSelect, open, loading = false, error = false, describedById, required = false, trailing }: Props) {
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
  // Status text to show when there are no selectable results yet:
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

  // Two mutually exclusive popovers. The listbox is mounted only when there is at
  // least one real option: a listbox that owns no options is announced as an empty
  // list, and status text parked inside it as a presentational row is unreachable
  // by list navigation. The status text is a plain element outside the listbox, and
  // the polite live region below already speaks it.
  const listboxOpen = open && !dismissed && hasOptions;
  const statusOpen = open && !dismissed && !hasOptions && statusMessage !== null;
  const listId = `${id}-listbox`;
  const statusId = `${id}-status`;
  const hintId = `${id}-hint`;
  const optionId = (i: number) => `${id}-opt-${i}`;

  // Tie any active error to the input so a screen reader announces it on focus,
  // not just as a transient live-region message (WCAG 3.3.1). On a failed search
  // the status region holds the error text; an external describedById (e.g. a
  // geolocation error) is merged in too. The hint is always present: picking a
  // suggestion is the only way to confirm an address, and nothing else in the form
  // says so to someone who can't see the submit button's state (WCAG 3.3.2).
  const describedBy = [error ? statusId : null, hintId, describedById].filter(Boolean).join(" ");

  const onKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (!listboxOpen) {
      // Re-open a list dismissed via Escape: per the ARIA combobox pattern,
      // Arrow keys bring the listbox back (and move to the first/last option)
      // without the user having to retype. Guarded on `open` + suggestions so
      // we only re-open when the parent would otherwise show the list.
      if ((e.key === "ArrowDown" || e.key === "ArrowUp") && open && hasOptions) {
        e.preventDefault();
        setDismissed(false);
        setActive(e.key === "ArrowDown" ? 0 : suggestions.length - 1);
        return;
      }
      // Only a status panel is showing: nothing to navigate, but Escape can
      // still dismiss it.
      if (statusOpen && e.key === "Escape") { e.preventDefault(); setDismissed(true); }
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
      case "Home":
        e.preventDefault();
        setActive(0);
        break;
      case "End":
        e.preventDefault();
        setActive(suggestions.length - 1);
        break;
      case "Enter":
        if (active >= 0) { e.preventDefault(); onSelect(suggestions[active]); }
        break;
      case "Escape":
        e.preventDefault();
        setDismissed(true);
        setActive(-1);
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
    <div className="input-group" onBlur={onBlur}>
      <label className="field-label" htmlFor={id}>{label}</label>
      <div className="input-wrap">
        <input
          id={id}
          role="combobox"
          // Gated on there being real options, not merely on a popover being
          // visible: claiming a popup opened and then owning nothing is what
          // produces the "list box, 0 items" announcement.
          aria-expanded={listboxOpen}
          // Only reference the listbox while it actually exists in the DOM
          // (it's rendered only when there are options) — a dangling id is invalid.
          aria-controls={listboxOpen ? listId : undefined}
          aria-autocomplete="list"
          // Both the listbox and its options exist only while it is open, so these
          // references must clear when collapsed (a dangling id is invalid ARIA).
          aria-activedescendant={listboxOpen && active >= 0 ? optionId(active) : undefined}
          aria-describedby={describedBy}
          aria-required={required || undefined}
          // Flag the field itself, not just the error text, when its lookup failed.
          aria-invalid={error || undefined}
          value={value}
          // Typing after an Escape dismissal re-opens the list.
          onChange={(e) => { setDismissed(false); onValueChange(e.target.value); }}
          // Blur dismisses the list so it can't linger over the next control.
          // Without this reset, returning to the field leaves it collapsed until
          // the user retypes or presses an arrow key.
          onFocus={() => { if (open && hasOptions) setDismissed(false); }}
          onKeyDown={onKeyDown}
          className="field-input"
          inputMode="search"
          autoComplete="off"
        />
        {trailing}
      </div>

      {listboxOpen && (
        <ul className="suggestions" role="listbox" id={listId} aria-label={label}>
          {suggestions.map((r, i) => (
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
          ))}
        </ul>
      )}

      {statusOpen && (
        // Standalone status panel (searching / no matches / error). Deliberately
        // not a listbox and not inside one.
        <div className={`suggestion-status${error ? " error" : ""}`}>{statusMessage}</div>
      )}

      <span id={hintId} className="visually-hidden">{t("form.suggestionHint")}</span>

      <span id={statusId} className="visually-hidden" role="status" aria-live="polite">
        {(hasOptions
          ? t("form.suggestionsAvailable", { count: suggestions.length })
          : statusMessage ?? "") + (announceTick ? "\u200B" : "")}
      </span>
    </div>
  );
}
