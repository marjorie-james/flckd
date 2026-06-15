import { describe, it, expect, vi, afterEach } from "vitest";
import { prefersReducedMotion } from "../../src/utils/reducedMotion";

// prefersReducedMotion drives whether the map jumps (instant) or flies (animated)
// to a selected starting address — spec FR-004 / SC-005.
describe("prefersReducedMotion", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("returns true when the reduce-motion media query matches", () => {
    vi.stubGlobal("matchMedia", vi.fn().mockReturnValue({ matches: true }));
    expect(prefersReducedMotion()).toBe(true);
  });

  it("returns false when the media query does not match", () => {
    vi.stubGlobal("matchMedia", vi.fn().mockReturnValue({ matches: false }));
    expect(prefersReducedMotion()).toBe(false);
  });

  it("queries the reduce-motion preference specifically", () => {
    const mm = vi.fn().mockReturnValue({ matches: false });
    vi.stubGlobal("matchMedia", mm);
    prefersReducedMotion();
    expect(mm).toHaveBeenCalledWith("(prefers-reduced-motion: reduce)");
  });

  it("falls back to false when matchMedia is unavailable", () => {
    vi.stubGlobal("matchMedia", undefined);
    expect(prefersReducedMotion()).toBe(false);
  });
});
