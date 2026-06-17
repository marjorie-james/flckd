require "rails_helper"

RSpec.describe "GET /api/v1/cameras", type: :request do
  it "returns cameras within the bbox" do
    inside = create(:camera, location: "SRID=4326;POINT(-104.99 39.74)", confidence: 0.9)
    create(:camera, location: "SRID=4326;POINT(-80.0 25.0)", confidence: 0.9) # far away

    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,-104.9,39.8" }

    expect(response).to have_http_status(:ok)
    ids = response.parsed_body["cameras"].map { |c| c["id"] }
    expect(ids).to contain_exactly(inside.id)
  end

  it "includes the snapped location, monitored segment, and facing direction" do
    camera = create(:camera, location: "SRID=4326;POINT(-104.99 39.74)", confidence: 0.9, facing_direction: 90)
    create(:monitored_segment, camera: camera,
                               geometry: "SRID=4326;LINESTRING(-104.991 39.74, -104.989 39.74)")

    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,-104.9,39.8" }

    cam = response.parsed_body["cameras"].find { |c| c["id"] == camera.id }
    expect(cam["facing_direction"]).to eq(90)
    # Camera point projected onto the road it watches (on the line, not beside it).
    expect(cam["snapped_location"]["lat"]).to be_within(1e-6).of(39.74)
    expect(cam["snapped_location"]["lng"]).to be_within(1e-6).of(-104.99)
    expect(cam["segment"]).to eq([ [ -104.991, 39.74 ], [ -104.989, 39.74 ] ])
  end

  it "omits segment fields for a camera that has not been snapped" do
    camera = create(:camera, location: "SRID=4326;POINT(-104.99 39.74)", confidence: 0.9)

    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,-104.9,39.8" }

    cam = response.parsed_body["cameras"].find { |c| c["id"] == camera.id }
    expect(cam["snapped_location"]).to be_nil
    expect(cam["segment"]).to be_nil
    expect(cam["facing_direction"]).to be_nil
  end

  it "400s without a bbox" do
    get "/api/v1/cameras"
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on a non-numeric bbox instead of returning a degenerate box" do
    get "/api/v1/cameras", params: { bbox: "abc,def,ghi,jkl" }
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on a bbox with the wrong number of values" do
    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,-104.9" }
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on an inverted bbox (min > max) instead of a misleading empty success" do
    get "/api/v1/cameras", params: { bbox: "-104.9,39.8,-105.0,39.7" } # min_lng > max_lng
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on an out-of-range bbox" do
    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,-104.9,200" } # max_lat = 200
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on a bbox component that parses to infinity (1e400)" do
    # Float("1e400") yields Float::INFINITY without raising; only the range check
    # rejects it, so an infinite envelope never reaches PostGIS.
    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,1e400,39.8" }
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on a bbox component with surrounding junk (Float is strict, unlike to_f)" do
    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,-104.9foo,39.8" }
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on a non-numeric min_confidence (strict, unlike to_f coercing to 0.0)" do
    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,-104.9,39.8", min_confidence: "abc" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig("details", "param")).to eq("min_confidence")
  end

  it "applies the default 0.0 floor when min_confidence is omitted" do
    inside = create(:camera, location: "SRID=4326;POINT(-104.99 39.74)", confidence: 0.1)

    get "/api/v1/cameras", params: { bbox: "-105.0,39.7,-104.9,39.8" }

    expect(response).to have_http_status(:ok)
    ids = response.parsed_body["cameras"].map { |c| c["id"] }
    expect(ids).to include(inside.id)
  end
end
