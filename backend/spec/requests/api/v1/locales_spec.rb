require "rails_helper"

# US3: the supported-languages endpoint drives the language switcher.
RSpec.describe "GET /api/v1/meta/locales", type: :request do
  it "lists the supported locales with a default" do
    get "/api/v1/meta/locales"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["default"]).to be_present
    codes = body["locales"].map { |l| l["code"] }
    expect(codes).to include("en")
  end
end
