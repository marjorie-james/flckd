# Per-refresh audit record (feature 003, FR-013/FR-014). Records what each
# scheduled or manual refresh did, per source, for observability and to guard
# against overlapping runs. Contains NO user data — only reference-data counts,
# source names, and an error class string.
class CreateRefreshRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :refresh_runs do |t|
      t.string :trigger, null: false                       # scheduled | manual
      t.string :status, null: false, default: "running"    # running | success | partial | failed
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :duration_ms
      t.jsonb :per_source, null: false, default: {}
      t.jsonb :totals, null: false, default: {}

      t.timestamps
    end

    add_index :refresh_runs, :status
    add_index :refresh_runs, :started_at
  end
end
