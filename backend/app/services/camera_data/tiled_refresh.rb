module CameraData
  # Nationwide refresh of a single tiled source (OpenStreetMap via Overpass).
  #
  # Each UsTiles cell is fetched + imported INDEPENDENTLY, so one unreachable
  # tile no longer wastes the whole pass — the old `Overpass#fetch` looped every
  # cell and a single failure aborted the entire source. The stale reconciler
  # then runs ONLY over the cells that succeeded, so a failed tile can never
  # false-retire its cameras (the non-obvious correctness constraint in ADR 0001:
  # cameras in an unfetched tile look "missing" and would auto-retire after 3
  # such failures — FR-008/009/012).
  #
  # The work is exposed two ways:
  #   * #call — run all tiles + finalize in one shot (non-resumable callers/tests).
  #   * #blank_state / #import_next / #finalize — drive one tile at a time so
  #     DataRefreshJob can checkpoint progress on the continuation cursor and
  #     resume after an interruption (deploy) without re-fetching done tiles.
  #     `state` is a plain JSON-safe Hash so it survives ActiveJob serialization.
  #
  # `source_factory` is `->(bbox)` returning a Sources::Base for that cell, so the
  # job is deterministic in tests; production passes the live Overpass factory.
  # `cutoff` (the run's start) decides seen-vs-missing in reconciliation and must
  # stay fixed across resumes — the job passes `run.started_at`.
  class TiledRefresh
    Result = RefreshResult # shared shape (see CameraData::RefreshResult)

    def initialize(tiles:, source_factory:, road_lookup: nil, cutoff: nil)
      @tiles = Array(tiles)
      @source_factory = source_factory
      @road_lookup = road_lookup
      @cutoff = cutoff || Time.current
    end

    def size = @tiles.size

    # Fresh progress state. Plain string keys + arrays so it round-trips cleanly
    # through the continuation cursor's JSON serialization.
    # "is_delta" / "deleted_refs" track the delta path for finalize; old cursors
    # without these keys degrade gracefully (is_delta nil = falsy → full path).
    def blank_state
      { "i" => 0, "added" => 0, "updated" => 0, "skipped" => 0,
        "failed" => 0, "ok" => [], "error_class" => nil,
        "is_delta" => false, "deleted_refs" => [] }
    end

    def call
      state = blank_state
      import_next(state) until state["i"] >= @tiles.size
      finalize(state)
    end

    # Import the tile at state["i"] in isolation and advance the cursor. A failed
    # tile is recorded (failed +1) and skipped, never raised, so one bad cell
    # doesn't abort the pass. Mutates and returns state.
    #
    # Delta path: when the source supports delta and `data_source.last_imported_at`
    # is within the delta window, only changed cameras are fetched. Deleted refs
    # are accumulated in state so finalize can bulk-touch unchanged cameras before
    # the stale reconciler runs.
    def import_next(state)
      cell = @tiles[state["i"]]
      begin
        source = @source_factory.call(cell)
        @source_name ||= source.source_name
        @importer ||= Importer.for_source(source)
        since = delta_since
        if source.supports_delta?(since: since)
          delta = source.fetch_delta(since: since)
          stats = @importer.import(delta[:upserted])
          (state["deleted_refs"] ||= []).concat(delta[:deleted_refs])
          state["is_delta"] = true
        else
          stats = @importer.import(source.fetch)
        end
        state["added"] += stats.added
        state["updated"] += stats.updated
        state["skipped"] += stats.skipped
        state["ok"] << [ cell[:south], cell[:west], cell[:north], cell[:east] ]
      rescue StandardError => e
        state["failed"] += 1
        state["error_class"] = e.class.name
        Rails.logger.warn("[camera_data] tile #{cell.values_at(:south, :west, :north, :east).join(',')} failed: #{e.class}")
      end
      state["i"] += 1
      state
    end

    # Reconcile (within successful tiles only) + snap; returns the run Result.
    # For delta runs, bulk-touch unchanged cameras first so the stale reconciler
    # doesn't flag them as missing (they simply weren't in the diff).
    def finalize(state)
      if state["is_delta"]
        StaleReconciler.new.touch_seen(data_source: data_source, except_refs: state.fetch("deleted_refs", []))
        retired = reconcile_global
      else
        retired = reconcile(state["ok"])
      end
      snapped = snap
      build_result(state, retired: retired, snapped: snapped)
    end

    private

    def importer = @importer

    def data_source
      @data_source ||= (@source_name && DataSource.find_by(name: @source_name))
    end

    # The timestamp to use as the delta anchor — snapshotted exactly once on the
    # first tile so a mid-run DataSource creation (by the importer) cannot shift
    # later tiles onto the delta path when the source had no prior baseline.
    # Uses a boolean flag rather than ||= because ||= does not memoize nil.
    def delta_since
      unless defined?(@delta_since_set)
        @delta_since = data_source&.last_imported_at
        @delta_since_set = true
      end
      @delta_since
    end

    # Reconcile only within successfully-fetched tiles (see class note). `ok` is an
    # array of [south, west, north, east] arrays (JSON-safe cursor form).
    def reconcile(ok)
      return 0 unless data_source

      bboxes = ok.map { |south, west, north, east| { south: south, west: west, north: north, east: east } }
      StaleReconciler.new.reconcile(data_source: data_source, cutoff: @cutoff, bboxes: bboxes).retired
    end

    # For delta runs, bulk-touch already marked all unchanged cameras as seen, so
    # we reconcile globally (bboxes: nil) to catch deleted_refs outside processed tiles.
    def reconcile_global
      return 0 unless data_source

      StaleReconciler.new.reconcile(data_source: data_source, cutoff: @cutoff).retired
    end

    # Snap any of the source's cameras with no monitored segment yet (idempotent;
    # best-effort — skipped when no road lookup is configured).
    def snap
      return 0 if @road_lookup.nil? || data_source.nil?

      unsnapped = Camera.where(data_source: data_source)
                        .left_joins(:monitored_segments)
                        .where(monitored_segments: { id: nil }).distinct
      SegmentSnapper.new(road_lookup: @road_lookup).snap_all(unsnapped).size
    end

    def status_for(ok:, failed:)
      return "failed" if ok.zero?
      return "success" if failed.zero?

      "partial"
    end

    def build_result(state, retired:, snapped:)
      ok = state["ok"].size
      failed = state["failed"]
      status = status_for(ok: ok, failed: failed)

      outcome = {
        "status" => status, "added" => state["added"], "updated" => state["updated"],
        "skipped" => state["skipped"], "retired" => retired,
        "tiles_ok" => ok, "tiles_failed" => failed
      }
      outcome["error_class"] = state["error_class"] if state["error_class"]

      Result.new(
        per_source: { @source_name => outcome },
        totals: { "added" => state["added"], "updated" => state["updated"], "skipped" => state["skipped"], "retired" => retired },
        snapped_total: snapped,
        status: status
      )
    end
  end
end
