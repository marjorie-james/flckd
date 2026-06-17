# Solid Cache schema (from solid_cache 1.0.10's install template, cache_schema.rb)
# created in the DEDICATED `cache` database. This migration lives in db/cache_migrate
# and only runs against the `cache` connection (database.yml production -> the
# flckd_production_cache database). It does NOT run in dev/test, which have no `cache`
# sub-database — those environments fall back to the primary connection for Rails.cache.
class CreateSolidCacheEntries < ActiveRecord::Migration[8.1]
  def change
    create_table "solid_cache_entries", force: :cascade do |t|
      t.binary "key", limit: 1024, null: false
      t.binary "value", limit: 536870912, null: false
      t.datetime "created_at", null: false
      t.integer "key_hash", limit: 8, null: false
      t.integer "byte_size", limit: 4, null: false
      t.index [ "byte_size" ], name: "index_solid_cache_entries_on_byte_size"
      t.index [ "key_hash", "byte_size" ], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
      t.index [ "key_hash" ], name: "index_solid_cache_entries_on_key_hash", unique: true
    end
  end
end
