# Provenance for camera records (hybrid pipeline: community + internal).
class CreateDataSources < ActiveRecord::Migration[8.1]
  def change
    create_table :data_sources do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "community" # community | internal
      t.string :url
      t.string :license
      t.datetime :last_imported_at

      t.timestamps
    end

    add_index :data_sources, :name, unique: true
  end
end
