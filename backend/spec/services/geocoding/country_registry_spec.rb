require "rails_helper"

# The country registry is the single source of truth for "what does country X
# need" — the OSM extract URL, the framing/viewbox bbox, whether the US Census
# TIGER house-number import applies, and the label for internal admin divisions.
# US is the only fully populated + validated entry at launch (FR-002, FR-009).
RSpec.describe Geocoding::CountryRegistry do
  describe ".resolve" do
    it "defaults to the US when no code is given" do
      record = described_class.resolve
      expect(record.code).to eq("us")
      expect(record.name).to eq("United States")
    end

    it "defaults to the US when the env var is blank" do
      record = described_class.resolve(nil)
      expect(record.code).to eq("us")
    end

    it "returns the fully populated US record" do
      us = described_class.resolve("us")

      expect(us).to have_attributes(
        code: "us",
        name: "United States",
        extract_url: "https://download.geofabrik.de/north-america/us-latest.osm.pbf",
        bbox: [ -125.0, 24.5, -66.9, 49.5 ],
        tiger: true,
        sub_region_kind: "state"
      )
    end

    it "is case-insensitive on the country code" do
      expect(described_class.resolve("US").code).to eq("us")
    end

    it "raises a clear, actionable error for an unknown / un-provisioned country (FR-009)" do
      expect { described_class.resolve("fr") }
        .to raise_error(Geocoding::CountryRegistry::UnknownCountryError, /fr/i)
    end

    it "names the supported countries in the failure so the operator can correct it" do
      expect { described_class.resolve("zz") }
        .to raise_error(Geocoding::CountryRegistry::UnknownCountryError, /us/)
    end
  end

  describe "#viewbox" do
    it "derives the Nominatim viewbox (min_lng,max_lat,max_lng,min_lat) from the bbox" do
      # bbox is [west, south, east, north]; Nominatim wants left,top,right,bottom.
      expect(described_class.resolve("us").viewbox).to eq("-125.0,49.5,-66.9,24.5")
    end
  end

  describe "#bounds" do
    it "frames as [[west, south], [east, north]] for the map (FR-007)" do
      expect(described_class.resolve("us").bounds).to eq([ [ -125.0, 24.5 ], [ -66.9, 49.5 ] ])
    end
  end

  describe ".single_state?" do
    around do |example|
      orig = ENV.to_hash.slice("GEOCODER_REGION_STATE")
      example.run
    ensure
      orig.key?("GEOCODER_REGION_STATE") ? ENV["GEOCODER_REGION_STATE"] = orig["GEOCODER_REGION_STATE"] : ENV.delete("GEOCODER_REGION_STATE")
    end

    it "is true when GEOCODER_REGION_STATE is set (single-state dev mode)" do
      ENV["GEOCODER_REGION_STATE"] = "Iowa"
      expect(described_class.single_state?).to be(true)
    end

    it "is false when GEOCODER_REGION_STATE is unset (whole-country mode)" do
      ENV.delete("GEOCODER_REGION_STATE")
      expect(described_class.single_state?).to be(false)
    end
  end
end
