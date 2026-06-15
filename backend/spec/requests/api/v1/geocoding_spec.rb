require "rails_helper"

RSpec.describe "GET /api/v1/geocode/search", type: :request do
  # The default deployment spans a whole country (CountryRegistry), so a typed
  # state token disambiguates same-named cities instead of being dropped
  # (FR-003/FR-004). These drive the real GeocoderClient against recorded
  # Nominatim responses (no live geocoder, Principle II).
  def fixture(name) = Rails.root.join("spec/fixtures/geocoder/#{name}").read

  around do |example|
    # Force the country-spanning path: the compose test env sets
    # GEOCODER_REGION_STATE (the single-region dev override), which would
    # otherwise take the legacy strip-and-fallback path.
    keys = %w[GEOCODER_REGION_STATE GEOCODER_VIEWBOX GEOCODER_COUNTRY]
    orig = ENV.to_hash.slice(*keys)
    ENV.delete("GEOCODER_REGION_STATE")
    ENV.delete("GEOCODER_VIEWBOX")
    ENV["GEOCODER_COUNTRY"] = "us"
    example.run
  ensure
    keys.each { |k| orig.key?(k) ? ENV[k] = orig[k] : ENV.delete(k) }
  end

  it "resolves same-named cities to the correct state and does not drop the state token" do
    base = ENV.fetch("GEOCODER_URL", "http://geocoder:8080")
    stub_request(:get, "#{base}/search")
      .with(query: hash_including("q" => "Springfield, IL"))
      .to_return(status: 200, body: fixture("search_springfield_il.json"),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, "#{base}/search")
      .with(query: hash_including("q" => "Springfield, MO"))
      .to_return(status: 200, body: fixture("search_springfield_mo.json"),
                 headers: { "Content-Type" => "application/json" })

    get "/api/v1/geocode/search", params: { q: "Springfield, IL" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["results"].first["label"]).to eq("Springfield, IL")

    get "/api/v1/geocode/search", params: { q: "Springfield, MO" }
    expect(response.parsed_body["results"].first["label"]).to eq("Springfield, MO")
  end
end

RSpec.describe "POST /api/v1/geocode/reverse", type: :request do
  it "400s on non-numeric coordinates instead of reverse-geocoding (0,0)" do
    post "/api/v1/geocode/reverse", params: { coordinate: { lat: "abc", lng: -93.6 } }, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "400s when a coordinate component is missing" do
    post "/api/v1/geocode/reverse", params: { coordinate: { lat: 41.6 } }, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "400s on out-of-range coordinates" do
    post "/api/v1/geocode/reverse", params: { coordinate: { lat: 91, lng: -93.6 } }, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "reverse-geocodes valid coordinates" do
    geocoder = instance_double(Geocoding::GeocoderClient,
                               reverse: { label: "Somewhere, IA", lat: 41.6, lng: -93.6, type: "road", confidence: 0.8 })
    allow(Geocoding::GeocoderClient).to receive(:build).and_return(geocoder)

    post "/api/v1/geocode/reverse", params: { coordinate: { lat: 41.6, lng: -93.6 } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["label"]).to eq("Somewhere, IA")
  end
end
