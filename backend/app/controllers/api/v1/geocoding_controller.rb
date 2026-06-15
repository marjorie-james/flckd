module Api
  module V1
    class GeocodingController < BaseController
      def search
        text = params.require(:q)
        results = geocoder.search(text, lang: I18n.locale.to_s, limit: limit)
        render json: { results: results }
      end

      def reverse
        coord = params.require(:coordinate).permit(:lat, :lng)
        lat, lng = required_coordinate(coord[:lat], coord[:lng], :coordinate)
        result = geocoder.reverse(lat: lat, lng: lng, lang: I18n.locale.to_s)
        return render_error(code: "not_found", status: :not_found) unless result

        render json: result
      end

      private

      def geocoder
        @geocoder ||= Geocoding::GeocoderClient.build
      end

      def limit
        [ (params[:limit] || 5).to_i, 10 ].min
      end
    end
  end
end
