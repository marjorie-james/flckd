module Routing
  # Client for the self-hosted routing engine (Valhalla). Supports excluding or
  # penalizing specific monitored road segments per request — the mechanism
  # behind monitored-segment camera avoidance.
  class RoutingEngineClient < Geo::HttpClient
    def self.build
      new(base_url: ENV.fetch("ROUTING_URL", "http://routing:8002"))
    end

    # origin/destination: { lat:, lng: }
    # exclude_polygons: array of GeoJSON-style coordinate rings to avoid (hard).
    # exclude_penalty: when true, segments are heavily penalized instead of
    #   excluded (used for the minimum-exposure fallback pass).
    #
    # Returns a normalized hash:
    #   { geometry:, distance_m:, duration_s:, maneuvers: [...] }
    def route(origin:, destination:, exclude_polygons: [], costing_options: {})
      payload = {
        costing: "auto",
        locations: [
          { lat: origin[:lat], lon: origin[:lng] },
          { lat: destination[:lat], lon: destination[:lng] }
        ],
        exclude_polygons: exclude_polygons,
        costing_options: { auto: costing_options }
      }
      body = post("/route", payload)
      normalize(body)
    end

    # Snaps a point to the nearest drivable edge in the routing graph. Returns
    # the OSM way id, the edge's encoded shape, and the snap distance (meters),
    # or nil if nothing nearby. Used to snap cameras to monitored segments.
    #   { osm_way_id:, shape:, distance_m: } | nil
    def locate(lat:, lng:)
      body = post("/locate", { locations: [ { lat: lat, lon: lng } ], costing: "auto", verbose: true })
      edges = Array(body).first&.fetch("edges", nil) || []
      edge = edges.min_by { |e| e["distance"] || Float::INFINITY }
      info = edge && edge["edge_info"]
      return nil unless info && info["way_id"] && info["shape"]

      { osm_way_id: info["way_id"], shape: info["shape"], distance_m: edge["distance"] || 0.0 }
    end

    # Like #locate but returns every distinct drivable edge within `radius` metres
    # of the point, sorted nearest-first. A single OSM way can surface as several
    # directed edges (forward + reverse) sharing one way_id; callers dedupe. Used to
    # find a camera's opposing/parallel carriageway — on a divided road that is a
    # *separate* OSM way the camera still sees, so it must be monitored too.
    #   [ { osm_way_id:, shape:, distance_m: }, ... ]
    def locate_all(lat:, lng:, radius:)
      body = post("/locate", { locations: [ { lat: lat, lon: lng, radius: radius } ], costing: "auto", verbose: true })
      edges = Array(Array(body).first&.dig("edges"))
      edges.filter_map { |e|
        info = e["edge_info"]
        next unless info && info["way_id"] && info["shape"]

        { osm_way_id: info["way_id"], shape: info["shape"], distance_m: e["distance"] || 0.0 }
      }.sort_by { |e| e[:distance_m] }
    end

    # The routing engine's status hash, including `tileset_last_modified` (epoch
    # seconds). Used to detect a stale OSM substrate — the routing graph is built
    # from an OSM extract and is NOT rebuilt on the camera-refresh cadence.
    def status
      get("/status")
    end

    private

    def normalize(body)
      leg = body.dig("trip", "legs", 0) || {}
      summary = body.dig("trip", "summary") || {}
      {
        geometry: leg["shape"],
        distance_m: ((summary["length"] || 0) * 1000).round, # Valhalla returns km
        duration_s: (summary["time"] || 0).round,
        maneuvers: Array(leg["maneuvers"]).map { |m| normalize_maneuver(m) }
      }
    end

    def normalize_maneuver(maneuver)
      {
        type: maneuver["type"],
        instruction: maneuver["instruction"],
        distance_m: ((maneuver["length"] || 0) * 1000).round,
        # begin_shape_index lets the frontend place the maneuver on the polyline.
        shape_index: maneuver["begin_shape_index"]
      }
    end
  end
end
