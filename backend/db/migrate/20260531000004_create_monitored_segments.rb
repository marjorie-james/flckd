# The road segment(s) a camera monitors — the unit of avoidance.
# Camera is snapped to its nearest road; osm_way_id matches the routing graph.
class CreateMonitoredSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :monitored_segments do |t|
      t.references :camera, null: false, foreign_key: true
      t.bigint :osm_way_id, null: false
      t.line_string :geometry, geographic: false, srid: 4326, null: false
      t.string :direction, null: false, default: "both" # both | forward | backward
      t.float :snap_distance_m, null: false, default: 0.0

      t.timestamps
    end

    add_index :monitored_segments, :geometry, using: :gist
    add_index :monitored_segments, :osm_way_id
  end
end
