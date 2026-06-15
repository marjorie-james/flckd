module CameraData
  # Presents recent RefreshRun records for `rake camera_data:refresh:status`
  # (FR-013). Two renderings stay in sync: a human-readable table and a
  # structured JSON form matching contracts/refresh-run.schema.json. Reference
  # data only — no user data is ever included.
  class RefreshStatus
    # One source of truth for the per-source summary line shared by the status
    # table (#run_lines) and the rake import/refresh tasks. `counts` selects which
    # success counters to render — the import path tracks `skipped`, the refresh
    # path tracks `retired` — so the three former copies can no longer drift.
    def self.format_source(name, outcome, counts: %w[added updated retired])
      detail =
        if outcome["status"] == "success"
          counts.map { |k| "#{k}=#{outcome[k]}" }.join(" ")
        else
          outcome["status"]
        end
      err = outcome["error_class"] ? " [#{outcome['error_class']}]" : ""
      "  #{name.ljust(28)} #{detail}#{err}"
    end

    def initialize(limit: 5)
      @limit = limit
    end

    def runs
      RefreshRun.recent.limit(@limit)
    end

    def as_json(*)
      runs.map { |r| serialize(r) }
    end

    def to_text
      return "No refresh runs recorded yet." if runs.empty?

      runs.map { |r| run_lines(r) }.join("\n\n")
    end

    private

    def serialize(run)
      {
        "id" => run.id,
        "trigger" => run.trigger,
        "status" => run.status,
        "started_at" => run.started_at&.utc&.iso8601,
        "finished_at" => run.finished_at&.utc&.iso8601,
        "duration_ms" => run.duration_ms,
        "totals" => run.totals,
        "per_source" => run.per_source
      }
    end

    def run_lines(run)
      header = "#{run.started_at&.utc&.iso8601}  #{run.trigger}  [#{run.status}]  #{run.duration_ms}ms"
      sources = run.per_source.map { |name, o| self.class.format_source(name, o) }
      ([ header ] + sources).join("\n")
    end
  end
end
