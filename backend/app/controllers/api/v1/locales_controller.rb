module Api
  module V1
    # Lists supported interface languages (drives the language switcher, FR-013).
    class LocalesController < BaseController
      # Display names for the available locales. This catalog MUST stay in sync
      # with config/locales/*.yml and the frontend SUPPORTED_LOCALES list, so a
      # derived/selected locale always resolves to a fully translated language
      # (the authoritative-catalog dependency, research D8).
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
