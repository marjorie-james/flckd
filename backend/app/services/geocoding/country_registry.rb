module Geocoding
  # Static reference data resolving the one country a deployment covers to
  # everything provisioning + geocoding need: the whole-country OSM extract URL,
  # the framing/viewbox bbox, whether the US Census TIGER house-number import
  # applies, and the label for internal admin divisions.
  #
  # Selected by GEOCODER_COUNTRY (backend) / COUNTRY in infra/.region (scripts),
  # defaulting to `us` (FR-002). The structure is country-generic, but US is the
  # only fully populated and validated entry at launch — an unknown or
  # un-provisioned code fails fast with an actionable error (FR-009), never
  # silently substituted. Adding a country = adding a record here AND provisioning
  # its data.
  module CountryRegistry
    # Raised for a code not present (or not fully provisioned) in the registry.
    # The message names the supported codes so the operator can correct config.
    class UnknownCountryError < StandardError; end

    DEFAULT_CODE = "us".freeze

    # One configured country. `bbox` is [west, south, east, north]; the derived
    # views (#viewbox for Nominatim, #bounds for the map) keep that single source
    # of truth so framing and bounded search never drift.
    Country = Struct.new(:code, :name, :extract_url, :bbox, :tiger, :sub_region_kind, keyword_init: true) do
      # Nominatim's viewbox is "min_lng,max_lat,max_lng,min_lat" (left,top,right,
      # bottom) — note the lat order is inverted relative to bbox.
      def viewbox
        west, south, east, north = bbox
        [ west, north, east, south ].join(",")
      end

      # Map-framing extent as [[west, south], [east, north]] (lng/lat corners) —
      # the shape /coverage/bounds returns.
      def bounds
        west, south, east, north = bbox
        [ [ west, south ], [ east, north ] ]
      end
    end

    # Only `us` is populated and validated at launch (launch invariant). The
    # bbox spans the continental US; the extract is Geofabrik's whole-US PBF.
    REGISTRY = {
      "us" => Country.new(
        code: "us",
        name: "United States",
        extract_url: "https://download.geofabrik.de/north-america/us-latest.osm.pbf",
        bbox: [ -125.0, 24.5, -66.9, 49.5 ],
        tiger: true,
        sub_region_kind: "state"
      )
    }.freeze

    module_function

    # Resolve the configured country. Defaults to `us` when unset/blank (FR-002);
    # raises UnknownCountryError for an unknown / un-provisioned code (FR-009).
    def resolve(code = ENV["GEOCODER_COUNTRY"])
      key = code.to_s.strip.downcase
      key = DEFAULT_CODE if key.empty?

      REGISTRY.fetch(key) do
        raise UnknownCountryError,
              "Unknown or un-provisioned country '#{code}'. Only #{supported_codes.join(', ')} " \
              "is supported at launch. Set GEOCODER_COUNTRY (or COUNTRY in infra/.region) to a " \
              "supported, provisioned country."
      end
    end

    def supported_codes
      REGISTRY.keys
    end

    # The single place that decides "is this a single-state DEV deployment?" (the
    # legacy single-region path) vs a whole country — so GeocoderClient.build and
    # MapFraming.bounds can never select different modes. Keyed on the presence of
    # GEOCODER_REGION_STATE (set only by setup.sh's single-state path).
    def single_state?
      ENV["GEOCODER_REGION_STATE"].present?
    end
  end
end
