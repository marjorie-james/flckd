module CameraData
  # Production road lookup backed by the routing engine itself (Valhalla
  # /locate). Snapping against the same graph used for routing guarantees the
  # osm_way_id and geometry line up exactly with what the router excludes — so
  # avoidance targets the precise monitored segment, not a radius.
  #
  # Implements the SegmentSnapper contract:
  #   nearby_roads(lng:, lat:) -> [ { osm_way_id:, geometry_ewkt:, distance_m: }, ... ]
  #   nearest_road(lng:, lat:)  -> the single closest of those, or nil
  class ValhallaRoadLookup
    # Half-length (meters) of the monitored span stored per camera. We clip the
    # full routing edge (which can be kilometers long) down to a short stretch
    # centered on the camera, so avoidance targets only the segment the camera
    # actually watches — not the entire road — and the resulting exclusion
    # polygon stays well under the routing engine's perimeter limit.
    HALF_SPAN_M = 50.0

    # How far a parallel/opposing lane can be from the camera and still be within
    # its view. A camera watching one carriageway of a divided road plainly reads
    # plates on the other carriageway a few car-widths away (the proximity scorer
    # assumes a 75 m read radius); that opposing lane is a separate OSM way, so
    # unless we monitor it too a route can drive right past the camera on the other
    # side and the planner believes it avoided it.
    SIGHTLINE_M = 40.0

    # Max heading difference (degrees, axis-folded so anti-parallel counts as
    # parallel) for a nearby edge to be treated as the same road's other
    # carriageway rather than a cross street. Keeps avoidance road-scoped: we add
    # the opposing lane the camera sees, not every street that crosses near it.
    PARALLEL_TOLERANCE_DEG = 25.0

    def initialize(routing_client: Routing::RoutingEngineClient.build)
      @routing = routing_client
    end

    # Every drivable carriageway the camera watches: the road it sits on plus any
    # roughly-parallel opposing/adjacent lane within SIGHTLINE_M (a separate OSM way
    # on a divided road). Nearest-first. Empty when nothing is in range or the
    # routing engine is unavailable.
    def nearby_roads(lng:, lat:)
      edges = @routing.locate_all(lat: lat, lng: lng, radius: SIGHTLINE_M)

      # One entry per OSM way, at its closest approach, within the sightline.
      roads = edges.group_by { |e| e[:osm_way_id] }
                   .map { |_id, es| es.min_by { |e| e[:distance_m] } }
                   .select { |e| e[:distance_m] <= SIGHTLINE_M }
                   .sort_by { |e| e[:distance_m] }
      return [] if roads.empty?

      primary = roads.first
      primary_bearing = Routing::Polyline.bearing(primary[:shape])
      roads
        .select { |e| e.equal?(primary) || parallel?(primary_bearing, Routing::Polyline.bearing(e[:shape])) }
        .filter_map { |e| build_road(e, lng, lat) }
    rescue Geo::HttpClient::ServiceError
      [] # routing engine unavailable — skip snapping rather than fail the import
    end

    def nearest_road(lng:, lat:)
      nearby_roads(lng: lng, lat: lat).min_by { |r| r[:distance_m] }
    end

    private

    def build_road(edge, lng, lat)
      ewkt = Routing::Polyline.to_linestring_ewkt(edge[:shape])
      return nil unless ewkt

      {
        osm_way_id: edge[:osm_way_id],
        geometry_ewkt: clip_to_span(ewkt, lng, lat) || ewkt,
        distance_m: edge[:distance_m] || 0.0
      }
    end

    # True when two headings lie on roughly the same axis — parallel OR anti-parallel,
    # since opposing carriageways run in opposite directions. A nil bearing (degenerate
    # edge) is treated as parallel so we never silently drop a candidate on bad geometry.
    def parallel?(a, b)
      return true if a.nil? || b.nil?

      diff = (a - b).abs % 180.0
      diff = 180.0 - diff if diff > 90.0
      diff <= PARALLEL_TOLERANCE_DEG
    end

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
