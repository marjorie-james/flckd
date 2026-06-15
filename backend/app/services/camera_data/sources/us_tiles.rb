module CameraData
  module Sources
    # Splits the continental-US bounding box into a grid of smaller bbox cells so
    # nationwide Overpass fetches can be tiled — a single nationwide query
    # exceeds public Overpass server limits. Cell size is
    # configurable; smaller cells = more, lighter requests (research R2).
    module UsTiles
      # Approximate continental-US (CONUS) bounds in WGS84 degrees.
      CONUS = { south: 24.5, west: -125.0, north: 49.5, east: -66.9 }.freeze
      DEFAULT_CELL_DEG = 2.0

      module_function

      # Returns an array of { south:, west:, north:, east: } cells tiling `bounds`.
      def cells(cell_deg: DEFAULT_CELL_DEG, bounds: CONUS)
        result = []
        lat = bounds[:south]
        while lat < bounds[:north]
          north = [ lat + cell_deg, bounds[:north] ].min
          lng = bounds[:west]
          while lng < bounds[:east]
            east = [ lng + cell_deg, bounds[:east] ].min
            result << { south: lat, west: lng, north: north, east: east }
            lng += cell_deg
          end
          lat += cell_deg
        end
        result
      end
    end
  end
end
