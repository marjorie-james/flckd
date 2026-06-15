class AddAutoRetiredToCameras < ActiveRecord::Migration[8.1]
  # Distinguishes auto-retirement (a camera the source stopped reporting for
  # `missing_limit` refreshes) from human removal (`remove!`). Previously both set
  # verification_status="removed", which is terminal for reconciliation — so a
  # transiently-absent camera that reappeared could never recover and silently
  # dropped out of avoidance forever. Auto-retirement now uses this flag, which the
  # reconciler clears the moment the source reports the camera again.
  def up
    add_column :cameras, :auto_retired, :boolean, default: false, null: false
    add_index :cameras, :auto_retired, where: "auto_retired", name: "index_cameras_auto_retired"

    # Backfill: revive cameras that were almost certainly AUTO-retired (they went
    # through the missing path: consecutive_missing_count >= the default limit) into
    # the recoverable lifecycle. Human removals (remove!) never increment the miss
    # counter, so they stay removed. Verified cameras are exempt from auto-retire.
    execute(<<~SQL)
      UPDATE cameras
      SET auto_retired = true, verification_status = 'unverified'
      WHERE verification_status = 'removed'
        AND consecutive_missing_count >= 3
    SQL
  end

  def down
    remove_column :cameras, :auto_retired
  end
end
