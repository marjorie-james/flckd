# Freshness/stale lifecycle tracking for cameras (feature 003). Lets the refresh
# pipeline keep avoiding a camera that vanished upstream while flagging it stale,
# and auto-retire it after N consecutive missing refreshes (FR-008/FR-009).
class AddFreshnessToCameras < ActiveRecord::Migration[8.1]
  def change
    add_column :cameras, :last_seen_in_source_at, :datetime
    add_column :cameras, :consecutive_missing_count, :integer, null: false, default: 0
    add_column :cameras, :stale, :boolean, null: false, default: false

    add_index :cameras, :stale, where: "stale", name: "index_cameras_on_stale_true"
  end
end
