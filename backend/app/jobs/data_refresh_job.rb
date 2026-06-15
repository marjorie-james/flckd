# Scheduled/manual refresh of the camera dataset (feature 003).
#
# Aggregates the live, permissively-licensed OpenStreetMap ALPR substrate
# (continental-US) into the source-of-truth `cameras` table, snapping new cameras
# to their monitored segments, and records a RefreshRun audit. Runs in the
# background on a fixed daily schedule (config/recurring.yml, 08:00 UTC) — FR-010
# (schedule), FR-011 (background, non-blocking), FR-013 (audit), FR-014 (no
# overlapping runs). No user data is involved — reference data only.
#
# Tiling: each UsTiles cell is fetched independently (CameraData::TiledRefresh).
# The job is an ActiveJob continuation — progress (the per-tile cursor + running
# tallies) is checkpointed after every cell, so a deploy/interruption mid-run
# RESUMES from the last completed cell instead of re-fetching the whole country.
#
# `tiles`/`source_factory`/`road_lookup` are injectable so the job is
# deterministic in tests (no network). NOTE: a Proc source_factory isn't
# serializable, so production must use the default (it survives resume); tests
# pass a lambda and run straight-through (the :test adapter never interrupts).
class DataRefreshJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :default

  # Only graceful interrupts resume; a genuine error fails the run (don't silently
  # retry a broken refresh just because some tiles already advanced).
  self.resume_errors_after_advancing = false
  self.max_resumptions = 50

  # Belt-and-suspenders against overlapping runs at the queue layer (FR-014);
  # the RefreshRun running-guard below covers the manual + restart cases.
  limits_concurrency(to: 1, key: "camera_data_refresh") if respond_to?(:limits_concurrency)

  UNSET = Object.new
  private_constant :UNSET

  def perform(_mode = "aggregate", trigger: "scheduled", tiles: nil, source_factory: nil, road_lookup: UNSET)
    run = acquire_run(trigger)
    return :skipped if run == :skipped

    # Default substrate is the PBF-derived local extract (ADR 0002): one "tile"
    # covering the whole served region, so the tiled fan-out / checkpoint /
    # tile-aware reconcile machinery runs trivially with a single cell and no API
    # calls. CAMERA_OSM_SOURCE=overpass flips to the live tiled Overpass path
    # (the escape hatch). Explicit `tiles:`/`source_factory:` (tests) override.
    pbf_mode = tiles.nil? && source_factory.nil? && CameraData.osm_source != "overpass"

    refresh = CameraData::TiledRefresh.new(
      tiles: tiles || (pbf_mode ? [ CameraData::Sources::UsTiles::CONUS ] : CameraData::Sources::UsTiles.cells),
      source_factory: source_factory || (pbf_mode ? method(:pbf_source) : method(:default_source)),
      road_lookup: road_lookup.equal?(UNSET) ? CameraData::ValhallaRoadLookup.new : road_lookup,
      cutoff: run.started_at
    )

    begin
      # One step, resumed via its cursor (the JSON-safe progress Hash). Each cell
      # checkpoints with `set!`, which interrupts here on graceful shutdown; the
      # interrupt (an Exception, not StandardError) flows past the rescue below to
      # the continuation machinery, which re-enqueues the job to resume.
      step :refresh_tiles do |s|
        state = s.cursor || refresh.blank_state
        while state["i"] < refresh.size
          refresh.import_next(state)
          s.set!(state)
        end
        # state["ok"] = the [south, west, north, east] of the tiles that actually
        # refreshed, so freshness is set per data-region (not a global update).
        finalize(run, refresh.finalize(state), state["ok"])
      end

      run
    rescue ActiveJob::Continuation::Error
      raise
    rescue StandardError => e
      # A hard failure (not the per-tile isolation TiledRefresh already handles)
      # must not leave the run stuck in `running` — that would block every future
      # refresh via the guard above. Mark it failed, alert, and re-raise.
      run.update!(status: "failed", finished_at: Time.current,
                  duration_ms: ((Time.current - run.started_at) * 1000).round)
      Telemetry.notify(e, run_id: run.id, phase: "data_refresh")
      raise
    end
  end

  private

  # Start a fresh run, or — when resuming after an interruption — adopt the one
  # already in progress instead of creating a second (FR-014).
  def acquire_run(trigger)
    if continuation.started?
      RefreshRun.running.recent.first || RefreshRun.create!(trigger: trigger, started_at: Time.current)
    elsif RefreshRun.running?
      Rails.logger.info("[camera_data] refresh skipped — another run is already in progress (FR-014)")
      :skipped
    else
      RefreshRun.create!(trigger: trigger, started_at: Time.current)
    end
  end

  # Record the run outcome exactly once. Reconcile + snap already happened inside
  # `result` (TiledRefresh#finalize); persisting status here is guarded so a
  # crash-retry re-entering this step can't double-finalize — once the status is
  # no longer "running", this is a no-op. The whole thing is one transaction so a
  # crash mid-finalize rolls back and the retry redoes it cleanly.
  def finalize(run, result, refreshed_bboxes = [])
    finalized = false
    ActiveRecord::Base.transaction do
      next unless run.reload.status == "running"

      run.update!(
        status: result.status,
        finished_at: Time.current,
        duration_ms: ((Time.current - run.started_at) * 1000).round,
        per_source: result.per_source,
        totals: result.totals
      )
      touch_data_region_freshness(refreshed_bboxes, Time.current)
      finalized = true
    end

    return unless finalized && result.status != "success"

    # Surface degraded/failed runs to telemetry (per_source carries only
    # statuses/counts/error_class — no user data).
    Telemetry.alert(
      "camera_data refresh finished status=#{result.status}",
      run_id: run.id, status: result.status, per_source: result.per_source
    )
  end

  # Set data_freshness_at ONLY on the data-regions that overlap a tile that
  # actually refreshed (FR-008) — replacing the old global update_all, which
  # would falsely freshen regions whose tiles never ran (or failed). The
  # refreshed tiles are ST_Collect'd into one geometry and intersected against
  # each region. `refreshed_bboxes` is the cursor's JSON-safe [s,w,n,e] arrays;
  # values are our own numeric UsTiles cells (to_f makes the interpolation safe).
  def touch_data_region_freshness(refreshed_bboxes, at)
    return if refreshed_bboxes.blank?

    envelopes = refreshed_bboxes.map do |south, west, north, east|
      "ST_MakeEnvelope(#{west.to_f}, #{south.to_f}, #{east.to_f}, #{north.to_f}, 4326)"
    end
    CoverageArea
      .where("ST_Intersects(region, ST_Collect(ARRAY[#{envelopes.join(', ')}]))")
      .update_all(data_freshness_at: at)
  end

  # Default (ADR 0002): read ALPR nodes from the prebuilt GeoJSON filtered out of
  # the OSM PBF extract (infra/scripts/build-cameras.sh). The bbox is ignored —
  # the single served-region "tile" covers the whole file. A named method (not a
  # lambda) so it survives continuation serialization across a resume.
  def pbf_source(_bbox)
    CameraData::Sources::OsmExtractFile.new
  end

  # Escape hatch (ADR 0002): the live/self-hosted Overpass API, fetched one bbox
  # per UsTiles cell for fair-use. Active when CAMERA_OSM_SOURCE=overpass.
  def default_source(bbox)
    CameraData::Sources::Overpass.new(bbox: bbox)
  end
end
