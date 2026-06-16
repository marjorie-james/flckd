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

  def bad_request_message(accept_language)
    post "/api/v1/routes",
         params: { route: { origin: { lat: 1, lng: 2 } } },
         headers: { "Accept-Language" => accept_language },
         as: :json
    expect(response).to have_http_status(:bad_request)
    response.parsed_body["message"]
  end

  it "negotiates Spanish from the Accept-Language header" do
    expect(bad_request_message("es")).to match(/inicio|destino/i)
  end

  it "negotiates the supported language across q-values and order" do
    # de is unsupported and higher-q; es is the supported choice (FR-002).
    expect(bad_request_message("de;q=0.9, es;q=0.8")).to match(/inicio|destino/i)
  end

  it "falls back a regional variant to its base language (es-MX → es)" do
    expect(bad_request_message("es-MX")).to match(/inicio|destino/i)
  end

  it "uses the English default when no offered language is acceptable" do
    expect(bad_request_message("fr, de")).to match(/start|destination|required/i)
  end

  it "lets an explicit ?locale= override the Accept-Language header" do
    post "/api/v1/routes?locale=es",
         params: { route: { origin: { lat: 1, lng: 2 } } },
         headers: { "Accept-Language" => "en" },
         as: :json
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["message"]).to match(/inicio|destino/i)
  end
end
