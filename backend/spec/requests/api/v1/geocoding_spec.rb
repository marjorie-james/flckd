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
