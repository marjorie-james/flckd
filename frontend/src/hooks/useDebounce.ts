import { useEffect, useState } from "react";

// General-purpose debounce. If flushBelow > 0, values whose trimmed length
// falls below that threshold are applied immediately (no delay) — useful for
// clearing a suggestions list without waiting for the full debounce interval.
export function useDebounce(value: string, delay: number, flushBelow = 0): string {
  const shouldFlush = flushBelow > 0 && value.trim().length < flushBelow;
  const [debounced, setDebounced] = useState(value);
  /* eslint-disable react-hooks/set-state-in-effect */
  useEffect(() => {
    // While flushing, keep `debounced` in sync with the (short) value so that
    // when the input crosses back above the threshold we don't return a stale
    // previously-typed query for one render.
    if (shouldFlush) {
      setDebounced(value);
      return;
    }
    const id = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(id);
  }, [value, delay, shouldFlush]);
  /* eslint-enable react-hooks/set-state-in-effect */
  return shouldFlush ? value : debounced;
}
