module CameraData
  # Production road lookup backed by the routing engine itself (Valhalla
  # /locate). Snapping against the same graph used for routing guarantees the
  # osm_way_id and geometry line up exactly with what the router excludes — so
  # avoidance targets the precise monitored segment, not a radius.
  #
  # Implements the SegmentSnapper contract:
  #   nearest_road(lng:, lat:) -> { osm_way_id:, geometry_ewkt:, distance_m: } | nil
  class ValhallaRoadLookup
    # Half-length (meters) of the monitored span stored per camera. We clip the
    # full routing edge (which can be kilometers long) down to a short stretch
    # centered on the camera, so avoidance targets only the segment the camera
    # actually watches — not the entire road — and the resulting exclusion
    # polygon stays well under the routing engine's perimeter limit.
    HALF_SPAN_M = 50.0

    def initialize(routing_client: Routing::RoutingEngineClient.build)
      @routing = routing_client
    end

    def nearest_road(lng:, lat:)
      located = @routing.locate(lat: lat, lng: lng)
      return nil unless located

      ewkt = Routing::Polyline.to_linestring_ewkt(located[:shape])
      return nil unless ewkt

      {
        osm_way_id: located[:osm_way_id],
        geometry_ewkt: clip_to_span(ewkt, lng, lat) || ewkt,
        distance_m: located[:distance_m] || 0.0
      }
    rescue Geo::HttpClient::ServiceError
      nil # routing engine unavailable — skip snapping rather than fail the import
    end

    private

    # Clips the edge to a ~2*HALF_SPAN_M stretch centered on the camera's
    # projection onto the line. Returns EWKT, or nil if the clip can't be
    # computed (caller falls back to the full edge).
    def clip_to_span(ewkt, lng, lat)
      conn = ActiveRecord::Base.connection
      line = "ST_GeomFromEWKT(#{conn.quote(ewkt)})"
      point = "ST_SetSRID(ST_MakePoint(#{lng.to_f}, #{lat.to_f}), 4326)"
      conn.select_value(<<~SQL.squish)
        SELECT ST_AsEWKT(
          ST_LineSubstring(g,
            GREATEST(0.0, ST_LineLocatePoint(g, p) - frac),
            LEAST(1.0,   ST_LineLocatePoint(g, p) + frac)))
        FROM (
          SELECT #{line} AS g, #{point} AS p,
                 #{HALF_SPAN_M} / NULLIF(ST_Length(geography(#{line})), 0) AS frac
        ) s
        WHERE frac IS NOT NULL
      SQL
    end
  end
end
