require "rails_helper"

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

RSpec.describe "GET /api/v1/geocode/search", type: :request do
  let(:geocoder) { instance_double(Geocoding::GeocoderClient, search: []) }

  before { allow(Geocoding::GeocoderClient).to receive(:build).and_return(geocoder) }

  it "400s when the query is missing" do
    get "/api/v1/geocode/search"
    expect(response).to have_http_status(:bad_request)
  end

  it "passes free-text queries through verbatim, including characters that are " \
     "significant in a URL or query string" do
    # The query reaches the geocoder as a value (Faraday URL-encodes it on the way
    # to Nominatim); it must not be sanitized, truncated, or split here.
    weird = %(123 O'Brien St & "Main", #5?x=1)
    get "/api/v1/geocode/search", params: { q: weird }

    expect(response).to have_http_status(:ok)
    expect(geocoder).to have_received(:search).with(weird, lang: anything, limit: anything)
  end

  it "clamps the result limit to 10" do
    get "/api/v1/geocode/search", params: { q: "des moines", limit: 999 }
    expect(geocoder).to have_received(:search).with("des moines", lang: anything, limit: 10)
  end

  it "defaults the limit to 5 when none is given" do
    get "/api/v1/geocode/search", params: { q: "des moines" }
    expect(geocoder).to have_received(:search).with("des moines", lang: anything, limit: 5)
  end
end
