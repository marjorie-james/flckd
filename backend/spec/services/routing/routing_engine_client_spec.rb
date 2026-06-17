require "rails_helper"

# Exercises the REAL Valhalla response parsing against recorded fixtures — the
# single most important geo client (it powers camera-segment avoidance) and the
# one previously left without a fixture-backed test. A change in Valhalla's
# JSON shape must break this spec, not production (Constitution Principle II).
RSpec.describe Routing::RoutingEngineClient do
  let(:base_url) { "http://routing.test" }
  subject(:client) { described_class.new(base_url: base_url) }

  def fixture(name) = Rails.root.join("spec/fixtures/valhalla/#{name}").read

  describe "#route" do
    before do
      stub_request(:post, "#{base_url}/route")
        .to_return(status: 200, body: fixture("route.json"),
                   headers: { "Content-Type" => "application/json" })
    end

    subject(:result) do
      client.route(origin: { lat: 41.5868, lng: -93.6250 },
                   destination: { lat: 41.6611, lng: -91.5302 })
    end

    it "normalizes the geometry and converts km totals to meters/seconds" do
      expect(result[:geometry]).to eq("}_qsFt}whMnDsB|GeE")
      expect(result[:distance_m]).to eq(184_227) # 184.227 km -> m, rounded
      expect(result[:duration_s]).to eq(6241)    # 6240.5 s, rounded
    end

    it "maps each maneuver (type, instruction, km->m distance, shape index)" do
      expect(result[:maneuvers].size).to eq(3)
      first = result[:maneuvers].first
      expect(first).to eq(
        type: 1,
        instruction: "Drive east on East Locust Street.",
        distance_m: 502,
        shape_index: 0
      )
    end

    it "sends the locations and exclude_polygons Valhalla expects" do
      client.route(origin: { lat: 1.0, lng: 2.0 }, destination: { lat: 3.0, lng: 4.0 },
                   exclude_polygons: [ [ [ 2.0, 1.0 ], [ 2.1, 1.1 ] ] ])

      expect(WebMock).to have_requested(:post, "#{base_url}/route").with { |req|
        body = JSON.parse(req.body)
        body["costing"] == "auto" &&
          body["locations"] == [ { "lat" => 1.0, "lon" => 2.0 }, { "lat" => 3.0, "lon" => 4.0 } ] &&
          body["exclude_polygons"].length == 1
      }
    end

    it "tolerates a response with no trip (degenerate body)" do
      stub_request(:post, "#{base_url}/route")
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      degenerate = client.route(origin: { lat: 0, lng: 0 }, destination: { lat: 0, lng: 0 })
      expect(degenerate).to eq(geometry: nil, distance_m: 0, duration_s: 0, maneuvers: [])
    end
  end

  describe "#locate" do
    it "returns the nearest edge by snap distance" do
      stub_request(:post, "#{base_url}/locate")
        .to_return(status: 200, body: fixture("locate.json"),
                   headers: { "Content-Type" => "application/json" })

      snap = client.locate(lat: 41.5868, lng: -93.6250)

      expect(snap).to eq(osm_way_id: 12_345_678, shape: "}_qsFt}whMaAbC", distance_m: 4.2)
    end

    it "returns nil when no edge has usable edge_info" do
      stub_request(:post, "#{base_url}/locate")
        .to_return(status: 200, body: [ { "edges" => [] } ].to_json,
                   headers: { "Content-Type" => "application/json" })

      expect(client.locate(lat: 0.0, lng: 0.0)).to be_nil
    end
  end

  describe "#locate_all" do
    it "returns every distinct usable edge within radius, nearest-first" do
      stub_request(:post, "#{base_url}/locate")
        .to_return(status: 200, body: fixture("locate.json"),
                   headers: { "Content-Type" => "application/json" })

      edges = client.locate_all(lat: 41.5868, lng: -93.6250, radius: 40)

      expect(edges).to eq([
        { osm_way_id: 12_345_678, shape: "}_qsFt}whMaAbC", distance_m: 4.2 },
        { osm_way_id: 99_887_766, shape: "}_qsFt}whMnDsB", distance_m: 12.4 }
      ])
    end

    it "skips edges without usable edge_info and returns [] when none qualify" do
      stub_request(:post, "#{base_url}/locate")
        .to_return(status: 200, body: [ { "edges" => [ { "distance" => 3.0, "edge_info" => {} } ] } ].to_json,
                   headers: { "Content-Type" => "application/json" })

      expect(client.locate_all(lat: 0.0, lng: 0.0, radius: 40)).to eq([])
    end
  end

  describe "#status" do
    it "returns the engine status including tileset_last_modified" do
      stub_request(:get, "#{base_url}/status")
        .to_return(status: 200, body: fixture("status.json"),
                   headers: { "Content-Type" => "application/json" })

      expect(client.status["tileset_last_modified"]).to eq(1_780_330_310)
    end
  end

  it "raises ServiceError when the engine is unreachable" do
    stub_request(:post, "#{base_url}/route").to_timeout

    expect {
      client.route(origin: { lat: 0, lng: 0 }, destination: { lat: 0, lng: 0 })
    }.to raise_error(Geo::HttpClient::ServiceError)
  end
end
