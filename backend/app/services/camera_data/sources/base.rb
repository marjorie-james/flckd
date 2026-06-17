module CameraData
  module Sources
    # Base class for camera-data sources. A source knows how to fetch raw camera
    # observations from one provider (OSM via Overpass, a municipal open-data
    # export, a community dataset, ...) and normalize them into the record shape
    # CameraData::Importer expects:
    #
    #   { external_ref:, lat:, lng:, facing_direction:, camera_type:, confidence: }
    #
    # It also declares its own provenance (name/kind/url/license) so every
    # imported camera is attributable to a licensed origin. The aggregate
    # `cameras` table is our source of truth; each row carries the source it came
    # from. We only ever query for the *coverage region*, never a user location.
    class Base
      # Subclasses set these via `source` (or override the readers).
      class << self
        attr_reader :source_name, :source_kind, :source_url, :license

        # Declares provenance for every record this source produces.
        def source(name:, kind: "community", url: nil, license: nil)
          @source_name = name
          @source_kind = kind
          @source_url = url
          @license = license
        end
      end

      def source_name = self.class.source_name
      def source_kind = self.class.source_kind
      def source_url  = self.class.source_url
      def license     = self.class.license

      # Returns an array of normalized record hashes. Implemented by subclasses.
      def fetch
        raise NotImplementedError, "#{self.class} must implement #fetch"
      end

      # True when this source can supply a delta since `since` (i.e. only records
      # that changed). Overpass overrides this; all other sources return false and
      # always do a full fetch via #fetch.
      def supports_delta?(since:) = false

      # Returns { upserted: [...], deleted_refs: [...] } for records changed since
      # `since`. Only called when supports_delta? returns true; Overpass overrides.
      def fetch_delta(since:)
        raise NotImplementedError, "#{self.class} must implement #fetch_delta when supports_delta? is true"
      end

      private

      # --- Shared tag/value normalization ---------------------------------

      # Maps free-form brand/operator/type hints to a coarse camera_type.
      # Flock is called out because it is the dominant ALPR vendor we avoid.
      def normalize_camera_type(brand: nil, type: nil)
        haystack = [ brand, type ].compact.join(" ").downcase
        return "Flock" if haystack.include?("flock")
        return "ALPR" if haystack.include?("alpr") || haystack.include?("anpr")

        type.presence || "ALPR"
      end

      # Normalizes a compass bearing into 0..359, or nil when unknown/invalid.
      # Accepts numeric degrees or cardinal strings (N, NE, ...).
      def normalize_direction(value)
        return nil if value.nil?

        if value.is_a?(String) && (deg = CARDINALS[value.strip.upcase])
          return deg
        end

        # Float first so fractional bearings ROUND (359.9 -> 360 -> 0) rather than
        # being truncated by Integer() short-circuiting the ||. String "90" still
        # parses via Float and rounds to 90; nil/invalid fall through to nil.
        deg = (Float(value, exception: false) || Integer(value, exception: false))&.round
        return nil if deg.nil?

        deg % 360
      end

      CARDINALS = {
        "N" => 0, "NE" => 45, "E" => 90, "SE" => 135,
        "S" => 180, "SW" => 225, "W" => 270, "NW" => 315
      }.freeze
    end
  end
end
