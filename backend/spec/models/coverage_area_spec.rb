require "rails_helper"

RSpec.describe CoverageArea, type: :model do
  it "reports coverage for a point inside the region" do
    create(:coverage_area) # covers the continental US
    expect(CoverageArea.covers?(-104.99, 39.74)).to be(true)
  end

  it "reports no coverage for a point outside the region" do
    create(:coverage_area)
    expect(CoverageArea.covers?(2.35, 48.85)).to be(false) # Paris
  end

  describe ".bounds" do
    it "returns the bounding box [[w,s],[e,n]] enclosing the region" do
      create(:coverage_area) # MULTIPOLYGON over the continental US
      expect(CoverageArea.bounds).to eq([ [ -125.0, 24.0 ], [ -66.0, 49.0 ] ])
    end

    it "encloses every coverage area when several exist" do
      create(:coverage_area, region: "SRID=4326;MULTIPOLYGON(((-100 30, -90 30, -90 40, -100 40, -100 30)))")
      create(:coverage_area, region: "SRID=4326;MULTIPOLYGON(((-80 35, -70 35, -70 45, -80 45, -80 35)))")
      expect(CoverageArea.bounds).to eq([ [ -100.0, 30.0 ], [ -70.0, 45.0 ] ])
    end

    it "returns nil when no coverage area exists" do
      expect(CoverageArea.bounds).to be_nil
    end
  end
end
