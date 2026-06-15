// Whether the user has asked the OS/browser to minimize motion. Used to choose
// an instant map reposition over an animated one (accessibility — spec FR-004).
// Returns false when matchMedia is unavailable (e.g. older test environments),
// so callers fall back to the animated default.
export function prefersReducedMotion(): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false;
  }
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}
