class RemoveDeflockSource < ActiveRecord::Migration[8.1]
  # DeFlock was fetched as a separate source, but it ingested the *identical* OSM
  # substrate as "OpenStreetMap (Overpass)" (same Overpass query, same endpoint),
  # so every physical camera was stored twice. We no longer fetch it separately
  # (ADR 0001); drop its now-unrefreshed rows. The same cameras remain under the
  # OpenStreetMap source, so there is no coverage loss. Raw SQL keeps this
  # independent of model code; monitored_segments has no ON DELETE CASCADE, so
  # remove them first.
  def up
    ds_id = select_value("SELECT id FROM data_sources WHERE name = 'DeFlock'")
    return if ds_id.nil?

    execute(<<~SQL.squish)
      DELETE FROM monitored_segments
      WHERE camera_id IN (SELECT id FROM cameras WHERE data_source_id = #{ds_id.to_i})
    SQL
    execute("DELETE FROM cameras WHERE data_source_id = #{ds_id.to_i}")
    execute("DELETE FROM data_sources WHERE id = #{ds_id.to_i}")
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
