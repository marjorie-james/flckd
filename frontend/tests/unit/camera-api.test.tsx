import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";

// useCameras passes the map zoom so the backend can drop the heavy per-camera
// segment geometry when zoomed out. apiGet is mocked to capture the params.
const apiGet = vi.fn();
vi.mock("../../src/services/apiClient", () => ({
  apiGet: (...args: unknown[]) => apiGet(...args),
}));

import { useCameras } from "../../src/services/cameraApi";

function wrapper() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  );
}

beforeEach(() => {
  apiGet.mockReset();
  apiGet.mockResolvedValue({ cameras: [] });
});

describe("useCameras zoom-aware payload", () => {
  it("sends the zoom param so the backend can drop detail when zoomed out", async () => {
    renderHook(() => useCameras("-1,-1,1,1", 11), { wrapper: wrapper() });
    await waitFor(() => expect(apiGet).toHaveBeenCalled());
    expect(apiGet.mock.calls[0][1]).toMatchObject({ bbox: "-1,-1,1,1", zoom: 11 });
  });

  it("omits zoom when none is given (full detail, back-compat)", async () => {
    renderHook(() => useCameras("-1,-1,1,1"), { wrapper: wrapper() });
    await waitFor(() => expect(apiGet).toHaveBeenCalled());
    expect(apiGet.mock.calls[0][1]).not.toHaveProperty("zoom");
    expect(apiGet.mock.calls[0][1]).toMatchObject({ bbox: "-1,-1,1,1" });
  });
});
