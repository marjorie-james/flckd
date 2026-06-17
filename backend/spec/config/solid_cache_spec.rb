require "rails_helper"

# Solid Cache is the production Rails.cache backend (and therefore the Rack::Attack
# throttle-counter store). Booting the production environment in a test is fragile,
# so we assert the WIRING structurally: the cache config points at the dedicated
# `cache` database, the cache migration creates the entries table, and production.rb
# selects :solid_cache_store. A regression in any of these silently drops the
# durable, cross-container throttle store we depend on.
RSpec.describe "Solid Cache wiring" do
  it "configures the production cache to use the dedicated `cache` database" do
    # aliases: true so the `<<: *default` merge keys parse without raising.
    config = YAML.load_file(Rails.root.join("config/cache.yml"), aliases: true)
    expect(config.dig("production", "database")).to eq("cache")
  end

  it "ships a cache migration that creates the solid_cache_entries table" do
    sources = Dir[Rails.root.join("db/cache_migrate/*.rb")].map { |f| File.read(f) }
    expect(sources).not_to be_empty
    expect(sources).to include(a_string_matching(/create_table\s+["']solid_cache_entries["']/))
  end

  it "selects :solid_cache_store as the production cache store" do
    production_env = File.read(Rails.root.join("config/environments/production.rb"))
    expect(production_env).to include("config.cache_store = :solid_cache_store")
  end
end
