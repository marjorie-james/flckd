require "rails_helper"
require "stringio"

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

  it "passes bbox values separately to ST_MakeEnvelope while executing the real query" do
    relation = MonitoredSegment.for_routing(0.0)
    allow(MonitoredSegment).to receive(:for_routing).with(0.0).and_return(relation)
    expect(relation).to receive(:where).with(
      "ST_Intersects(geometry, ST_MakeEnvelope(?, ?, ?, ?, 4326)) " \
        "/* route-candidate-envelope */",
      *bbox
    ).and_call_original

    expect(described_class.new.segments_in_bbox(bbox)).to include(segment)
  end

  it "finds candidates on both sides of the antimeridian with split envelopes" do
    east = create(:monitored_segment,
                  geometry: "SRID=4326;LINESTRING(179.90 41.6963, 179.95 41.6963)")
    west = create(:monitored_segment,
                  geometry: "SRID=4326;LINESTRING(-179.95 41.6963, -179.90 41.6963)")

    result = described_class.new.segments_in_bbox([ 179.85, 41.65, -179.85, 41.72 ])

    expect(result.map(&:id)).to contain_exactly(east.id, west.id)
  end

  it "redacts only candidate coordinate binds in Active Record SQL logs" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    logger.level = Logger::DEBUG
    logger.formatter = AnonymityLogScrubber::Formatter.new(logger.formatter)
    original_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = logger

    described_class.new.segments_in_bbox(bbox)

    sql_line = io.string.lines.find { |line| line.include?("route-candidate-envelope") }
    expect(sql_line).to include("MonitoredSegment Load", "ST_MakeEnvelope($4, $5, $6, $7, 4326)")
    expect(sql_line).to match(/\(\d+\.\d+ms\)/)
    expect(sql_line).to include("[nil, [redacted-coord]]", "4326")
    expect(sql_line).not_to include("-92.6", "41.65", "-92.5", "41.72")
  ensure
    ActiveRecord::Base.logger = original_logger
  end

  it "returns candidates in stable primary-key order" do
    create(:monitored_segment, osm_way_id: 222,
                               geometry: "SRID=4326;LINESTRING(-92.5380 41.6963, -92.5370 41.6963)")
    create(:monitored_segment, osm_way_id: 333,
                               geometry: "SRID=4326;LINESTRING(-92.5360 41.6963, -92.5350 41.6963)")
    queries = []
    callback = lambda do |_name, _started, _finished, _id, payload|
      queries << payload[:sql] if payload[:sql].include?("ST_MakeEnvelope")
    end

    result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      described_class.new.segments_in_bbox(bbox)
    end

    expect(result.map(&:id)).to eq(result.map(&:id).sort)
    expect(queries.one?).to be(true)
    expect(queries.first).to match(/ORDER BY .*monitored_segments.*id.* ASC/)
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
