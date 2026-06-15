# Known ALPR/Flock cameras. Reference data only — never user data.
class CreateCameras < ActiveRecord::Migration[8.1]
  def change
    create_table :cameras do |t|
      t.references :data_source, null: false, foreign_key: true
      t.string :external_ref
      t.st_point :location, geographic: false, srid: 4326, null: false
      t.integer :facing_direction # degrees 0-359, if known
      t.string :camera_type
      t.float :confidence, null: false, default: 0.5
      t.string :verification_status, null: false, default: "unverified"
      t.datetime :first_seen_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :last_verified_at

      t.timestamps
    end

    add_index :cameras, :location, using: :gist
    add_index :cameras, :verification_status
    add_index :cameras, %i[data_source_id external_ref], unique: true,
                                                          where: "external_ref IS NOT NULL"
  end
end
