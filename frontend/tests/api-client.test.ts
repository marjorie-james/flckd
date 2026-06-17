import { describe, it, expect, vi, afterEach } from "vitest";
import { apiGet, apiPost, ApiError } from "../src/services/apiClient";

// The fetch wrapper is anonymity-critical: it must talk ONLY to our own
// same-origin backend and must not attach cookies, auth, or any identifier.
function stubFetch(body: unknown, ok = true, status = 200) {
  const res = { ok, status, statusText: "OK", json: async () => body } as Response;
  const mock = vi.fn().mockResolvedValue(res);
  vi.stubGlobal("fetch", mock);
  return mock;
}

describe("apiClient anonymity", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("only calls our own same-origin /api/v1 endpoint (never a third party)", async () => {
    const fetchMock = stubFetch({});
    await apiPost("/routes", { route: {} });

    const url = fetchMock.mock.calls[0][0] as string;
    expect(url).toBe("/api/v1/routes");
    expect(url).not.toMatch(/^https?:\/\//); // not an absolute external URL
  });

  it("sends only content-type + language headers — no cookie/auth/identifier", async () => {
    const fetchMock = stubFetch({});
    await apiPost("/routes", { route: {} });

    const init = fetchMock.mock.calls[0][1] as RequestInit;
    // No explicit credentials => cookies are never sent cross-origin.
    expect(init.credentials).toBeUndefined();
    const keys = Object.keys(init.headers as Record<string, string>).map((k) => k.toLowerCase());
    expect(keys.sort()).toEqual(["accept-language", "content-type"]);
    expect(keys).not.toContain("authorization");
    expect(keys).not.toContain("cookie");
  });

  it("posts exactly the caller's body — no injected identifiers", async () => {
    const fetchMock = stubFetch({});
    const payload = { route: { origin: { lat: 1, lng: 2 }, destination: { lat: 3, lng: 4 } } };
    await apiPost("/routes", payload);

    const init = fetchMock.mock.calls[0][1] as RequestInit;
    expect(JSON.parse(init.body as string)).toEqual(payload);
  });

  it("builds GET queries against our relative endpoint only", async () => {
    const fetchMock = stubFetch({ results: [] });
    await apiGet("/geocode/search", { q: "des moines", limit: 5 });

    const url = fetchMock.mock.calls[0][0] as string;
    expect(url).toBe("/api/v1/geocode/search?q=des+moines&limit=5");
    expect(url).not.toMatch(/^https?:\/\//);
  });

  it("forwards an AbortSignal into the fetch options (cancels superseded GETs)", async () => {
    const fetchMock = stubFetch({ cameras: [] });
    const controller = new AbortController();
    await apiGet("/cameras", { bbox: "1,2,3,4" }, controller.signal);

    const init = fetchMock.mock.calls[0][1] as RequestInit;
    expect(init.signal).toBe(controller.signal);
  });

  it("surfaces backend error code/status as ApiError", async () => {
    stubFetch({ code: "bad_request", message: "nope" }, false, 400);
    await expect(apiPost("/routes", {})).rejects.toMatchObject({
      code: "bad_request",
      status: 400,
    });
    await expect(apiPost("/routes", {})).rejects.toBeInstanceOf(ApiError);
  });
});
