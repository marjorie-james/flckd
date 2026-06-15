module CameraData
  # Reconciles one source's cameras against a refresh, after that source's import
  # has succeeded (FR-008/FR-009). Cameras the source reported this run (their
  # last_seen_in_source_at is at/after the run cutoff) are marked fresh; cameras
  # it no longer reports are flagged stale and, after `missing_limit` consecutive
  # misses, auto-retired — except human-verified cameras, which are exempt.
  #
  # Run ONLY for sources whose fetch succeeded, so a failed source never retires
  # its own cameras (last-good preserved, FR-012).
  class StaleReconciler
    Result = Struct.new(:retired, keyword_init: true)

    def initialize(missing_limit: CameraData.missing_limit)
      @missing_limit = missing_limit
    end

    # `bboxes:` (optional) scopes reconciliation to cameras located within the
    # given tile bounding boxes — the cells that were *successfully* fetched this
    # run. Cameras in a tile whose fetch FAILED are left untouched: we didn't see
    # the tile, so we can't tell its cameras are missing, and reconciling them
    # would wrongly auto-retire real cameras after repeated tile failures
    # (FR-008/009). nil = reconcile all of the source's cameras (single-bbox /
    # whole-source imports).
    def reconcile(data_source:, cutoff:, bboxes: nil)
      retired = 0
      # One transaction for the whole source rather than a commit per camera.
      ActiveRecord::Base.transaction do
        # Includes auto-retired cameras (only human-`removed` are excluded) so the
        # `seen_in_source!` branch can REVIVE one the source reports again.
        scope = data_source.cameras.where.not(verification_status: "removed")
        scope = scope.where(within_any_bbox(bboxes)) unless bboxes.nil?
        scope.find_each do |camera|
          if camera.last_seen_in_source_at && camera.last_seen_in_source_at >= cutoff
            camera.seen_in_source!
          elsif camera.auto_retired?
            next # already retired and still missing — nothing to do (leave recoverable)
          else
            camera.mark_missing!(limit: @missing_limit)
            retired += 1 if camera.auto_retired? # newly retired this run
          end
        end
      end
      Result.new(retired: retired)
    end

    # Marks all of a source's non-removed cameras as seen now, except the given refs
    # — so a delta run's unchanged cameras don't look "missing" to #reconcile. One
    # UPDATE rather than one per camera. (Shared by both refresh orchestrators; the
    # auto-retired flag is intentionally NOT cleared here — only a camera the source
    # actually reports this run is revived, which #reconcile handles.)
    def touch_seen(data_source:, except_refs: [])
      return unless data_source

      scope = data_source.cameras.where.not(verification_status: "removed")
      scope = scope.where.not(external_ref: except_refs) if except_refs.any?
      scope.update_all(last_seen_in_source_at: Time.current)
    end

    private

    # SQL predicate: camera location falls in ANY of the bboxes. Uses the GiST
    # bbox-overlap operator (&&) so it stays index-friendly; for a point, overlap
    # with an envelope means the point is inside it. Coords are forced numeric, so
    # interpolation is injection-safe. Empty set → match nothing.
    def within_any_bbox(bboxes)
      return "1=0" if bboxes.empty?

      bboxes.map do |b|
        "location && ST_MakeEnvelope(#{b[:west].to_f}, #{b[:south].to_f}, " \
          "#{b[:east].to_f}, #{b[:north].to_f}, 4326)"
      end.join(" OR ")
    end
  end
end
