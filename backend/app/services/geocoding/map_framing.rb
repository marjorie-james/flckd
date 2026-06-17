module Geocoding
  # The initial map-framing extent for the deployment's configured SCOPE (FR-007).
  # Mirrors GeocoderClient.build's mode decision so framing always matches what is
  # actually loaded:
  #
  #   * Whole-country deployment (default) → the country registry bbox — the
  #     entire country (e.g. continental US), however sparse the camera footprint.
  #   * Single-state DEV deployment (GEOCODER_REGION_STATE set) → that state's
  #     extent, taken from the configured geocoder viewbox (which IS the state's
  #     bbox). Falls back to the country bbox if the viewbox is unset/malformed.
  #
  # Returns [[west, south], [east, north]] (lng/lat corners) — the shape
  # /coverage/bounds serves to the client.
  module MapFraming
    module_function

    def bounds
      # CountryRegistry.single_state? is the shared mode decision (same one
      # GeocoderClient.build uses), so framing and geocoding never disagree.
      if CountryRegistry.single_state? && (viewbox = ENV["GEOCODER_VIEWBOX"].presence)
        viewbox_bounds(viewbox) || CountryRegistry.resolve.bounds
      else
        CountryRegistry.resolve.bounds
      end
    end

    # Nominatim viewbox is "min_lng,max_lat,max_lng,min_lat" (left,top,right,
    # bottom); convert to our [[west, south], [east, north]] framing corners.
    # Returns nil for a malformed viewbox so the caller falls back.
    def viewbox_bounds(viewbox)
      parts = viewbox.split(",")
      # Require EXACTLY four components: too few left a nil corner (caught below),
      # but too many silently used the first four — a typo'd 5-component viewbox
      # would mis-frame the map. Reject anything but four and fall back.
      return nil unless parts.length == 4

      west, north, east, south = parts.map { |v| Float(v) }
      [ [ west, south ], [ east, north ] ]
    rescue ArgumentError
      nil
    end
  end
end
