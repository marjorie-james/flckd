class RequireCameraExternalRef < ActiveRecord::Migration[8.1]
  # external_ref was nullable, which forced a *partial* unique index
  # (WHERE external_ref IS NOT NULL) and let blank-ref imports create anonymous
  # duplicate rows. Every real source supplies an external_ref; make it required
  # and swap the partial index for a plain unique one (ADR 0001).
  INDEX = "index_cameras_on_data_source_id_and_external_ref".freeze

  def up
    # Backfill any legacy NULLs (none expected from real sources — only possible
    # from old blank-ref imports) with a stable synthetic ref before NOT NULL.
    execute("UPDATE cameras SET external_ref = 'legacy:' || id WHERE external_ref IS NULL")
    change_column_null :cameras, :external_ref, false

    remove_index :cameras, name: INDEX
    add_index :cameras, %i[data_source_id external_ref], unique: true, name: INDEX
  end

  def down
    remove_index :cameras, name: INDEX
    add_index :cameras, %i[data_source_id external_ref], unique: true,
              where: "external_ref IS NOT NULL", name: INDEX
    change_column_null :cameras, :external_ref, true
  end
end
