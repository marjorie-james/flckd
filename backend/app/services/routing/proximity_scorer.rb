module Routing
  # Scores how exposed a route is to cameras as a *soft* cost, not just a count of
  # monitored segments it drives on. For every routable monitored segment within
  # READ_RADIUS_M of the route, it adds (1 - distance / READ_RADIUS_M): a segment the
  # route runs right along contributes ~1, one at the edge of camera range ~0.
  #
  # This is the objective the route selector minimises (traded against time via the
  # aggressiveness λ). It captures what the old on-segment count missed: a detour that
  # technically leaves the monitored 100 m but still hugs a dozen cameras 60 m away is
  # barely an improvement, and this cost says so.
  #
  # Each segment's proximity is further weighted by how the route passes the camera:
  # full cost when the route travels along the camera's facing axis (most readable),
  # discounted toward DIRECTIONAL_FLOOR when it passes perpendicular (poorly positioned
  # for a plate read). This only ever re-ranks already-exposed fallback detours — the
  # selector consults this cost solely when no camera-free route exists, and
  # is_fully_clean / the RouteNotice banner are driven by RouteCameraDetector, not by
  # this — so a discount can never turn a not-clean route into a "clean" claim.
  class ProximityScorer
    READ_RADIUS_M = 75.0 # how far a camera can plausibly read a plate

    # Cost multiplier for a route that passes a camera perpendicular to its facing
    # axis. Never 0: an ALPR still captures off-axis, and facing_direction data quality
    # is uneven — so we discount a misaligned pass without zeroing it out.
    DIRECTIONAL_FLOOR = 0.35
    # Metres each side of the closest-approach point used to estimate the route's local
    # heading: stable against polyline jitter, still "local".
    BEARING_SAMPLE_M = 10.0

    # route: { geometry:, ... } (Valhalla polyline6). `segments` is the already-fetched
    # in-bbox candidate set (the planner computes it once via SegmentExclusionBuilder),
    # so this scores only those rows — by primary key — instead of re-scanning every
    # routable segment with geography math. Routability is already baked into the
    # candidate set. Returns a non-negative Float; 0.0 when no candidate is within
    # range (or the geometry doesn't decode / there are no candidates).
    def cost(route, segments)
      return 0.0 if segments.blank?

      line = Routing::Polyline.safe_linestring_ewkt(route[:geometry])
      return 0.0 unless line

      rows(line, segments).sum do |proximity, route_bearing, facing|
        proximity * directional_factor(route_bearing, facing)
      end
    end

    private

    # Per in-range segment: [proximity (0..1), route_bearing_deg | nil, facing_deg | nil].
    # route_bearing is the azimuth of two points on the route bracketing its
    # closest-approach point to the segment, taken via geography() so it's a true
    # compass bearing rather than a latitude-skewed planar one. ST_Azimuth returns NULL
    # when those points coincide (degenerate/ultra-short route) → nil bearing → no
    # discount. The candidate set is small (only segments within READ_RADIUS_M), so
    # summing per-row in Ruby is cheap and keeps the angle math testable.
    def rows(line, segments)
      expr = "ST_GeomFromEWKT(#{ActiveRecord::Base.connection.quote(line)})"
      frac = "ST_LineLocatePoint(#{expr}, ST_ClosestPoint(#{expr}, monitored_segments.geometry))"
      eps  = "LEAST(0.5, #{BEARING_SAMPLE_M} / NULLIF(ST_Length(geography(#{expr})), 0))"
      p1   = "ST_LineInterpolatePoint(#{expr}, GREATEST(0, #{frac} - #{eps}))"
      p2   = "ST_LineInterpolatePoint(#{expr}, LEAST(1, #{frac} + #{eps}))"

      MonitoredSegment
        .joins(:camera)
        .where(id: segments.map(&:id))
        .where("ST_DWithin(geography(monitored_segments.geometry), geography(#{expr}), #{READ_RADIUS_M})")
        .pluck(
          Arel.sql("GREATEST(0, 1 - ST_Distance(geography(monitored_segments.geometry), geography(#{expr})) / #{READ_RADIUS_M})"),
          Arel.sql("degrees(ST_Azimuth(geography(#{p1}), geography(#{p2})))"),
          Arel.sql("cameras.facing_direction")
        )
    end

    # 1.0 when the route runs along the camera's facing axis (most exposed) or when
    # direction is unknown (omnidirectional camera, or the bearing couldn't be
    # computed); decays to DIRECTIONAL_FLOOR for a perpendicular pass. Axis-based
    # (|cos|) so it doesn't matter which way along the road the camera reads plates —
    # aligned and anti-aligned are equally exposed.
    def directional_factor(route_bearing, facing)
      return 1.0 if route_bearing.nil? || facing.nil?

      align = Math.cos((route_bearing - facing) * Math::PI / 180.0).abs
      DIRECTIONAL_FLOOR + (1.0 - DIRECTIONAL_FLOOR) * align
    end
  end
end
