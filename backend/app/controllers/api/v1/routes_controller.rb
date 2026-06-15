module Api
  module V1
    # Plans a camera-avoiding driving route (US1). POST so origin/destination
    # never appear in URLs or logs (anonymity, FR-011).
    class RoutesController < BaseController
      def create
        origin = coordinate(route_params[:origin], :origin)
        destination = coordinate(route_params[:destination], :destination)

        result = Routing::RoutePlanner.new.plan(
          origin: origin,
          destination: destination,
          locale: route_params[:locale] || I18n.locale.to_s
        )
        render json: RouteSerializer.new(result).as_json
      rescue ActionController::ParameterMissing => e
        # Handle bad input here, inside the locale-scoped around_action, so the
        # 400 message is localized — class-level rescue_from runs after the locale
        # scope has unwound and would render in the default locale.
        render_bad_request(e)
      rescue Geo::HttpClient::ServiceError
        render_error(code: "no_route", status: :unprocessable_entity)
      end

      private

      def route_params
        params.require(:route).permit(
          :locale,
          origin: %i[lat lng], destination: %i[lat lng]
        )
      end

      # Validates and parses a {lat, lng} pair via the shared helper, which rejects
      # missing/non-numeric/out-of-range input as a 400 rather than silently
      # coercing it to a Null Island (0,0) route.
      def coordinate(hash, name)
        lat, lng = required_coordinate(hash&.dig(:lat), hash&.dig(:lng), name)
        { lat: lat, lng: lng }
      end
    end
  end
end
