module Api
  module V1
    # Lists supported interface languages (drives the language switcher, FR-013).
    class LocalesController < BaseController
      LOCALE_NAMES = { "en" => "English", "es" => "Español" }.freeze

      def index
        render json: {
          default: I18n.default_locale.to_s,
          locales: I18n.available_locales.map { |code|
            { code: code.to_s, name: LOCALE_NAMES[code.to_s] || code.to_s }
          }
        }
      end
    end
  end
end
