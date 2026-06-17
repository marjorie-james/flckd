require "rails_helper"

RSpec.describe CameraData::ValhallaRoadLookup do
  let(:routing) { instance_double(Routing::RoutingEngineClient) }

  subject(:lookup) { described_class.new(routing_client: routing) }

  # Two real, decodable polyline6 shapes (their actual bearings are irrelevant —
  # we stub Routing::Polyline.bearing to control the parallel/perpendicular axis).
  let(:shape_a) { "}_qsFt}whMaAbC" }
  let(:shape_b) { "}_qsFt}whMnDsB" }

  describe "#nearby_roads" do
    it "monitors the road the camera sits on plus a roughly-parallel opposing carriageway" do
      allow(routing).to receive(:locate_all).with(lat: 41.6, lng: -93.0, radius: described_class::SIGHTLINE_M).and_return([
        { osm_way_id: 10, shape: shape_a, distance_m: 5.0 },
        { osm_way_id: 11, shape: shape_b, distance_m: 18.0 }
      ])
      allow(Routing::Polyline).to receive(:bearing).with(shape_a).and_return(90.0)
      allow(Routing::Polyline).to receive(:bearing).with(shape_b).and_return(272.0) # anti-parallel ≈ same axis

      roads = lookup.nearby_roads(lng: -93.0, lat: 41.6)

      expect(roads.map { |r| r[:osm_way_id] }).to contain_exactly(10, 11)
      expect(roads).to all(include(:geometry_ewkt))
      expect(roads.first[:geometry_ewkt]).to start_with("SRID=4326;LINESTRING(")
    end

    it "excludes a perpendicular cross street near the camera" do
      allow(routing).to receive(:locate_all).and_return([
        { osm_way_id: 10, shape: shape_a, distance_m: 5.0 },
        { osm_way_id: 12, shape: shape_b, distance_m: 12.0 }
      ])
      allow(Routing::Polyline).to receive(:bearing).with(shape_a).and_return(90.0)
      allow(Routing::Polyline).to receive(:bearing).with(shape_b).and_return(0.0) # perpendicular

      roads = lookup.nearby_roads(lng: -93.0, lat: 41.6)

      expect(roads.map { |r| r[:osm_way_id] }).to eq([ 10 ])
    end

    it "collapses a way's multiple directed edges into one road (closest approach)" do
      allow(routing).to receive(:locate_all).and_return([
        { osm_way_id: 10, shape: shape_a, distance_m: 9.0 },
        { osm_way_id: 10, shape: shape_a, distance_m: 5.0 } # same way, other directed edge
      ])
      allow(Routing::Polyline).to receive(:bearing).and_return(90.0)

      roads = lookup.nearby_roads(lng: -93.0, lat: 41.6)

      expect(roads.size).to eq(1)
      expect(roads.first[:distance_m]).to eq(5.0)
    end

    it "drops candidates beyond the sightline" do
      allow(routing).to receive(:locate_all).and_return([
        { osm_way_id: 10, shape: shape_a, distance_m: 5.0 },
        { osm_way_id: 13, shape: shape_b, distance_m: described_class::SIGHTLINE_M + 10 }
      ])
      allow(Routing::Polyline).to receive(:bearing).and_return(90.0)

      expect(lookup.nearby_roads(lng: -93.0, lat: 41.6).map { |r| r[:osm_way_id] }).to eq([ 10 ])
    end

    it "returns [] when the engine locates nothing" do
      allow(routing).to receive(:locate_all).and_return([])

      expect(lookup.nearby_roads(lng: -93.0, lat: 41.6)).to eq([])
    end

    it "returns [] (rather than raising) when the routing engine is unavailable" do
      allow(routing).to receive(:locate_all).and_raise(Geo::HttpClient::ServiceError)

      expect(lookup.nearby_roads(lng: -93.0, lat: 41.6)).to eq([])
    end
  end

  describe "#nearest_road" do
    it "returns the single closest road" do
      allow(routing).to receive(:locate_all).and_return([
        { osm_way_id: 10, shape: shape_a, distance_m: 5.0 },
        { osm_way_id: 11, shape: shape_b, distance_m: 18.0 }
      ])
      allow(Routing::Polyline).to receive(:bearing).and_return(90.0)

      road = lookup.nearest_road(lng: -93.0, lat: 41.6)

      expect(road[:osm_way_id]).to eq(10)
      expect(road[:geometry_ewkt]).to start_with("SRID=4326;LINESTRING(")
      expect(road[:distance_m]).to eq(5.0)
    end

    it "returns nil when nothing is in range" do
      allow(routing).to receive(:locate_all).and_return([])

      expect(lookup.nearest_road(lng: -93.0, lat: 41.6)).to be_nil
    end
  end
end
