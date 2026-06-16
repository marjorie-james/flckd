import { describe, it, expect, vi, afterEach } from "vitest";

// config.ts holds module-level state seeded by loadConfig(), so each test
// re-imports a fresh module copy to isolate that state.
async function freshConfig() {
  vi.resetModules();
  return import("../src/config");
}

function stubFetch(body: unknown, ok = true) {
  const res = { ok, status: ok ? 200 : 404, json: async () => body } as Response;
  const mock = vi.fn().mockResolvedValue(res);
  vi.stubGlobal("fetch", mock);
  return mock;
}

describe("runtime config", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("defaults to same-origin before loadConfig runs (API relative, tiles = page origin)", async () => {
    const { apiBase, tilesBase } = await freshConfig();
    expect(apiBase()).toBe(""); // relative /api/v1
    expect(tilesBase()).toBe(window.location.origin);
  });

  it("applies apiBase/tilesBase from config.json, trimming trailing slashes", async () => {
    stubFetch({ apiBase: "https://api.flckd.example/", tilesBase: "https://tiles.flckd.example//" });
    const { loadConfig, apiBase, tilesBase } = await freshConfig();
    await loadConfig();
    expect(apiBase()).toBe("https://api.flckd.example");
    expect(tilesBase()).toBe("https://tiles.flckd.example");
  });

  it("fetches config.json with no-store so a CDN cache can't pin a dead origin", async () => {
    const mock = stubFetch({ apiBase: "", tilesBase: "" });
    const { loadConfig } = await freshConfig();
    await loadConfig();
    expect(mock).toHaveBeenCalledWith("/config.json", { cache: "no-store" });
  });

  it("falls back to same-origin when config.json is missing (404)", async () => {
    stubFetch({}, false);
    const { loadConfig, apiBase, tilesBase } = await freshConfig();
    await loadConfig();
    expect(apiBase()).toBe("");
    expect(tilesBase()).toBe(window.location.origin);
  });

  it("falls back to same-origin and never throws when the fetch rejects", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")));
    const { loadConfig, apiBase, tilesBase } = await freshConfig();
    await expect(loadConfig()).resolves.toBeUndefined();
    expect(apiBase()).toBe("");
    expect(tilesBase()).toBe(window.location.origin);
  });

  it("ignores non-string fields in config.json", async () => {
    stubFetch({ apiBase: 42, tilesBase: null });
    const { loadConfig, apiBase, tilesBase } = await freshConfig();
    await loadConfig();
    expect(apiBase()).toBe("");
    expect(tilesBase()).toBe(window.location.origin);
  });
});
