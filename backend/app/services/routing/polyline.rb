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
