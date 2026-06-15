require "rails_helper"

RSpec.describe CameraData::Sources::GeojsonFile do
  let(:path) { Rails.root.join("spec/fixtures/camera_data/sample_cameras.geojson").to_s }

  subject(:source) do
    described_class.new(
      path: path,
      name: "Denver Open Data",
      url: "https://opendata.example.gov/cameras",
      license: "CC0-1.0"
    )
  end

  it "carries the supplied per-file provenance" do
    expect(source.source_name).to eq("Denver Open Data")
    expect(source.license).to eq("CC0-1.0")
    expect(source.source_url).to eq("https://opendata.example.gov/cameras")
  end

  it "normalizes Point features and skips non-points" do
    records = source.fetch

    expect(records.size).to eq(2) # the LineString feature is skipped
    expect(records.map { |r| r[:lat] }).to all(be_a(Numeric))
  end

  it "uses the source id when present and derives a stable ref otherwise" do
    by_index = source.fetch
    expect(by_index.first[:external_ref]).to eq("city-cam-7")
    # Second feature has no id: ref is derived deterministically from coords.
    expect(by_index.second[:external_ref]).to eq("geojson:39.730000,-104.930000")
  end

  it "maps type/brand and clamps confidence" do
    records = source.fetch.index_by { |r| r[:external_ref] }

    expect(records["city-cam-7"][:camera_type]).to eq("Flock")
    expect(records["city-cam-7"][:facing_direction]).to eq(180)
    expect(records["city-cam-7"][:confidence]).to eq(0.8)
    # No confidence in the source → default 0.5.
    expect(records["geojson:39.730000,-104.930000"][:confidence]).to eq(0.5)
    expect(records["geojson:39.730000,-104.930000"][:camera_type]).to eq("ALPR") # ANPR
  end
end
