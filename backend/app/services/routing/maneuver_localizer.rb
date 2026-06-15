module Routing
  # Maps provider-neutral maneuver data to localized, human-readable text so
  # turn-by-turn directions translate cleanly (FR-015) rather than relying on a
  # provider's prose. Falls back to the engine's instruction if no template.
  module ManeuverLocalizer
    module_function

    def localize(maneuvers, locale: "en")
      Array(maneuvers).map do |m|
        {
          type: m[:type],
          localized_text: localized_text(m, locale),
          distance_m: m[:distance_m],
          shape_index: m[:shape_index]
        }
      end
    end

    # Internal helper for #localize — not part of the module's public contract.
    def localized_text(maneuver, locale)
      key = "maneuvers.#{maneuver[:type]}"
      I18n.t(key, locale: locale, default: maneuver[:instruction] || maneuver[:type].to_s)
    end
    private_class_method :localized_text
  end
end
