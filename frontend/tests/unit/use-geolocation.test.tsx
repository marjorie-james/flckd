import { describe, it, expect, vi, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useGeolocation } from "../../src/hooks/useGeolocation";

// The hook used to expose the browser's locale-dependent err.message; it now maps
// failures to stable codes the UI localizes. These pin that mapping so a denied /
// unavailable / timed-out / unsupported request is never a silent no-op.
function geoError(code: number) {
  return { code, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3, message: "locale text" };
}

function stubGeolocation(getCurrentPosition: unknown) {
  vi.stubGlobal("navigator", { geolocation: { getCurrentPosition }, language: "en-US" });
}

afterEach(() => vi.unstubAllGlobals());

describe("useGeolocation error codes", () => {
  it.each([
    [1, "denied"],
    [2, "unavailable"],
    [3, "timeout"],
  ])("maps W3C code %i to '%s'", (code, expected) => {
    stubGeolocation((_ok: PositionCallback, err: PositionErrorCallback) =>
      err(geoError(code) as GeolocationPositionError),
    );
    const { result } = renderHook(() => useGeolocation());
    act(() => result.current.request());
    expect(result.current.error).toBe(expected);
    expect(result.current.coordinate).toBeNull();
  });

  it("reports 'unsupported' when the browser has no geolocation API", () => {
    vi.stubGlobal("navigator", { language: "en-US" });
    const { result } = renderHook(() => useGeolocation());
    act(() => result.current.request());
    expect(result.current.error).toBe("unsupported");
  });

  it("returns the coordinate and clears error on success", () => {
    stubGeolocation((ok: PositionCallback) =>
      ok({ coords: { latitude: 41.5, longitude: -93.6 } } as GeolocationPosition),
    );
    const { result } = renderHook(() => useGeolocation());
    act(() => result.current.request());
    expect(result.current.coordinate).toEqual({ lat: 41.5, lng: -93.6 });
    expect(result.current.error).toBeNull();
  });
});
