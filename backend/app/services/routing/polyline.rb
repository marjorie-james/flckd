module Routing
  # Decoder for Valhalla's encoded polyline shape. Valhalla uses precision 1e6
  # (a.k.a. "polyline6"). Returns an array of [lng, lat] pairs (GeoJSON order)
  # so callers can build EWKT/GeoJSON directly.
  #
  # Used to turn a routing edge's shape (camera snapping) and a route's geometry
  # (checking which monitored segments a route still passes) into real geometry.
  module Polyline
    PRECISION = 1_000_000.0 # Valhalla polyline6

    module_function

    # Returns [[lng, lat], ...]. Returns [] for blank input. Raises nothing on
    # truncated input — it stops at the last complete coordinate pair.
    def decode(encoded, precision: PRECISION)
      return [] if encoded.nil? || encoded.empty?

      bytes = encoded.bytes
      size = bytes.size
      coords = []
      index = 0
      lat = 0
      lng = 0

      while index < size
        dlat, index = next_value(bytes, index, size)
        break if index.nil?

        dlng, index = next_value(bytes, index, size)
        break if index.nil?

        lat += dlat
        lng += dlng
        coords << [ lng / precision, lat / precision ]
      end

      coords
    end

    # Builds a LineString EWKT (SRID 4326) from an encoded shape, or nil if the
    # shape doesn't yield at least two points.
    def to_linestring_ewkt(encoded, precision: PRECISION)
      coords = decode(encoded, precision: precision)
      return nil if coords.size < 2

      "SRID=4326;LINESTRING(#{coords.map { |lng, lat| "#{lng} #{lat}" }.join(', ')})"
    end

    # Initial compass bearing in degrees (0..360) from the first decoded point to
    # the last, or nil when the shape yields fewer than two points. Used when
    # snapping a camera to tell a road's opposing/parallel carriageway (roughly the
    # same axis) from a perpendicular cross street, so a camera only ever monitors
    # the road it actually watches in both travel directions — not the streets that
    # merely cross near it.
    def bearing(encoded, precision: PRECISION)
      coords = decode(encoded, precision: precision)
      return nil if coords.size < 2

      rad = Math::PI / 180.0
      lng1, lat1 = coords.first
      lng2, lat2 = coords.last
      phi1 = lat1 * rad
      phi2 = lat2 * rad
      dlng = (lng2 - lng1) * rad
      y = Math.sin(dlng) * Math.cos(phi2)
      x = Math.cos(phi1) * Math.sin(phi2) - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dlng)
      (Math.atan2(y, x) / rad) % 360
    end

    # Like #to_linestring_ewkt but never raises: nil for blank or undecodable input.
    # The hot-path scorers (proximity + camera detection) both turn a route's
    # geometry into a line this way, so it lives here as the single source of truth.
    def safe_linestring_ewkt(encoded)
      return nil if encoded.blank?

      to_linestring_ewkt(encoded)
    rescue StandardError
      nil
    end

    # Reads one zig-zag varint starting at `index`. Returns [value, next_index],
    # or [nil, nil] if the input is truncated mid-value.
    def next_value(bytes, index, size)
      shift = 0
      result = 0
      loop do
        return [ nil, nil ] if index >= size

        byte = bytes[index] - 63
        index += 1
        result |= (byte & 0x1f) << shift
        shift += 5
        break if byte < 0x20
      end
      value = result.odd? ? ~(result >> 1) : (result >> 1)
      [ value, index ]
    end
    private_class_method :next_value
  end
end
