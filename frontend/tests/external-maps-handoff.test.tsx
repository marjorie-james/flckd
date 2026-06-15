import { describe, it, expect } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import "../src/i18n";
import { ExternalMapsHandoff } from "../src/components/ExternalMapsHandoff";

// The handoff is the ONE sanctioned exception to strict anonymity (FR-012b):
// route locations may go to Apple/Google Maps, but only after an explicit,
// user-initiated confirmation with a warning. These tests pin that contract.
const origin = { lat: 41.5868, lng: -93.625 };
const destination = { lat: 41.6611, lng: -91.5302 };

describe("ExternalMapsHandoff anonymity (FR-012b)", () => {
  it("reveals no external link or coordinates before the user opts in", () => {
    render(<ExternalMapsHandoff origin={origin} destination={destination} />);

    expect(screen.queryByRole("link")).toBeNull();
    expect(document.body.innerHTML).not.toContain("41.5868");
    expect(document.body.innerHTML).not.toContain("maps.apple.com");
  });

  it("shows an explicit warning dialog before exposing the links", () => {
    render(<ExternalMapsHandoff origin={origin} destination={destination} />);

    fireEvent.click(screen.getByRole("button"));

    expect(screen.getByRole("alertdialog")).toBeInTheDocument();
    expect(screen.getAllByRole("link")).toHaveLength(2);
  });

  it("moves focus into the dialog when it opens", () => {
    render(<ExternalMapsHandoff origin={origin} destination={destination} />);
    fireEvent.click(screen.getByRole("button"));

    const dialog = screen.getByRole("alertdialog");
    expect(dialog.contains(document.activeElement)).toBe(true);
  });

  it("closes on Escape and restores focus to the trigger", () => {
    render(<ExternalMapsHandoff origin={origin} destination={destination} />);
    fireEvent.click(screen.getByRole("button"));

    fireEvent.keyDown(screen.getByRole("alertdialog"), { key: "Escape" });

    expect(screen.queryByRole("alertdialog")).toBeNull();
    expect(document.activeElement).toBe(screen.getByRole("button", { name: /open in maps/i }));
  });

  it("labels the dialog with its warning text", () => {
    render(<ExternalMapsHandoff origin={origin} destination={destination} />);
    fireEvent.click(screen.getByRole("button"));

    expect(screen.getByRole("alertdialog")).toHaveAccessibleName(/shares this route's locations/i);
  });

  it("opens external maps safely (noopener noreferrer) once confirmed", () => {
    render(<ExternalMapsHandoff origin={origin} destination={destination} />);
    fireEvent.click(screen.getByRole("button"));

    const links = screen.getAllByRole("link") as HTMLAnchorElement[];
    for (const a of links) {
      expect(a.rel).toContain("noopener");
      expect(a.rel).toContain("noreferrer");
    }
    const hrefs = links.map((a) => a.href);
    expect(hrefs.some((h) => h.includes("maps.apple.com"))).toBe(true);
    expect(hrefs.some((h) => h.includes("google.com/maps"))).toBe(true);
  });
});
