import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import "../src/i18n";
import { RouteExport } from "../src/components/RouteExport";
import type { Route } from "../src/types/api";

function route(overrides: Partial<Route> = {}): Route {
  return {
    geometry: "__ajnA~n{oqD~hbE_ibE", // decodes to a multi-point line
    distance_m: 6000,
    duration_s: 600,
    maneuvers: [],
    cameras_avoided_count: 3,
    remaining_cameras: [],
    is_fully_clean: true,
    fastest_comparison: { distance_m: 5000, duration_s: 500, added_distance_m: 1000, added_duration_s: 100, geometry: "_fp_", cameras_passed_count: 2 },
    coverage_warning: null,
    ...overrides,
  };
}

describe("RouteExport", () => {
  it("shows only the export trigger until the user opts in", () => {
    render(<RouteExport route={route()} />);
    expect(screen.getByRole("button", { name: /export route \(gpx\)/i })).toBeInTheDocument();
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
  });

  it("warns about the file risk AND explains how to use it before any download", () => {
    render(<RouteExport route={route()} />);
    fireEvent.click(screen.getByRole("button", { name: /export route \(gpx\)/i }));

    const dialog = screen.getByRole("alertdialog");
    expect(dialog).toHaveTextContent(/contains your exact route/i);
    expect(dialog).toHaveTextContent(/protecting it is up to you/i);
    expect(dialog).toHaveTextContent(/track-following navigation app/i);
  });

  describe("the warning is a truthful non-modal dialog", () => {
    // Closing remounts the trigger, so re-query it rather than holding a stale node.
    const trigger = () => screen.getByRole("button", { name: /export route \(gpx\)/i });
    const openIt = () => {
      render(<RouteExport route={route()} />);
      fireEvent.click(trigger());
      return { dialog: screen.getByRole("alertdialog") };
    };

    it("does not claim aria-modal, since the rest of the page stays exposed", () => {
      const { dialog } = openIt();
      expect(dialog).not.toHaveAttribute("aria-modal");
    });

    it("moves focus into the dialog on open", () => {
      const { dialog } = openIt();
      expect(document.activeElement).toBe(dialog);
    });

    it("closes on Escape and returns focus to the trigger", () => {
      const { dialog } = openIt();

      fireEvent.keyDown(dialog, { key: "Escape" });

      expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
      expect(document.activeElement).toBe(trigger());
    });

    it("returns focus to the trigger when cancelled with the mouse", () => {
      openIt();

      fireEvent.click(screen.getByRole("button", { name: /cancel/i }));

      expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
      expect(document.activeElement).toBe(trigger());
    });
  });

  it("renders nothing when the route has too few points to form a track", () => {
    const { container } = render(<RouteExport route={route({ geometry: "" })} />);
    expect(container).toBeEmptyDOMElement();
  });

  describe("download is built locally and never touches the network (anonymity)", () => {
    let captured: Blob | null;
    let createSpy: ReturnType<typeof vi.fn>;
    let revokeSpy: ReturnType<typeof vi.fn>;
    let clickSpy: ReturnType<typeof vi.spyOn>;
    let fetchSpy: ReturnType<typeof vi.fn>;
    let realCreate: typeof URL.createObjectURL;
    let realRevoke: typeof URL.revokeObjectURL;

    beforeEach(() => {
      captured = null;
      createSpy = vi.fn((blob: Blob) => { captured = blob; return "blob:mock"; });
      revokeSpy = vi.fn();
      // Assign the two methods directly (jsdom doesn't implement them) without
      // replacing the URL constructor.
      realCreate = URL.createObjectURL;
      realRevoke = URL.revokeObjectURL;
      URL.createObjectURL = createSpy as unknown as typeof URL.createObjectURL;
      URL.revokeObjectURL = revokeSpy as unknown as typeof URL.revokeObjectURL;
      clickSpy = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
      fetchSpy = vi.fn();
      vi.stubGlobal("fetch", fetchSpy);
    });

    afterEach(() => {
      URL.createObjectURL = realCreate;
      URL.revokeObjectURL = realRevoke;
      vi.unstubAllGlobals();
      vi.restoreAllMocks();
    });

    it("creates a GPX blob, downloads it as flckd-route.gpx, and makes no request", async () => {
      render(<RouteExport route={route()} />);
      fireEvent.click(screen.getByRole("button", { name: /export route \(gpx\)/i }));
      fireEvent.click(screen.getByRole("button", { name: /download \.gpx/i }));

      expect(createSpy).toHaveBeenCalledOnce();
      expect(captured).toBeInstanceOf(Blob);
      expect(captured!.type).toBe("application/gpx+xml");

      const text = await captured!.text();
      expect(text).toContain("<gpx");
      expect(text).toContain("<trkpt ");

      // The download anchor fired and, crucially, nothing was sent anywhere.
      expect(clickSpy).toHaveBeenCalled();
      expect(fetchSpy).not.toHaveBeenCalled();

      // The object URL is released on the next macrotask (deferred so the revoke
      // can't cancel the in-flight download); flush it before asserting cleanup.
      await new Promise((resolve) => setTimeout(resolve, 0));
      expect(revokeSpy).toHaveBeenCalled();
    });
  });
});
