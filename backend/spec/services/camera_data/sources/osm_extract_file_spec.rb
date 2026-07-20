require "rails_helper"

RSpec.describe CameraData::Sources::OsmExtractFile do
  let(:path) { Rails.root.join("spec/fixtures/camera_data/osm_extract_cameras.geojson").to_s }

  subject(:source) { described_class.new(path: path) }

  it "declares the shared OpenStreetMap / ODbL provenance (same identity as Overpass)" do
    expect(source.source_name).to eq("OpenStreetMap")
    expect(source.license).to eq("ODbL-1.0")
    expect(source.source_kind).to eq("community")
    # Identical to the Overpass mechanism, so a CAMERA_OSM_SOURCE flip is seamless.
    expect(source.source_name).to eq(CameraData::Sources::Overpass.new(bbox: { south: 0, west: 0, north: 1, east: 1 }).source_name)
  end

  it "keeps only ALPR/Flock nodes — drops non-ALPR surveillance and non-nodes" do
    refs = source.fetch.map { |r| r[:external_ref] }
    # Kept: 1001-1003 (classic) + 1004-1006 (broadened variants below).
    # Excluded: n2001 (surveillance:type=public), n2002 (brand=Hikvision, a
    # generic CCTV maker, not an ALPR vendor), and w3001 (a way, not a node).
    expect(refs).to contain_exactly(
      "osm:node/1001", "osm:node/1002", "osm:node/1003",
      "osm:node/1004", "osm:node/1005", "osm:node/1006"
    )
  end

  it "matches the broadened tag variants DeFlock / municipal mappers actually use" do
    refs = source.fetch.map { |r| r[:external_ref] }
    # n1004: manufacturer=Flock Safety with NO brand/operator (previously missed).
    # n1005: operator=Vigilant Solutions (a non-Flock ALPR vendor).
    # n1006: surveillance:type=ANPR (ANPR in surveillance:type was previously missed).
    expect(refs).to include("osm:node/1004", "osm:node/1005", "osm:node/1006")
  end

  it "still rejects a generic (non-ALPR) surveillance camera by brand" do
    refs = source.fetch.map { |r| r[:external_ref] }
    expect(refs).not_to include("osm:node/2002") # brand=Hikvision (CCTV, not ALPR)
  end

  it "re-derives the canonical osm:node/<id> external_ref from the osmium type_id" do
    expect(source.fetch.map { |r| r[:external_ref] }).to all(match(%r{\Aosm:node/\d+\z}))
  end

  it "maps brand/type tags to a coarse camera_type (parity with Overpass)" do
    by_ref = source.fetch.index_by { |r| r[:external_ref] }
    expect(by_ref["osm:node/1001"][:camera_type]).to eq("Flock") # brand=Flock Safety
    expect(by_ref["osm:node/1002"][:camera_type]).to eq("ALPR")  # camera:type=ANPR
    expect(by_ref["osm:node/1003"][:camera_type]).to eq("Flock") # operator=Flock
  end

  it "normalizes facing direction from degrees and cardinals" do
    by_ref = source.fetch.index_by { |r| r[:external_ref] }
    expect(by_ref["osm:node/1001"][:facing_direction]).to eq(90)   # "90"
    expect(by_ref["osm:node/1002"][:facing_direction]).to eq(45)   # "NE"
    expect(by_ref["osm:node/1003"][:facing_direction]).to be_nil   # untagged
  end

  it "carries coordinates and the default unverified confidence" do
    rec = source.fetch.find { |r| r[:external_ref] == "osm:node/1001" }
    expect(rec[:lat]).to be_within(1e-6).of(41.5868)
    expect(rec[:lng]).to be_within(1e-6).of(-93.6250)
    expect(rec[:confidence]).to eq(0.5)
  end
end
