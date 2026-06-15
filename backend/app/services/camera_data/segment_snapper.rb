module CameraData
  # Snaps a camera to the road segment(s) it monitors, creating MonitoredSegment
  # records whose osm_way_id matches the routing graph. This is what makes
  # avoidance "monitored-segment" rather than radius-based.
  #
  # `road_lookup` is an object responding to:
  #   nearest_road(lng:, lat:) -> { osm_way_id:, geometry_ewkt:, distance_m: } | nil
  # In production this queries the OSM road table the routing graph is built
  # from; in tests it is a simple stub.
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

    def snap(camera)
      road = lookup(camera)
      road && create_segment(camera, road)
    end

    def snap_all(cameras)
      cameras = cameras.to_a
      return [] if cameras.empty?
      return cameras.filter_map { |c| snap(c) } if @concurrency == 1 || cameras.one?

      # Fan out the network-bound lookups concurrently, then persist serially on the
      # caller's thread — writes stay single-threaded and the output order matches
      # the input (so a failed lookup simply drops its camera, as before).
      roads = lookup_concurrently(cameras)
      cameras.zip(roads).filter_map { |camera, road| road && create_segment(camera, road) }
    end

    private

    def lookup(camera)
      coords = camera.location
      @road_lookup.nearest_road(lng: coords.x, lat: coords.y)
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
            ActiveRecord::Base.connection_pool.with_connection { results[i] = lookup(camera) }
          end
        end
      end.each(&:join)

      results
    end

    def create_segment(camera, road)
      camera.monitored_segments.create!(
        osm_way_id: road[:osm_way_id],
        geometry: road[:geometry_ewkt],
        direction: direction_for(camera),
        snap_distance_m: road[:distance_m] || 0.0
      )
    end

    # If the camera's facing direction is known we could restrict to one travel
    # direction; absent that, monitor both.
    def direction_for(camera)
      camera.facing_direction.present? ? "forward" : "both"
    end
  end
end
