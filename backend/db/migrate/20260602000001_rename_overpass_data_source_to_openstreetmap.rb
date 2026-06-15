# ADR 0002: the OSM ALPR substrate is now mechanism-neutral — the same
# OpenStreetMap origin is reached either via the live Overpass API or the local
# PBF extract. Provenance names the DATA ORIGIN, not the access mechanism, so the
# `DataSource` is renamed "OpenStreetMap (Overpass)" → "OpenStreetMap". This lets
# both mechanisms share one identity (and stable osm:node/<id> external_refs), so
# flipping CAMERA_OSM_SOURCE never forks a camera onto a second data source.
#
# Raw SQL (no model dependency) and guarded so it's idempotent and a no-op where
# the row doesn't exist (e.g. a fresh DB that has never run a refresh).
class RenameOverpassDataSourceToOpenstreetmap < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE data_sources SET name = 'OpenStreetMap'
      WHERE name = 'OpenStreetMap (Overpass)'
        AND NOT EXISTS (SELECT 1 FROM data_sources WHERE name = 'OpenStreetMap')
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE data_sources SET name = 'OpenStreetMap (Overpass)'
      WHERE name = 'OpenStreetMap'
        AND NOT EXISTS (SELECT 1 FROM data_sources WHERE name = 'OpenStreetMap (Overpass)')
    SQL
  end
end
