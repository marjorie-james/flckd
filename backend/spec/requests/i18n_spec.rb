require "rails_helper"

# US3: user-facing errors are localized per the request locale (?locale= or
# Accept-Language). Spanish is part of the launch locale set.
RSpec.describe "Localized API errors", type: :request do
  it "returns an English error by default" do
    post "/api/v1/routes", params: { route: { origin: { lat: 1, lng: 2 } } }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["message"]).to match(/start|destination|required/i)
  end

  it "returns a Spanish error when locale=es" do
    post "/api/v1/routes?locale=es", params: { route: { origin: { lat: 1, lng: 2 } } }, as: :json
    expect(response).to have_http_status(:bad_request)
    # es.yml bad_request mentions "inicio" / "destino".
    expect(response.parsed_body["message"]).to match(/inicio|destino/i)
  end
end
