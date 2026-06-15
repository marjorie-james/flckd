import { useEffect, useState } from "react";

// General-purpose debounce. If flushBelow > 0, values whose trimmed length
// falls below that threshold are applied immediately (no delay) — useful for
// clearing a suggestions list without waiting for the full debounce interval.
export function useDebounce(value: string, delay: number, flushBelow = 0): string {
  const shouldFlush = flushBelow > 0 && value.trim().length < flushBelow;
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    if (shouldFlush) return;
    const id = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(id);
  }, [value, delay, shouldFlush]);
  return shouldFlush ? value : debounced;
}
