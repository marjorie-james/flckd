# Performance budgets (Constitution Principle IV). Measured against the request
# layer with the geo services stubbed (deterministic, no network) so the gate
# exercises *our* per-request overhead — serialization, controller, params,
# error handling — not the third-party engines.
#
# Budgets derive from the Success Criteria / plan.md:
#   - route response p95 < 2 s server-side (SC-004)
#   - geocode autocomplete p95 < 300 ms
#
# These run on every CI invocation; a regression past budget fails the build.
require "rails_helper"

RSpec.describe "Performance budgets", type: :request do
  # Number of samples per endpoint. Enough to make a p95 meaningful while
  # keeping the suite fast and deterministic.
  SAMPLES = 30

  # Rate limiting (rack-attack) would trip on the rapid sampling loop below and
  # isn't what this gate measures — disable it for the duration of the budget.
  around do |example|
    previously_enabled = Rack::Attack.enabled
    Rack::Attack.enabled = false
    example.run
    Rack::Attack.enabled = previously_enabled
  end

  # Returns the p-th percentile (0..100) of an array of numbers using the
  # nearest-rank method.
  def percentile(values, pct)
    sorted = values.sort
    rank = (pct / 100.0) * sorted.length
    index = [ rank.ceil - 1, 0 ].max
    sorted[index]
  end

  def measure(samples)
    Array.new(samples) do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end
  end

  describe "POST /api/v1/routes" do
    let(:result) do
      Routing::Result.new(
        geometry: "_poly_", distance_m: 6_000, duration_s: 600,
        maneuvers: [ { type: "start", localized_text: "Go", distance_m: 6_000, shape_index: 0 } ],
        cameras_avoided_count: 2, remaining_cameras: [], is_fully_clean: true,
        fastest_comparison: { distance_m: 5_000, duration_s: 500, added_distance_m: 1_000, added_duration_s: 100 },
        coverage_warning: nil
      )
    end

    let(:params) do
      {
        route: {
          origin: { lat: 39.7392, lng: -104.9903 },
          destination: { lat: 39.7294, lng: -104.8319 },
          locale: "en"
        }
      }
    end

    before do
      planner = instance_double(Routing::RoutePlanner, plan: result)
      allow(Routing::RoutePlanner).to receive(:new).and_return(planner)
    end

    it "stays under the 2 s server-side p95 budget" do
      durations = measure(SAMPLES) do
        post "/api/v1/routes", params: params, as: :json
        expect(response).to have_http_status(:ok)
      end

      p95 = percentile(durations, 95)
      expect(p95).to be < 2.0,
        "route p95 was #{(p95 * 1000).round(1)} ms (budget 2000 ms)"
    end
  end

  describe "GET /api/v1/geocode/search" do
    let(:results) do
      [ { label: "1600 Glenarm Pl, Denver", lat: 39.7449, lng: -104.9899, type: "address", confidence: 0.9 } ]
    end

    before do
      geocoder = instance_double(Geocoding::GeocoderClient, search: results)
      allow(Geocoding::GeocoderClient).to receive(:build).and_return(geocoder)
    end

    it "stays under the 300 ms autocomplete p95 budget" do
      durations = measure(SAMPLES) do
        get "/api/v1/geocode/search", params: { q: "1600 glen", limit: 5 }
        expect(response).to have_http_status(:ok)
      end

      p95 = percentile(durations, 95)
      expect(p95).to be < 0.3,
        "geocode autocomplete p95 was #{(p95 * 1000).round(1)} ms (budget 300 ms)"
    end
  end
end
