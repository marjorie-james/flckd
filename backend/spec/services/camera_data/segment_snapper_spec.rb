require "rails_helper"

RSpec.describe CameraData::SegmentSnapper do
  # Stub road lookup: always returns a single known road segment.
  let(:road_lookup) do
    instance_double(
      CameraData::ValhallaRoadLookup,
      nearby_roads: [
        {
          osm_way_id: 999,
          geometry_ewkt: "SRID=4326;LINESTRING(-104.9905 39.7392, -104.9901 39.7392)",
          distance_m: 4.0
        }
      ]
    )
  end

  it "creates a monitored segment snapped to the nearest road" do
    camera = create(:camera)
    segments = described_class.new(road_lookup: road_lookup).snap(camera)

    expect(segments.size).to eq(1)
    expect(segments.first).to be_persisted
    expect(segments.first.osm_way_id).to eq(999)
    expect(camera.monitored_segments.count).to eq(1)
  end

  it "monitors the opposing carriageway too, as its own segment" do
    # A divided road: the camera sits on way 999, its opposing carriageway is the
    # separate way 1000 a few metres away — the camera still sees it.
    allow(road_lookup).to receive(:nearby_roads).and_return([
      { osm_way_id: 999,  geometry_ewkt: "SRID=4326;LINESTRING(-104.9905 39.7392, -104.9901 39.7392)", distance_m: 4.0 },
      { osm_way_id: 1000, geometry_ewkt: "SRID=4326;LINESTRING(-104.9905 39.7390, -104.9901 39.7390)", distance_m: 18.0 }
    ])
    camera = create(:camera, facing_direction: 90)

    segments = described_class.new(road_lookup: road_lookup).snap(camera)

    expect(segments.map(&:osm_way_id)).to contain_exactly(999, 1000)
    by_way = segments.index_by(&:osm_way_id)
    expect(by_way[999].direction).to eq("forward")  # the road the camera sits on
    expect(by_way[1000].direction).to eq("both")     # opposing carriageway, watched either way
  end

  it "is idempotent per (camera, way): re-snapping only adds the missing carriageway" do
    camera = create(:camera)
    camera.monitored_segments.create!(
      osm_way_id: 999, geometry: "SRID=4326;LINESTRING(-104.9905 39.7392, -104.9901 39.7392)",
      direction: "both", snap_distance_m: 4.0
    )
    allow(road_lookup).to receive(:nearby_roads).and_return([
      { osm_way_id: 999,  geometry_ewkt: "SRID=4326;LINESTRING(-104.9905 39.7392, -104.9901 39.7392)", distance_m: 4.0 },
      { osm_way_id: 1000, geometry_ewkt: "SRID=4326;LINESTRING(-104.9905 39.7390, -104.9901 39.7390)", distance_m: 18.0 }
    ])

    added = described_class.new(road_lookup: road_lookup).snap(camera)

    expect(added.map(&:osm_way_id)).to eq([ 1000 ])
    expect(camera.monitored_segments.pluck(:osm_way_id)).to contain_exactly(999, 1000)
  end

  it "returns nil when no road is found" do
    allow(road_lookup).to receive(:nearby_roads).and_return([])
    camera = create(:camera)

    expect(described_class.new(road_lookup: road_lookup).snap(camera)).to be_nil
  end

  it "snaps every camera across concurrent lookups, preserving order" do
    cameras = Array.new(5) { create(:camera) }
    # A plain, thread-safe fake (rspec doubles aren't safe to call across threads);
    # tags each segment with its camera's id so we can assert the order is preserved.
    lookup = Class.new do
      def nearby_roads(lng:, lat:)
        [ { osm_way_id: 999, geometry_ewkt: "SRID=4326;LINESTRING(#{lng} #{lat}, #{lng + 0.001} #{lat})", distance_m: 4.0 } ]
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
      def nearby_roads(lng:, lat:)
        raise "lookup boom" if lng == failing_lng

        [ { osm_way_id: 999, geometry_ewkt: "SRID=4326;LINESTRING(#{lng} #{lat}, #{lng + 0.001} #{lat})", distance_m: 4.0 } ]
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
