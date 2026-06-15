require "rails_helper"

RSpec.describe "GET /api/v1/coverage", type: :request do
  it "reports coverage for a US point" do
    create(:coverage_area, name: "United States")

    get "/api/v1/coverage", params: { lat: 39.74, lng: -104.99 }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["covered"]).to be(true)
    expect(body["area_name"]).to eq("United States")
  end

  it "reports no coverage outside any area" do
    create(:coverage_area, name: "United States")

    get "/api/v1/coverage", params: { lat: 48.85, lng: 2.35 }

    expect(response.parsed_body["covered"]).to be(false)
  end

  it "400s on non-numeric coordinates instead of coercing to (0,0)" do
    get "/api/v1/coverage", params: { lat: "abc", lng: -104.99 }
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on out-of-range coordinates" do
    get "/api/v1/coverage", params: { lat: 200, lng: -104.99 }
    expect(response).to have_http_status(:bad_request)
  end
end

RSpec.describe "GET /api/v1/coverage/bounds", type: :request do
  it "returns the bounding box of the covered region" do
    create(:coverage_area) # MULTIPOLYGON over the continental US

    get "/api/v1/coverage/bounds"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["bounds"]).to eq([ [ -125.0, 24.0 ], [ -66.0, 49.0 ] ])
  end

  it "returns null bounds when no coverage area exists" do
    get "/api/v1/coverage/bounds"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["bounds"]).to be_nil
  end
end
