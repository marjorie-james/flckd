# Deterministic fakes for the self-hosted geo services. Tests never hit the
# network (Constitution Principle II) — they exercise real avoidance behavior
# against canned routing/geocoding responses.
module GeoFakes
  # A fake routing engine that mirrors the real one's primitives. A plain request
  # returns the fastest route; a request WITH exclude_polygons returns the next
  # camera-avoiding route; a request with costing_options (and no exclusion) returns
  # the "quiet" candidate. `avoiding` may be:
  #   - a single route hash (returned for every exclusion request), or
  #   - an array of route hashes / :raise symbols consumed in order across the
  #     planner's iterative reroute passes (:raise simulates "no route under this
  #     exclusion set"), or
  #   - nil (avoidance just returns the fastest route).
  # `quiet` is the route returned for a costing_options request (defaults to the
  # fastest route; pass :raise to simulate the quiet costing finding no route).
  # `raise_on_exclude: true` makes every exclusion request raise.
  class FakeRoutingEngine
    # Records the polygons of the last avoidance request so tests can assert
    # which subset a pass excluded, and how many exclusion calls were made.
    attr_reader :last_exclude_polygons, :exclude_calls

    def initialize(fastest:, avoiding: nil, quiet: nil, raise_on_exclude: false)
      @fastest = fastest
      @avoiding = avoiding
      @quiet = quiet
      @raise_on_exclude = raise_on_exclude
      @last_exclude_polygons = nil
      @exclude_calls = 0
    end

    def route(origin:, destination:, exclude_polygons: [], costing_options: {})
      if exclude_polygons.empty?
        return @fastest if costing_options.empty?
        raise Geo::HttpClient::ServiceError, "no quiet route" if @quiet == :raise

        return @quiet || @fastest
      end

      @last_exclude_polygons = exclude_polygons
      @exclude_calls += 1
      raise Geo::HttpClient::ServiceError, "no clean route" if @raise_on_exclude

      entry =
        case @avoiding
        when nil then @fastest
        when Array then @avoiding[@exclude_calls - 1] || @avoiding.last
        else @avoiding
        end
      raise Geo::HttpClient::ServiceError, "no clean route" if entry == :raise

      entry
    end
  end

  # A fake proximity scorer keyed on a route's geometry string, so the planner's
  # time-vs-exposure selection is deterministic without real polylines/PostGIS.
  # Unknown geometries score `default`.
  class FakeProximityScorer
    def initialize(costs_by_geometry = {}, default: 0.0)
      @costs = costs_by_geometry
      @default = default
    end

    # `segments` (the candidate set) is accepted to match the real scorer's
    # signature; the fake keys purely on the route's geometry for determinism.
    def cost(route, _segments = nil)
      @costs.fetch(route[:geometry], @default)
    end
  end

  # A fake camera detector for planner unit tests: maps a route's geometry string
  # to the segments that route passes, so the iteration logic is exercised without
  # real polylines/PostGIS. Only ever returns segments present in `candidates`.
  class FakeDetector
    def initialize(passes_by_geometry = {})
      @passes = passes_by_geometry
    end

    def passed(route, candidates)
      ids = candidates.map(&:id).to_set
      Array(@passes[route[:geometry]]).select { |s| ids.include?(s.id) }
    end
  end

  class FakeGeocoder
    def initialize(results: [], reverse_result: nil)
      @results = results
      @reverse_result = reverse_result
    end

    def search(_text, lang: "en", limit: 5)
      @results.first(limit)
    end

    def reverse(lat:, lng:)
      @reverse_result
    end
  end

  def sample_route(distance_m:, duration_s:, geometry: "_fake_polyline_")
    {
      geometry: geometry,
      distance_m: distance_m,
      duration_s: duration_s,
      maneuvers: [
        { type: "start", instruction: "Head out", distance_m: distance_m, shape_index: 0 },
        { type: "destination", instruction: "Arrive", distance_m: 0, shape_index: 1 }
      ]
    }
  end
end

RSpec.configure do |config|
  config.include GeoFakes
end
