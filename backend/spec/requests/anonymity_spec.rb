require "rails_helper"

# US2: the service must not retain identifiable records and must not require an
# account/cookie. These specs assert the observable anonymity guarantees at the
# HTTP layer.
RSpec.describe "Anonymity guarantees", type: :request do
  let(:params) do
    {
      route: {
        origin: { lat: 39.7392, lng: -104.9903 },
        destination: { lat: 39.7294, lng: -104.8319 }
      }
    }
  end

  def stub_planner
    result = Routing::Result.new(
      geometry: "_p_", distance_m: 6000, duration_s: 600, maneuvers: [],
      cameras_avoided_count: 0, remaining_cameras: [], is_fully_clean: true,
      fastest_comparison: { distance_m: 6000, duration_s: 600, added_distance_m: 0, added_duration_s: 0 },
      coverage_warning: nil
    )
    planner = instance_double(Routing::RoutePlanner, plan: result)
    allow(Routing::RoutePlanner).to receive(:new).and_return(planner)
  end

  it "requires no account, login, or session cookie" do
    stub_planner
    post "/api/v1/routes", params: params, as: :json

    expect(response).to have_http_status(:ok)
    # No identifying Set-Cookie (no session/_csrf cookie established).
    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "redacts route coordinates from the parameter logs" do
    # Rails may precompile filter_parameters into a single Regexp; assert the
    # geo param names are matched whether the entry is a symbol or a regexp.
    filters = Rails.application.config.filter_parameters
    %w[origin destination lat lng].each do |name|
      matched = filters.any? { |f| f.is_a?(Regexp) ? f.match?(name) : f.to_s == name }
      expect(matched).to be(true), "expected '#{name}' to be a filtered parameter"
    end
  end

  it "does not tag request logs with the client IP" do
    expect(Rails.application.config.log_tags).to eq([ :request_id ])
  end

  it "never writes the client IP to the request log" do
    stub_planner
    io = StringIO.new
    capture_logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    allow(Rails).to receive(:logger).and_return(capture_logger)

    post "/api/v1/routes", params: params, as: :json,
                           headers: { "REMOTE_ADDR" => "203.0.113.7" }

    log = io.string
    expect(log).to include("Started POST") # the request is still logged…
    expect(log).not_to include("203.0.113.7") # …but the client IP never is
    expect(log).not_to match(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/) # no IPv4 at all
  end

  it "persists no record linking the request to a user" do
    stub_planner
    expect {
      post "/api/v1/routes", params: params, as: :json
    }.not_to change { [ Camera.count, MonitoredSegment.count, CoverageArea.count ] }
    # There is no RouteRequest/Route table at all — routes are ephemeral.
    expect(ActiveRecord::Base.connection.tables).not_to include("routes", "route_requests")
  end

  # The same anonymity guarantees must hold at country scale across every
  # geographic path — geocode, coverage, and route (FR-011 / SC-006). Geocoding
  # runs entirely on our self-hosted Nominatim (no third party ever sees a typed
  # address); these guard that no coordinates or client IPs reach the logs.
  describe "country-scaled geographic paths" do
    def capture_log
      io = StringIO.new
      logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
      allow(Rails).to receive(:logger).and_return(logger)
      yield
      io.string
    end

    it "leaks no client IP or coordinates when geocoding across the country" do
      base = ENV.fetch("GEOCODER_URL", "http://geocoder:8080")
      stub_request(:get, "#{base}/search")
        .with(query: hash_including("format" => "jsonv2"))
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      log = capture_log do
        get "/api/v1/geocode/search", params: { q: "Springfield, IL" },
                                      headers: { "REMOTE_ADDR" => "203.0.113.7" }
      end

      expect(response).to have_http_status(:ok)
      expect(log).not_to include("203.0.113.7")
      expect(log).not_to match(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/)
    end

    it "leaks no client IP when checking coverage at a country-scale point" do
      create(:coverage_area)

      log = capture_log do
        get "/api/v1/coverage", params: { lat: 41.59, lng: -93.62 },
                                headers: { "REMOTE_ADDR" => "198.51.100.9" }
      end

      expect(response).to have_http_status(:ok)
      expect(log).not_to include("198.51.100.9")
    end

    it "sends a typed address only to our self-hosted geocoder, never a third party" do
      base = ENV.fetch("GEOCODER_URL", "http://geocoder:8080")
      stub = stub_request(:get, "#{base}/search")
        .with(query: hash_including("format" => "jsonv2"))
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      # WebMock disallows real net connections in the suite, so any third-party
      # egress would raise; the request resolving against our own geocoder host
      # is the positive assertion of "self-hosted only".
      get "/api/v1/geocode/search", params: { q: "1007 East Grand Avenue, Des Moines, IA" }

      expect(stub).to have_been_requested
      expect(%w[geocoder localhost 127.0.0.1]).to include(URI(base).host)
    end
  end
end
