module Api
  module V1
    # Base for all v1 API controllers. Provides a single, structured, localized,
    # actionable error shape (Constitution Principle III) and sets the request
    # locale from the Accept-Language header / ?locale= param (FR-014).
    class BaseController < ActionController::API
      rescue_from ActionController::ParameterMissing, with: :render_bad_request
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from Geo::HttpClient::ServiceError, with: :render_service_unavailable

      around_action :switch_locale

      private

      def switch_locale(&action)
        locale = params[:locale].presence || locale_from_header || I18n.default_locale
        locale = I18n.default_locale unless I18n.available_locales.map(&:to_s).include?(locale.to_s)
        I18n.with_locale(locale, &action)
      end

      def locale_from_header
        header = request.headers["Accept-Language"]
        header&.scan(/[a-z]{2}/i)&.first&.downcase
      end

      # Renders { code, message, details? } — code is a stable machine string,
      # message is human-readable, localized, and actionable.
      def render_error(code:, status:, message: nil, details: nil)
        body = { code: code, message: message || I18n.t("errors.#{code}", default: code.to_s.humanize) }
        body[:details] = details if details
        render json: body, status: status
      end

      def render_bad_request(exception)
        render_error(code: "bad_request", status: :bad_request, details: { param: exception.param })
      end

      # Parses a value to Float, rejecting missing/non-numeric input as a 400 rather
      # than silently coercing it to 0.0 (which would route/geocode Null Island).
      def required_float(value, name)
        Float(value)
      rescue ArgumentError, TypeError
        raise ActionController::ParameterMissing, name
      end

      # Validates a lat/lng pair is numeric and within geographic range; returns
      # [lat, lng] or raises a 400. `name` labels the offending param.
      def required_coordinate(lat, lng, name)
        lat = required_float(lat, name)
        lng = required_float(lng, name)
        raise ActionController::ParameterMissing, name unless lat.between?(-90, 90) && lng.between?(-180, 180)

        [ lat, lng ]
      end

      def render_not_found(_exception)
        render_error(code: "not_found", status: :not_found)
      end

      def render_service_unavailable(_exception)
        render_error(code: "service_unavailable", status: :service_unavailable)
      end
    end
  end
end
