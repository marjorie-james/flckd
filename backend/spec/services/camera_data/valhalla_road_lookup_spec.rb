require "rails_helper"

RSpec.describe CameraData::ValhallaRoadLookup do
  let(:routing) { instance_double(Routing::RoutingEngineClient) }

  subject(:lookup) { described_class.new(routing_client: routing) }

  it "snaps a point to a road segment using the routing graph" do
    allow(routing).to receive(:locate).with(lat: 41.6878, lng: -93.0602).and_return(
      { osm_way_id: 15_932_922, shape: "_p~iF~ps|U_ulLnnqC_mqNvxq`@", distance_m: 4.2 }
    )

    road = lookup.nearest_road(lng: -93.0602, lat: 41.6878)

    expect(road[:osm_way_id]).to eq(15_932_922)
    expect(road[:geometry_ewkt]).to start_with("SRID=4326;LINESTRING(")
    expect(road[:distance_m]).to eq(4.2)
  end

  it "returns nil when the engine locates nothing" do
    allow(routing).to receive(:locate).and_return(nil)

    expect(lookup.nearest_road(lng: -93.0, lat: 41.6)).to be_nil
  end

  it "returns nil (rather than raising) when the routing engine is unavailable" do
    allow(routing).to receive(:locate).and_raise(Geo::HttpClient::ServiceError)

    expect(lookup.nearest_road(lng: -93.0, lat: 41.6)).to be_nil
  end
end
