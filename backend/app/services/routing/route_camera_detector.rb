module Routing
  # Given a route and a set of candidate monitored segments, returns the subset
  # the route actually drives through — its decoded geometry passes within
  # DETECTION_BUFFER of the segment. Used by the iterative avoidance loop ("which
  # cameras does this route still pass?") and by the fastest-route comparison.
  class RouteCameraDetector
    # ~9 m: tight enough to mean "the route is ON this road", not merely near a
    # parallel street. Deliberately narrower than the (wide) exclusion buffer:
    # exclusion errs toward reliably dropping the edge, detection errs toward not
    # over-reporting cameras the route doesn't actually pass.
    DETECTION_BUFFER = 0.00008

    # route: { geometry:, ... } (Valhalla polyline6). segments: [MonitoredSegment].
    # Returns the subset of `segments` the route passes, preserving input order.
    def passed(route, segments)
      return [] if segments.empty?

      line = Routing::Polyline.safe_linestring_ewkt(route[:geometry])
      return [] unless line

      hits = hit_ids(line, segments.map(&:id), route[:geometry])
      segments.select { |s| hits.include?(s.id) }
    end

    private

    # ST_DWithin(geometry, line, DETECTION_BUFFER) is sargable — it lets the planner
    # use the GiST index on `geometry` rather than computing ST_Buffer(geometry) per
    # row. Equivalent to the old buffered ST_Intersects (a line within R of the
    # segment iff the segment is within R of the line). Memoized per (route, candidate
    # set) because the avoid loop re-checks the same route's passed set several times
    # within one plan; the detector is built per RoutePlanner, so the cache is
    # per-request.
    def hit_ids(line, ids, encoded)
      (@hit_cache ||= {})[[ encoded, ids ]] ||=
        MonitoredSegment
          .where(id: ids)
          .where("ST_DWithin(geometry, ST_GeomFromEWKT(?), ?)", line, DETECTION_BUFFER)
          .pluck(:id)
          .to_set
    end
  end
end
