module Api
  module V1
    # Tells the client whether camera avoidance is available for a point and how
    # fresh the data is (FR-018).
    class CoverageController < BaseController
      def show
        lat, lng = required_coordinate(params.require(:lat), params.require(:lng), :lat)
        area = CoverageArea.containing(lng, lat).first

        render json: {
          covered: area.present?,
          area_name: area&.name,
          data_freshness_at: area&.data_freshness_at
        }
      end

      # Bounding box of the covered region(s) so the client can frame the map on
      # the coverage area, with no hardcoded launch state. `bounds` is null when no
      # coverage area is loaded.
      def bounds
        render json: { bounds: CoverageArea.bounds }
      end
    end
  end
end
