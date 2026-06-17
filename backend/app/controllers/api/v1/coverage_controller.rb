module Api
  module V1
    # Honest, per-data-region camera coverage: whether a point falls in an
    # ingested data-region and how fresh that region's data is (FR-008), plus the
    # configured country's framing extent (FR-007).
    class CoverageController < BaseController
      def show
        lat, lng = required_coordinate(params.require(:lat), params.require(:lng), :coordinate)
        # PRESENCE of camera data at the point (a containing data-region), with
        # that region's own freshness — not "is this inside the country".
        area = CoverageArea.containing(lng, lat).first

        render json: {
          covered: area.present?,
          data_freshness_at: area&.data_freshness_at
        }
      end

      # The deployment's configured framing extent (FR-007): a whole-country
      # deployment frames the entire country (registry bbox, however sparse the
      # camera footprint); a single-state dev deployment frames that state. See
      # Geocoding::MapFraming.
      def bounds
        render json: { bounds: Geocoding::MapFraming.bounds }
      end
    end
  end
end
