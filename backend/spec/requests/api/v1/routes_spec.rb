require "rails_helper"

RSpec.describe "POST /api/v1/routes", type: :request do
  let(:clean) do
    {
      geometry: "_poly_", distance_m: 6_000, duration_s: 600,
      maneuvers: [ { type: "start", instruction: "Go", distance_m: 6_000, shape_index: 0 } ]
    }
  end
  let(:fastest) { clean.merge(distance_m: 5_000, duration_s: 500) }

  let(:params) do
    {
      route: {
        origin: { lat: 39.7392, lng: -104.9903 },
        destination: { lat: 39.7294, lng: -104.8319 },
        locale: "en"
      }
    }
  end

  # Inject a fake planner so the request spec doesn't need a live routing engine.
  def stub_planner_with(result)
    planner = instance_double(Routing::RoutePlanner, plan: result)
    allow(Routing::RoutePlanner).to receive(:new).and_return(planner)
  end

  def result_struct(overrides = {})
    Routing::Result.new({
      geometry: "_poly_", distance_m: 6_000, duration_s: 600,
      maneuvers: [ { type: "start", localized_text: "Go", distance_m: 6_000, shape_index: 0 } ],
      cameras_avoided_count: 2, remaining_cameras: [], is_fully_clean: true,
      fastest_comparison: {
        distance_m: 5_000, duration_s: 500, added_distance_m: 1_000, added_duration_s: 100,
        geometry: "_fastpoly_", cameras_passed_count: 2
      },
      coverage_warning: nil
    }.merge(overrides))
  end

  it "returns a fully-clean avoiding route" do
    stub_planner_with(result_struct)

    post "/api/v1/routes", params: params, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["is_fully_clean"]).to be(true)
    expect(body["cameras_avoided_count"]).to eq(2)
    expect(body["fastest_comparison"]).to include("added_duration_s" => 100)
  end

  it "includes the fastest route's geometry and camera count in the comparison" do
    stub_planner_with(result_struct)

    post "/api/v1/routes", params: params, as: :json

    expect(response).to have_http_status(:ok)
    fc = response.parsed_body["fastest_comparison"]
    expect(fc).to include("geometry" => "_fastpoly_", "cameras_passed_count" => 2)
  end

  it "returns a minimum-exposure route with remaining cameras when no clean route exists" do
    stub_planner_with(result_struct(
      is_fully_clean: false,
      remaining_cameras: [ { osm_way_id: 999 } ]
    ))

    post "/api/v1/routes", params: params, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["is_fully_clean"]).to be(false)
    expect(body["remaining_cameras"]).to eq([ { "osm_way_id" => 999 } ])
  end

  it "400s when required params are missing" do
    post "/api/v1/routes", params: { route: { origin: { lat: 1, lng: 2 } } }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["code"]).to eq("bad_request")
  end

  it "400s on non-numeric coordinates instead of routing Null Island" do
    # Without validation, .to_f would coerce "abc" to 0.0 and plan a (0,0) route.
    expect(Routing::RoutePlanner).not_to receive(:new)
    post "/api/v1/routes",
         params: { route: { origin: { lat: "abc", lng: -104.99 }, destination: { lat: 39.7, lng: -104.8 } } },
         as: :json
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["code"]).to eq("bad_request")
  end

  it "400s on out-of-range coordinates" do
    post "/api/v1/routes",
         params: { route: { origin: { lat: 91.0, lng: -104.99 }, destination: { lat: 39.7, lng: -104.8 } } },
         as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on a JSON number that parses to infinity (1e400) instead of routing it" do
    # JSON.parse coerces a huge exponent to Float::INFINITY, which passes Float()
    # without raising — only the explicit range check rejects it. Guards that path.
    expect(Routing::RoutePlanner).not_to receive(:new)
    post "/api/v1/routes",
         params: %({"route":{"origin":{"lat":1e400,"lng":-104.99},"destination":{"lat":39.7,"lng":-104.8}}}),
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["code"]).to eq("bad_request")
  end

  it "accepts coordinates exactly on the range boundary (lat 90, lng 180)" do
    stub_planner_with(result_struct)
    post "/api/v1/routes",
         params: { route: { origin: { lat: 90.0, lng: 180.0 }, destination: { lat: -90.0, lng: -180.0 } } },
         as: :json
    expect(response).to have_http_status(:ok)
  end

  it "responds with a structured error code when the routing service is down" do
    planner = instance_double(Routing::RoutePlanner)
    allow(Routing::RoutePlanner).to receive(:new).and_return(planner)
    allow(planner).to receive(:plan).and_raise(Geo::HttpClient::ServiceError)

    post "/api/v1/routes", params: params, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["code"]).to eq("no_route")
  end
end
