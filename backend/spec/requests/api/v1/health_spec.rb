require "rails_helper"

RSpec.describe "GET /api/v1/health", type: :request do
  it "returns ok with a passing database check when the DB is reachable" do
    get "/api/v1/health"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["status"]).to eq("ok")
    expect(body.dig("checks", "database")).to eq("ok")
  end

  it "returns 503 degraded when the database is unreachable" do
    # Simulate the DB being down: the connectivity probe raises.
    allow(ActiveRecord::Base.connection).to receive(:execute)
      .with("SELECT 1").and_raise(ActiveRecord::ConnectionNotEstablished)

    get "/api/v1/health"

    expect(response).to have_http_status(:service_unavailable)
    body = response.parsed_body
    expect(body["status"]).to eq("degraded")
    expect(body.dig("checks", "database")).to eq("error")
  end
end
