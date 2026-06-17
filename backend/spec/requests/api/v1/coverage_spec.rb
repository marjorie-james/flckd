require "rails_helper"

RSpec.describe "GET /api/v1/coverage", type: :request do
  it "reports present + per-region freshness for a point with camera data (FR-008)" do
    create(:coverage_area, name: "United States", data_freshness_at: Time.utc(2026, 6, 15, 8, 0, 0))

    get "/api/v1/coverage", params: { lat: 39.74, lng: -104.99 }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["covered"]).to be(true)
    expect(body["data_freshness_at"]).to eq("2026-06-15T08:00:00.000Z")
  end

  it "reports absent + null freshness for a point inside the country without data" do
    # Data only over Iowa; an in-US point elsewhere is absent, not camera-free.
    create(:coverage_area, region: "SRID=4326;MULTIPOLYGON(((-96 40, -90 40, -90 43, -96 43, -96 40)))")

    get "/api/v1/coverage", params: { lat: 28.5, lng: -81.5 } # Orlando, FL

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["covered"]).to be(false)
    expect(body["data_freshness_at"]).to be_nil
  end

  it "400s on non-numeric coordinates instead of coercing to (0,0)" do
    get "/api/v1/coverage", params: { lat: "abc", lng: -104.99 }
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on out-of-range coordinates" do
    get "/api/v1/coverage", params: { lat: 200, lng: -104.99 }
    expect(response).to have_http_status(:bad_request)
  end

  it "labels the offending param :coordinate (pair-level) when the longitude is out of range" do
    get "/api/v1/coverage", params: { lat: 39.74, lng: 200 }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig("details", "param")).to eq("coordinate")
  end
end

RSpec.describe "GET /api/v1/coverage/bounds", type: :request do
  # Framing reads GEOCODER_REGION_STATE/VIEWBOX (which docker-compose interpolates
  # from the developer's infra/.env). Pin a deterministic scope per example so the
  # suite never depends on the local deployment scope.
  around do |example|
    keys = %w[GEOCODER_COUNTRY GEOCODER_REGION_STATE GEOCODER_VIEWBOX]
    orig = ENV.to_hash.slice(*keys)
    ENV["GEOCODER_COUNTRY"] = "us"
    ENV.delete("GEOCODER_REGION_STATE")
    ENV.delete("GEOCODER_VIEWBOX")
    example.run
  ensure
    keys.each { |k| orig.key?(k) ? ENV[k] = orig[k] : ENV.delete(k) }
  end

  it "returns the configured country's extent from the registry (FR-007), not the data footprint" do
    # A sparse data-region must NOT shrink the framing — bounds come from the
    # country registry so the map frames the whole country.
    create(:coverage_area, region: "SRID=4326;MULTIPOLYGON(((-96 40, -90 40, -90 43, -96 43, -96 40)))")

    get "/api/v1/coverage/bounds"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["bounds"]).to eq(Geocoding::CountryRegistry.resolve("us").bounds)
    expect(response.parsed_body["bounds"]).to eq([ [ -125.0, 24.5 ], [ -66.9, 49.5 ] ])
  end

  it "frames the country even with no ingested data at all" do
    get "/api/v1/coverage/bounds"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["bounds"]).to eq([ [ -125.0, 24.5 ], [ -66.9, 49.5 ] ])
  end

  it "frames the configured state for a single-state dev deployment" do
    keys = %w[GEOCODER_REGION_STATE GEOCODER_VIEWBOX]
    orig = ENV.to_hash.slice(*keys)
    ENV["GEOCODER_REGION_STATE"] = "Iowa"
    ENV["GEOCODER_VIEWBOX"] = "-96.7,43.6,-90.0,40.3" # Iowa's bbox (Nominatim viewbox order)

    get "/api/v1/coverage/bounds"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["bounds"]).to eq([ [ -96.7, 40.3 ], [ -90.0, 43.6 ] ])
  ensure
    keys.each { |k| orig.key?(k) ? ENV[k] = orig[k] : ENV.delete(k) }
  end
end
