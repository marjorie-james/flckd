module CameraData
  # Runs a set of camera-data sources into the single `cameras` table, which is
  # our source of truth. Each source is imported under its own provenance
  # (DataSource + license); idempotency is per (data_source, external_ref).
  #
  # Cross-source duplicates of the same physical camera are intentionally NOT
  # merged at the camera level: each remains an attributable observation, and
  # they collapse where it matters for routing — at the segment layer, since
  # cameras on the same OSM way snap to the same MonitoredSegment (one avoidance
  # target per OSM way).
  #
  # Per-source failures are isolated: a source that raises is recorded as
  # `failed` and the run continues with the others, preserving the failed
  # source's last-good data (FR-012). A source with no license is skipped
  # entirely (FR-005). After importing, newly added cameras are snapped to their
  # monitored road segments (best-effort; a no-op if no road lookup is given).
  class AggregateImport
    Result = RefreshResult # shared shape (see CameraData::RefreshResult)

    COUNT_KEYS = %w[added updated skipped retired].freeze

    def initialize(sources:, road_lookup: nil)
      @sources = Array(sources)
      @road_lookup = road_lookup
    end

    def call
      per_source = {}
      imported_refs = []

      @sources.each do |source|
        per_source[source.source_name] = import_source(source, imported_refs)
      end

      Result.new(
        per_source: per_source,
        totals: totals(per_source),
        snapped_total: snap(imported_refs),
        status: overall_status(per_source)
      )
    end

    private

    def import_source(source, imported_refs)
      if source.license.blank?
        Rails.logger.warn("[camera_data] skipping source '#{source.source_name}' — no license recorded (FR-005)")
        return outcome(status: "skipped_no_license")
      end

      # Cutoff captured before import: cameras imported now get a later
      # last_seen_in_source_at, so the reconciler can tell seen from missing.
      cutoff = Time.current
      ds = DataSource.find_by(name: source.source_name)
      since = ds&.last_imported_at

      if source.supports_delta?(since: since)
        import_with_delta(source, imported_refs, cutoff, since, ds)
      else
        import_full(source, imported_refs, cutoff, ds)
      end
    rescue StandardError => e
      # Isolate the failure: record the error class only (no user data — there is
      # none in this pipeline) and continue with the other sources. A failed
      # source is NOT reconciled, so its cameras keep their last-good state.
      Rails.logger.warn("[camera_data] source '#{source.source_name}' failed: #{e.class}")
      outcome(status: "failed", error_class: e.class.name)
    end

    def import_full(source, imported_refs, cutoff, data_source)
      records = source.fetch
      stats = Importer.for_source(source).import(records)
      imported_refs.concat(records.filter_map { |r| r[:external_ref] })
      retired = reconcile(data_source, cutoff)
      outcome(status: "success", added: stats.added, updated: stats.updated, skipped: stats.skipped, retired: retired)
    end

    def import_with_delta(source, imported_refs, cutoff, since, data_source)
      delta = source.fetch_delta(since: since)
      stats = Importer.for_source(source).import(delta[:upserted])
      imported_refs.concat(delta[:upserted].filter_map { |r| r[:external_ref] })
      # Bulk-touch unchanged cameras so the reconciler doesn't flag them as missing.
      # Deleted refs are intentionally excluded — their old timestamp stays below
      # the cutoff so the reconciler marks them missing and eventually retires them.
      StaleReconciler.new.touch_seen(data_source: data_source, except_refs: delta[:deleted_refs])
      retired = reconcile(data_source, cutoff)
      outcome(status: "success", added: stats.added, updated: stats.updated, skipped: stats.skipped, retired: retired)
    end

    # Flag stale / auto-retire this source's cameras that were not reported this
    # run. Only reached on a successful import (FR-012). Returns retired count.
    def reconcile(data_source, cutoff)
      return 0 unless data_source

      StaleReconciler.new.reconcile(data_source: data_source, cutoff: cutoff).retired
    end

    def outcome(status:, added: 0, updated: 0, skipped: 0, retired: 0, error_class: nil)
      o = { "status" => status, "added" => added, "updated" => updated, "skipped" => skipped, "retired" => retired }
      o["error_class"] = error_class if error_class
      o
    end

    def totals(per_source)
      COUNT_KEYS.index_with { |k| per_source.values.sum { |o| o[k].to_i } }
    end

    def overall_status(per_source)
      statuses = per_source.values.map { |o| o["status"] }
      return "success" if statuses.all?("success")
      return "failed" if statuses.none?("success")

      "partial"
    end

    # Snap only cameras that have no monitored segment yet, so re-imports don't
    # re-snap. Best-effort: skip entirely when no road lookup is configured.
    def snap(refs)
      return 0 if @road_lookup.nil? || refs.empty?

      unsnapped = Camera.where(external_ref: refs)
                        .left_joins(:monitored_segments)
                        .where(monitored_segments: { id: nil })
                        .distinct
      SegmentSnapper.new(road_lookup: @road_lookup).snap_all(unsnapped).size
    end
  end
end
