require "rails_helper"

# Seeding provisions the configured country's DEV camera data-region (default US)
# from the country registry — not a hardcoded launch state (FR-002). The map's
# framing extent is registry-derived (CoverageController#bounds), so it is NOT
# seeded here; only the data-region row is.
RSpec.describe "db/seeds.rb", type: :model do
  # seeds.rb resolves the country via ENV["GEOCODER_COUNTRY"] (which compose
  # interpolates from the developer's infra/.env). Pin it so the seeded region is
  # deterministic regardless of the local deployment scope — like every sibling
  # country-resolving spec.
  around do |example|
    keys = %w[GEOCODER_COUNTRY GEOCODER_REGION_STATE GEOCODER_VIEWBOX]
    orig = ENV.to_hash.slice(*keys)
    ENV["GEOCODER_COUNTRY"] = "us"
    ENV.delete("GEOCODER_REGION_STATE")
    ENV.delete("GEOCODER_VIEWBOX")
    example.run
  ensure
    keys.each { |k| orig.key?(k) ? ENV[k] = orig[k] : ENV.delete(k) }
  end

  def load_seeds
    silence_stream($stdout) { Rails.application.load_seed }
  rescue NoMethodError
    # silence_stream was removed from newer Rails; fall back to a manual capture.
    original = $stdout
    $stdout = StringIO.new
    Rails.application.load_seed
  ensure
    $stdout = original if original
  end

  it "creates the configured country's data-region from the registry (default US)" do
    expect { load_seeds }.to change(CoverageArea, :count).by(1)

    country = Geocoding::CountryRegistry.resolve
    area = CoverageArea.find_by(name: country.name)
    expect(area).to be_present
    expect(area.data_freshness_at).to be_present
  end

  it "covers a point inside the configured country" do
    load_seeds
    # Denver is inside the US bbox — the seeded data-region should contain it.
    expect(CoverageArea.covers?(-104.99, 39.74)).to be(true)
  end

  it "is idempotent (re-running seeds does not duplicate the region)" do
    load_seeds
    expect { load_seeds }.not_to change(CoverageArea, :count)
  end
end
