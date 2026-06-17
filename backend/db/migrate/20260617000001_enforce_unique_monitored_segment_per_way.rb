# A camera monitors a given OSM way at most once. The snapper is idempotent per
# (camera, osm_way_id), but that guard is read-then-write — two concurrent snap
# passes (e.g. a backfill accidentally run across both the web and job roles at
# once) could each insert the same pair. This enforces the invariant in the DB so
# it can't recur, after clearing any duplicates a pre-index run already created.
class EnforceUniqueMonitoredSegmentPerWay < ActiveRecord::Migration[8.1]
  def up
    # Keep the earliest row of each duplicated (camera_id, osm_way_id) pair.
    execute <<~SQL
      DELETE FROM monitored_segments a
      USING monitored_segments b
      WHERE a.camera_id = b.camera_id
        AND a.osm_way_id = b.osm_way_id
        AND a.id > b.id
    SQL

    add_index :monitored_segments, [ :camera_id, :osm_way_id ],
              unique: true, name: "index_monitored_segments_on_camera_and_way"
  end

  def down
    remove_index :monitored_segments, name: "index_monitored_segments_on_camera_and_way"
  end
end
