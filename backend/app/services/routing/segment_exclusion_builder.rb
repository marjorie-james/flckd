module Routing
  # Turns monitored segments into the exclusion polygons the routing engine
  # understands. Each segment becomes a buffer polygon around the road the camera
  # reads, so only that segment is avoided — not nearby roads the camera can't see.
  class SegmentExclusionBuilder
    # ~30 m buffer. Wide enough that Valhalla reliably drops the monitored edge
    # from the graph: a thin few-meter ribbon was silently ignored for some
    # segments (the snapped segment geometry sits a couple meters off the routing
    # edge), so the route would be "excluded" yet still drive through the camera.
    # Detection of which cameras a route passes uses a much tighter buffer
    # (Routing::RouteCameraDetector::DETECTION_BUFFER) to avoid over-reporting.
    EXCLUSION_BUFFER = 0.0003

    # All routable monitored segments whose geometry intersects the bbox.
    # A west value greater than east crosses the antimeridian.
    # bbox: [west_lng, min_lat, east_lng, max_lat]. Returns [MonitoredSegment].
    def segments_in_bbox(bbox, min_confidence: 0.0)
      MonitoredSegment
        .for_routing(min_confidence)
        .where(*envelope_predicate(bbox))
        .order(:id)
        .to_a
    end

    # GeoJSON exterior rings ([[lng, lat], ...]) buffering each given segment —
    # exactly the [lon, lat] form Valhalla's exclude_polygons expects. A segment's
    # buffer is computed once and cached (per-builder, i.e. per route request): the
    # avoid loop calls this repeatedly with overlapping segment sets, so caching by
    # id avoids re-buffering the same geometry every pass. EXCLUSION_BUFFER is a
    # constant, safe to interpolate.
    def rings_for(segments)
      return [] if segments.empty?

      cache = (@ring_cache ||= {})
      missing = segments.map(&:id).reject { |id| cache.key?(id) }
      load_rings(missing).each { |id, ring| cache[id] = ring } if missing.any?
      segments.filter_map { |s| cache[s.id] }
    end

    private

    # A west value greater than east denotes a bbox crossing the antimeridian.
    # PostGIS envelopes do not wrap, so split that range into two indexable boxes.
    def envelope_predicate(bbox)
      west, south, east, north = bbox
      if west > east
        [
          "(ST_Intersects(geometry, ST_MakeEnvelope(?, ?, 180.0, ?, 4326)) OR " \
            "ST_Intersects(geometry, ST_MakeEnvelope(-180.0, ?, ?, ?, 4326))) " \
            "/* route-candidate-envelope */",
          west, south, north, south, east, north
        ]
      else
        [ "ST_Intersects(geometry, ST_MakeEnvelope(?, ?, ?, ?, 4326)) " \
          "/* route-candidate-envelope */", *bbox ]
      end
    end

    # Buffers the given segment ids in one query; returns [[id, ring_or_nil], ...].
    def load_rings(ids)
      MonitoredSegment
        .where(id: ids)
        .pluck(:id, Arel.sql("ST_AsGeoJSON(ST_Buffer(geometry, #{EXCLUSION_BUFFER}))"))
        .map { |id, geojson| [ id, geojson && JSON.parse(geojson).dig("coordinates", 0) ] }
    end
  end
end
