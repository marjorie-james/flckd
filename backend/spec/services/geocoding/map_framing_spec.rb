require "rails_helper"

# The initial map-framing extent reflects the deployment's configured SCOPE
# (FR-007): a whole-country deployment frames the entire country; a single-state
# DEV deployment frames that state.
RSpec.describe Geocoding::MapFraming do
  def with_env(vars)
    keys = vars.keys.map(&:to_s)
    orig = ENV.to_hash.slice(*keys)
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    yield
  ensure
    keys.each { |k| orig.key?(k) ? ENV[k] = orig[k] : ENV.delete(k) }
  end

  describe ".bounds" do
    it "frames the entire country (registry bbox) for a whole-country deployment" do
      with_env("GEOCODER_REGION_STATE" => nil, "GEOCODER_COUNTRY" => "us") do
        expect(described_class.bounds).to eq([ [ -125.0, 24.5 ], [ -66.9, 49.5 ] ])
      end
    end

    it "frames the configured state (viewbox bbox) for a single-state dev deployment" do
      # Nominatim viewbox is min_lng,max_lat,max_lng,min_lat — Iowa's extent.
      with_env("GEOCODER_REGION_STATE" => "Iowa", "GEOCODER_VIEWBOX" => "-96.7,43.6,-90.0,40.3") do
        expect(described_class.bounds).to eq([ [ -96.7, 40.3 ], [ -90.0, 43.6 ] ])
      end
    end

    it "falls back to the country extent when a single-state viewbox is missing" do
      with_env("GEOCODER_REGION_STATE" => "Iowa", "GEOCODER_VIEWBOX" => nil, "GEOCODER_COUNTRY" => "us") do
        expect(described_class.bounds).to eq([ [ -125.0, 24.5 ], [ -66.9, 49.5 ] ])
      end
    end

    it "falls back to the country extent when the viewbox is non-numeric (ArgumentError branch)" do
      with_env("GEOCODER_REGION_STATE" => "Iowa", "GEOCODER_VIEWBOX" => "not,a,viewbox") do
        expect(described_class.bounds).to eq([ [ -125.0, 24.5 ], [ -66.9, 49.5 ] ])
      end
    end

    it "falls back to the country extent when the viewbox has too few components (nil-arity guard)" do
      # Numeric but only 3 of 4 components → south is nil; distinct from the
      # non-numeric ArgumentError path above.
      with_env("GEOCODER_REGION_STATE" => "Iowa", "GEOCODER_VIEWBOX" => "-96.7,43.6,-90.0") do
        expect(described_class.bounds).to eq([ [ -125.0, 24.5 ], [ -66.9, 49.5 ] ])
      end
    end

    it "falls back to the country extent when the viewbox has too many components" do
      # A typo'd 5-component viewbox must be rejected, not silently truncated to
      # the first four (which would mis-frame the map).
      with_env("GEOCODER_REGION_STATE" => "Iowa", "GEOCODER_VIEWBOX" => "-96.7,43.6,-90.0,40.3,0.0") do
        expect(described_class.bounds).to eq([ [ -125.0, 24.5 ], [ -66.9, 49.5 ] ])
      end
    end
  end
end
