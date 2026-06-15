require "rails_helper"

RSpec.describe Routing::SegmentExclusionBuilder do
  # A monitored segment on a known Iowa I-80 line, with an active camera.
  let!(:segment) do
    create(:monitored_segment,
           osm_way_id: 35_306_398,
           geometry: "SRID=4326;LINESTRING(-92.5410 41.6963, -92.5400 41.6963)")
  end

  let(:bbox) { [ -92.60, 41.65, -92.50, 41.72 ] } # [min_lng, min_lat, max_lng, max_lat]

  # Exercise the real production call path (RoutePlanner uses segments_in_bbox +
  # rings_for separately) rather than a test-only convenience wrapper.
  def plan(bbox, min_confidence: 0.0)
    builder = described_class.new
    segments = builder.segments_in_bbox(bbox, min_confidence: min_confidence)
    { segments: segments, polygons: builder.rings_for(segments) }
  end

  it "returns the monitored segments intersecting the bbox" do
    result = plan(bbox)

    expect(result[:segments].map(&:id)).to include(segment.id)
  end

  it "with min_confidence, excludes only high-confidence cameras' segments" do
    # `segment`'s camera is the factory default (confidence 0.9 → high).
    low_camera = create(:camera, confidence: 0.6, location: "SRID=4326;POINT(-92.5395 41.6963)")
    low_segment = create(:monitored_segment, camera: low_camera, osm_way_id: 111,
                                              geometry: "SRID=4326;LINESTRING(-92.5396 41.6963, -92.5392 41.6963)")

    ids = plan(bbox, min_confidence: 0.8)[:segments].map(&:id)

    expect(ids).to include(segment.id)        # 0.9 camera kept
    expect(ids).not_to include(low_segment.id) # 0.6 camera filtered out
  end

  it "emits exclusion polygons as Valhalla-style [lon, lat] coordinate rings" do
    result = plan(bbox)

    expect(result[:polygons]).not_to be_empty
    ring = result[:polygons].first
    # Each vertex is a two-element [lng, lat] numeric pair (NOT a {lat:, lon:} hash).
    expect(ring).to all(be_an(Array).and(have_attributes(size: 2)))
    lng, lat = ring.first
    expect(lng).to be_within(0.01).of(-92.54)
    expect(lat).to be_within(0.01).of(41.70)
  end

  it "excludes segments outside the bbox" do
    result = plan([ -90.0, 40.0, -89.9, 40.1 ])

    expect(result[:segments]).to be_empty
    expect(result[:polygons]).to be_empty
  end

  it "buffers every in-bbox segment (batched query returns one ring per segment)" do
    create(:monitored_segment, osm_way_id: 222,
                               geometry: "SRID=4326;LINESTRING(-92.5380 41.6963, -92.5370 41.6963)")
    result = plan(bbox)

    expect(result[:segments].size).to eq(2)
    expect(result[:polygons].size).to eq(2)
    expect(result[:polygons]).to all(be_an(Array))
  end
end
