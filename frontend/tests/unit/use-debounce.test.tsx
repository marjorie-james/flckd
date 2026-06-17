import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useDebounce } from "../../src/hooks/useDebounce";

// flushBelow makes short values apply immediately (used to clear a suggestions
// list without waiting). The bug: after flushing, `debounced` retained the stale
// long value, so re-crossing the threshold briefly returned a previously-typed
// query before the next debounce tick.
describe("useDebounce flush sync", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("does not return the stale long value after long → short → long", () => {
    const { result, rerender } = renderHook(
      ({ value }) => useDebounce(value, 300, 2),
      { initialProps: { value: "first" } },
    );

    // Let the initial long value debounce through.
    act(() => vi.advanceTimersByTime(300));
    expect(result.current).toBe("first");

    // Drop below the threshold: flushed immediately, no waiting.
    rerender({ value: "" });
    expect(result.current).toBe("");

    // Cross back above the threshold. Before the debounce tick fires, the hook
    // must not surface the old "first" query.
    rerender({ value: "second" });
    expect(result.current).not.toBe("first");

    act(() => vi.advanceTimersByTime(300));
    expect(result.current).toBe("second");
  });

  it("applies short values immediately when flushBelow is set", () => {
    const { result, rerender } = renderHook(
      ({ value }) => useDebounce(value, 300, 2),
      { initialProps: { value: "longquery" } },
    );
    act(() => vi.advanceTimersByTime(300));
    expect(result.current).toBe("longquery");

    rerender({ value: "x" });
    // No timer advance: a sub-threshold value is returned right away.
    expect(result.current).toBe("x");
  });
});
