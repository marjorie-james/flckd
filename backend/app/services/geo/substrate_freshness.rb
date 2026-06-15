module Geo
  # Detects a stale self-hosted geo substrate. The routing graph / tiles /
  # geocoder index are built from an OSM extract and — unlike the camera dataset
  # — are NOT refreshed on a schedule, so they silently drift from current OSM
  # (new roads, closures), degrading route quality and camera-segment snapping.
  #
  # We read the routing engine's `tileset_last_modified` (a cheap, always-present
  # freshness signal that tracks the actual built graph) and alert via Telemetry
  # when it exceeds the threshold. No user data is involved.
  class SubstrateFreshness
    DEFAULT_STALE_AFTER_DAYS = 30

    Result = Struct.new(:state, :age_days, keyword_init: true) # state: :fresh | :stale | :unknown

    def initialize(routing: Routing::RoutingEngineClient.build, stale_after_days: nil)
      @routing = routing
      @stale_after_days = (stale_after_days || ENV.fetch("GEO_SUBSTRATE_STALE_DAYS", DEFAULT_STALE_AFTER_DAYS)).to_i
    end

    def check
      modified = @routing.status["tileset_last_modified"]
      if modified.nil?
        Telemetry.alert("geo substrate freshness unknown — routing /status had no tileset_last_modified")
        return Result.new(state: :unknown, age_days: nil)
      end

      age_days = ((Time.current - Time.at(modified.to_i)) / 1.day).floor
      if age_days > @stale_after_days
        Telemetry.alert(
          "geo routing tileset is stale — rebuild the substrate (see docs/runbooks/geo-stack.md)",
          age_days: age_days, threshold_days: @stale_after_days
        )
        Result.new(state: :stale, age_days: age_days)
      else
        Result.new(state: :fresh, age_days: age_days)
      end
    rescue Geo::HttpClient::ServiceError => e
      # Can't determine freshness (routing down/unreachable) — worth surfacing too.
      Telemetry.notify(e, check: "geo_substrate_freshness")
      Result.new(state: :unknown, age_days: nil)
    end
  end
end
