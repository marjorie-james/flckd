module CameraData
  # The shape returned by both camera-refresh engines (AggregateImport, which runs
  # several sources in one pass, and TiledRefresh, which runs one tiled source with
  # checkpointing). Kept in one place so the two engines can't drift on the
  # contract their callers (rake tasks, DataRefreshJob, RefreshStatus) depend on.
  #
  #   per_source    => { "<source name>" => outcome_hash }
  #   totals        => aggregate added/updated/skipped/retired counts
  #   snapped_total => cameras snapped to monitored segments this run
  #   status        => "success" | "partial" | "failed"
  RefreshResult = Struct.new(:per_source, :totals, :snapped_total, :status, keyword_init: true)
end
