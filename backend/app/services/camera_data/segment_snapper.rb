module CameraData
  # Snaps a camera to the road segment(s) it monitors, creating MonitoredSegment
  # records whose osm_way_id matches the routing graph. This is what makes
  # avoidance "monitored-segment" rather than radius-based.
  #
  # A camera can monitor more than one segment: on a divided road its opposing
  # carriageway is a *separate* OSM way the camera still sees, so it gets its own
  # MonitoredSegment too — otherwise a route could drive past the camera on the
  # other side and the planner would believe it avoided it. Creation is idempotent
  # per (camera, osm_way_id), so re-running over already-snapped cameras only fills
  # in the carriageways they are missing.
  #
  # `road_lookup` is an object responding to:
  #   nearby_roads(lng:, lat:) -> [ { osm_way_id:, geometry_ewkt:, distance_m: }, ... ]
  # In production this queries the routing graph (Valhalla /locate); in tests it is
  # a simple stub.
  class SegmentSnapper
    # Bounded concurrency for the per-camera road lookups. Each lookup is a Valhalla
    # /locate round-trip plus a spatial clip query, so a cold import (tens of
    # thousands of cameras) is dominated by sequential network latency. Fanning the
    # lookups out across a small pool cuts the snap phase's wall-clock time. Kept
    # well under the DB connection pool (each worker checks out one connection) and
    # overridable via CAMERA_SNAP_CONCURRENCY.
    DEFAULT_CONCURRENCY = Integer(ENV.fetch("CAMERA_SNAP_CONCURRENCY", 4))

    def initialize(road_lookup:, concurrency: DEFAULT_CONCURRENCY)
      @road_lookup = road_lookup
      @concurrency = [ concurrency, 1 ].max
    end

    # Returns the segments created for this camera (possibly several), or nil when
    # nothing was created (no road in range, or every carriageway already snapped).
    def snap(camera)
      create_segments(camera, safe_lookup(camera)).presence
    end

    # Returns the flat list of segments created across all cameras (a camera may
    # contribute more than one). A failed lookup simply contributes nothing.
    def snap_all(cameras)
      cameras = cameras.to_a
      return [] if cameras.empty?
      if @concurrency == 1 || cameras.one?
        return cameras.flat_map { |c| create_segments(c, safe_lookup(c)) }
      end

      # Fan out the network-bound lookups concurrently, then persist serially on the
      # caller's thread — writes stay single-threaded and the output order matches
      # the input (so a failed lookup simply drops its camera, as before).
      roads = lookup_concurrently(cameras)
      cameras.zip(roads).flat_map { |camera, camera_roads| create_segments(camera, camera_roads) }
    end

    private

    def lookup(camera)
      coords = camera.location
      @road_lookup.nearby_roads(lng: coords.x, lat: coords.y)
    end

    # Per-camera lookup that never aborts the whole snap pass: one camera's failed
    # road lookup records nil (later dropped by filter_map) instead of raising at
    # Thread#join and discarding every already-computed lookup. Used by BOTH the
    # concurrent and single-threaded branches so the two paths behave identically.
    def safe_lookup(camera)
      lookup(camera)
    rescue StandardError => e
      Rails.logger.warn("[camera_data] segment snap lookup failed for camera #{camera.id}: #{e.class}")
      nil
    end

    # Runs #lookup for every camera across a bounded worker pool, preserving input
    # order in the result. Each worker checks out its own AR connection for the
    # duration (the lookup runs a spatial clip query), so the pool size stays under
    # the DB connection pool — DEFAULT_CONCURRENCY is sized for that.
    def lookup_concurrently(cameras)
      results = Array.new(cameras.size)
      queue = Queue.new
      cameras.each_with_index { |camera, i| queue << [ camera, i ] }

      Array.new([ @concurrency, cameras.size ].min) do
        Thread.new do
          loop do
            camera, i = begin
              queue.pop(true)
            rescue ThreadError
              break # queue drained
            end
            ActiveRecord::Base.connection_pool.with_connection { results[i] = safe_lookup(camera) }
          end
        end
      end.each(&:join)

      results
    end

    # Persists a MonitoredSegment for each carriageway the camera watches, skipping
    # any OSM way it is already snapped to (idempotent per camera+way). `roads` is
    # nearest-first; the closest is the road the camera sits on. nil/empty -> [].
    def create_segments(camera, roads)
      return [] if roads.blank?

      existing = camera.monitored_segments.pluck(:osm_way_id).to_set
      primary_way = roads.first[:osm_way_id]
      roads.filter_map do |road|
        next if existing.include?(road[:osm_way_id])

        create_segment(camera, road, direction: direction_for(camera, road[:osm_way_id] == primary_way))
      end
    end

    def create_segment(camera, road, direction:)
      camera.monitored_segments.create!(
        osm_way_id: road[:osm_way_id],
        geometry: road[:geometry_ewkt],
        direction: direction,
        snap_distance_m: road[:distance_m] || 0.0
      )
    end

    # The carriageway the camera physically sits on carries its facing direction (if
    # known); an opposing/adjacent carriageway is monitored regardless of travel
    # direction ("both") — the camera sees across it either way. `direction` is not
    # consulted by routing today; it records what the segment represents.
    def direction_for(camera, on_road)
      return "both" unless on_road

      camera.facing_direction.present? ? "forward" : "both"
    end
  end
end
