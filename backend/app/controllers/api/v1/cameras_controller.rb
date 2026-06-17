module Api
  module V1
    # Lists known cameras within a viewport for display (US4). Returns reference
    # points only — never user data.
    class CamerasController < BaseController
      # Safety valve on a single viewport response. The points are clustered on the
      # client (MapLibre runs supercluster on a worker), so thousands render without
      # main-thread jank; this cap just bounds the payload and the per-camera segment
      # geometry. Reaching it means the count may under-represent the true total, so
      # the client surfaces it rather than truncating silently (FR-011).
      VIEWPORT_LIMIT = 5_000

      # Below this zoom the client clusters the dots and does not draw the
      # monitored stretch, so we skip the per-camera segment geometry entirely:
      # a much lighter payload and no PostGIS segment join for thousands of
      # cameras. The segment fields come back null and the dot falls back to its
      # raw location. At or above this zoom — or when no zoom hint is sent (a
      # caller that always wants full detail) — segments are included.
      SEGMENT_DETAIL_ZOOM = 14

      def index
        bbox = parse_bbox(params.require(:bbox))
        cameras = Camera
                  .routable(min_confidence)
                  .where("ST_Intersects(location, ST_MakeEnvelope(?, ?, ?, ?, 4326))", *bbox)
                  .limit(VIEWPORT_LIMIT)
                  .to_a

        segments = detailed? ? segment_display(cameras.map(&:id)) : {}
        render json: { cameras: cameras.map { |c| camera_json(c, segments[c.id]) } }
      end

      private

      # Whether to include the heavy per-camera segment geometry. An absent zoom
      # keeps the full payload (back-compat); a zoom hint below SEGMENT_DETAIL_ZOOM
      # drops it. Strict like #min_confidence: junk ("abc") is a 400, not a silent
      # coercion that would quietly change the detail level.
      def detailed?
        return true if params[:zoom].blank?

        required_float(params[:zoom], :zoom) >= SEGMENT_DETAIL_ZOOM
      end

      # Per-camera display info for the monitored segment it sits on, batched into a
      # single query (no N+1): the camera point snapped onto the road it actually
      # watches, and that segment's geometry so the client can draw the dot on the
      # road and highlight the monitored stretch. Keyed by camera_id; a camera with
      # no snapped segment is simply absent. DISTINCT ON keeps the closest segment
      # when a camera has more than one.
      def segment_display(camera_ids)
        return {} if camera_ids.empty?

        relation = MonitoredSegment
                   .joins(:camera)
                   .where(camera_id: camera_ids)
                   .select(
                     "DISTINCT ON (monitored_segments.camera_id) monitored_segments.camera_id AS camera_id",
                     "monitored_segments.direction AS direction",
                     "ST_AsGeoJSON(monitored_segments.geometry) AS segment_geojson",
                     "ST_X(ST_ClosestPoint(monitored_segments.geometry, cameras.location)) AS snap_lng",
                     "ST_Y(ST_ClosestPoint(monitored_segments.geometry, cameras.location)) AS snap_lat"
                   )
                   .order("monitored_segments.camera_id, monitored_segments.snap_distance_m")

        MonitoredSegment.connection.select_all(relation.to_sql).each_with_object({}) do |row, acc|
          acc[row["camera_id"].to_i] = {
            snapped_location: { lat: row["snap_lat"].to_f, lng: row["snap_lng"].to_f },
            segment: JSON.parse(row["segment_geojson"])["coordinates"],
            direction: row["direction"]
          }
        end
      end

      def parse_bbox(raw)
        parts = raw.split(",")
        raise ActionController::ParameterMissing, :bbox unless parts.size == 4

        # Float() (not to_f) so non-numeric input is rejected as a 400 rather than
        # silently coerced to a degenerate 0,0,0,0 box.
        min_lng, min_lat, max_lng, max_lat = parts.map { |p| Float(p) }
        # Reject inverted or out-of-range boxes (which would otherwise yield a
        # misleading empty success instead of a 400).
        in_range = [ min_lng, max_lng ].all? { |v| v.between?(-180, 180) } &&
                   [ min_lat, max_lat ].all? { |v| v.between?(-90, 90) }
        raise ActionController::ParameterMissing, :bbox unless in_range && min_lng <= max_lng && min_lat <= max_lat

        [ min_lng, min_lat, max_lng, max_lat ]
      rescue ArgumentError, TypeError
        raise ActionController::ParameterMissing, :bbox
      end

      # Strict, matching parse_bbox / BaseController#required_float: an optional or
      # empty min_confidence keeps the 0.0 default (no floor), but junk ("abc")
      # yields a 400 rather than silently coercing to 0.0 and returning everything.
      def min_confidence
        params[:min_confidence].present? ? required_float(params[:min_confidence], :min_confidence) : 0.0
      end

      def camera_json(camera, segment)
        {
          id: camera.id,
          location: { lat: camera.location.y, lng: camera.location.x },
          # Where the camera sits on the road it watches, and that road stretch, so
          # the dot renders on the road (not floating beside it) and the monitored
          # segment can be highlighted. nil when the camera hasn't been snapped yet.
          snapped_location: segment&.dig(:snapped_location),
          segment: segment&.dig(:segment),
          # Compass bearing the camera faces (0–359), or nil for omnidirectional/360.
          facing_direction: camera.facing_direction,
          camera_type: camera.camera_type,
          confidence: camera.confidence,
          verification_status: camera.verification_status
        }
      end
    end
  end
end
