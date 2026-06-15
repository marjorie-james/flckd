require "rails_helper"

# A CoverageArea is an INGESTED camera-data region within the configured country
# (FR-008): `covers?`/`containing` answer "is there camera data here?", and each
# row carries its own `data_freshness_at`. Map framing is no longer derived from
# these rows — it comes from the country registry (see CoverageController#bounds).
RSpec.describe CoverageArea, type: :model do
  it "reports camera-data presence for a point inside a data-region" do
    create(:coverage_area) # covers the continental US
    expect(CoverageArea.covers?(-104.99, 39.74)).to be(true)
  end

  it "reports no presence for a point outside every data-region" do
    create(:coverage_area)
    expect(CoverageArea.covers?(2.35, 48.85)).to be(false) # Paris
  end

  it "reports no presence inside the country but outside any ingested region (absent, not camera-free)" do
    # A small data-region over Iowa; a Florida point is inside the US but has no
    # gathered data — honest "absent", distinct from "camera-free".
    create(:coverage_area, region: "SRID=4326;MULTIPOLYGON(((-96 40, -90 40, -90 43, -96 43, -96 40)))")
    expect(CoverageArea.covers?(-81.5, 28.5)).to be(false) # Orlando, FL — in the US, no data
  end

  describe ".containing" do
    it "returns the data-region whose own data_freshness_at applies to the point" do
      fresh = create(:coverage_area,
                     region: "SRID=4326;MULTIPOLYGON(((-96 40, -90 40, -90 43, -96 43, -96 40)))",
                     data_freshness_at: Time.current)
      create(:coverage_area,
             region: "SRID=4326;MULTIPOLYGON(((-83 25, -80 25, -80 31, -83 31, -83 25)))",
             data_freshness_at: 10.days.ago)

      region = CoverageArea.containing(-93.0, 41.5).first
      expect(region).to eq(fresh)
      expect(region.data_freshness_at).to be_within(1.minute).of(Time.current)
    end
  end
end
