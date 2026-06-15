# Regions where camera data exists / avoidance is meaningful.
class CreateCoverageAreas < ActiveRecord::Migration[8.1]
  def change
    create_table :coverage_areas do |t|
      t.string :name, null: false
      t.multi_polygon :region, geographic: false, srid: 4326, null: false
      t.datetime :data_freshness_at

      t.timestamps
    end

    add_index :coverage_areas, :region, using: :gist
  end
end
