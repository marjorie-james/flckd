require "rails_helper"

RSpec.describe CameraData::SegmentSnapper do
  # Stub road lookup: always returns a known road segment.
  let(:road_lookup) do
    instance_double(
      CameraData::ValhallaRoadLookup,
      nearest_road: {
        osm_way_id: 999,
        geometry_ewkt: "SRID=4326;LINESTRING(-104.9905 39.7392, -104.9901 39.7392)",
        distance_m: 4.0
      }
    )
  end

  it "creates a monitored segment snapped to the nearest road" do
    camera = create(:camera)
    segment = described_class.new(road_lookup: road_lookup).snap(camera)

    expect(segment).to be_persisted
    expect(segment.osm_way_id).to eq(999)
    expect(camera.monitored_segments.count).to eq(1)
  end

  it "returns nil when no road is found" do
    allow(road_lookup).to receive(:nearest_road).and_return(nil)
    camera = create(:camera)

    expect(described_class.new(road_lookup: road_lookup).snap(camera)).to be_nil
  end

  it "snaps every camera across concurrent lookups, preserving order" do
    cameras = Array.new(5) { create(:camera) }
    # A plain, thread-safe fake (rspec doubles aren't safe to call across threads);
    # tags each segment with its camera's id so we can assert the order is preserved.
    lookup = Class.new do
      def nearest_road(lng:, lat:)
        { osm_way_id: 999, geometry_ewkt: "SRID=4326;LINESTRING(#{lng} #{lat}, #{lng + 0.001} #{lat})", distance_m: 4.0 }
      end
    end.new

    segments = described_class.new(road_lookup: lookup, concurrency: 4).snap_all(cameras)

    expect(segments.size).to eq(5)
    expect(segments).to all(be_persisted)
    expect(segments.map(&:camera_id)).to eq(cameras.map(&:id)) # input order preserved
    expect(MonitoredSegment.count).to eq(5)
  end

  # A road lookup that raises for one specific camera location and succeeds for the
  # rest, so a single failing lookup must NOT abort the whole snap pass.
  def flaky_lookup(failing_lng:)
    Class.new do
      define_method(:failing_lng) { failing_lng }
      def nearest_road(lng:, lat:)
        raise "lookup boom" if lng == failing_lng

        { osm_way_id: 999, geometry_ewkt: "SRID=4326;LINESTRING(#{lng} #{lat}, #{lng + 0.001} #{lat})", distance_m: 4.0 }
      end
    end.new
  end

  [ 1, 4 ].each do |concurrency|
    it "snaps the remaining cameras when one camera's lookup raises (concurrency=#{concurrency})" do
      good_a = create(:camera, location: "SRID=4326;POINT(-104.10 39.0)")
      bad    = create(:camera, location: "SRID=4326;POINT(-104.20 39.0)")
      good_b = create(:camera, location: "SRID=4326;POINT(-104.30 39.0)")
      lookup = flaky_lookup(failing_lng: -104.20)

      segments = nil
      expect {
        segments = described_class.new(road_lookup: lookup, concurrency: concurrency).snap_all([ good_a, bad, good_b ])
      }.not_to raise_error

      expect(segments.map(&:camera_id)).to contain_exactly(good_a.id, good_b.id)
      expect(MonitoredSegment.count).to eq(2)
    end
  end
end
