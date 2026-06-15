require "rails_helper"

# ManeuverLocalizer owns FR-015 (localized turn-by-turn). Unit-covers the I18n
# key lookup, the two fallback rungs, and field pass-through.
RSpec.describe Routing::ManeuverLocalizer do
  describe ".localize" do
    it "passes type, distance, and shape index through unchanged" do
      maneuvers = [ { type: 10, instruction: "Turn right.", distance_m: 500, shape_index: 2 } ]

      out = described_class.localize(maneuvers, locale: "en").first

      expect(out).to include(type: 10, distance_m: 500, shape_index: 2)
    end

    it "uses the localized template when a translation exists for the maneuver type" do
      I18n.backend.store_translations(:en, maneuvers: { localizer_spec_turn: "Bear left now" })
      maneuvers = [ { type: "localizer_spec_turn", instruction: "Keep left.", distance_m: 0, shape_index: 0 } ]

      out = described_class.localize(maneuvers, locale: "en").first

      expect(out[:localized_text]).to eq("Bear left now")
    end

    it "falls back to the engine instruction when there is no translation" do
      maneuvers = [ { type: "no_such_maneuver_key", instruction: "Drive east.", distance_m: 0, shape_index: 0 } ]

      out = described_class.localize(maneuvers, locale: "en").first

      expect(out[:localized_text]).to eq("Drive east.")
    end

    it "falls back to the type string when there is neither a translation nor an instruction" do
      maneuvers = [ { type: "no_such_maneuver_key", instruction: nil, distance_m: 0, shape_index: 0 } ]

      out = described_class.localize(maneuvers, locale: "en").first

      expect(out[:localized_text]).to eq("no_such_maneuver_key")
    end

    it "returns an empty array for nil/empty input" do
      expect(described_class.localize(nil)).to eq([])
      expect(described_class.localize([])).to eq([])
    end
  end
end
