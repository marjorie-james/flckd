module Api
  module V1
    # Negotiates the response locale from an Accept-Language header (contracts §2;
    # research D2). Parses (tag, q) pairs, orders by quality descending then by
    # header order (a stable, deterministic tie-break — FR-013), reduces each tag
    # to its base language (`es-MX` → `es`, FR-004), and returns the first base
    # that is available, else the default (FR-005). Empty, wildcard, and malformed
    # entries are skipped (FR-012). Pure and deterministic — same header in, same
    # locale out.
    #
    # The frontend sends the *effective* selected locale as Accept-Language
    # (FR-016), so this usually receives a single clean tag; proper negotiation
    # keeps the API correct for direct/non-browser callers too.
    class LocaleNegotiator
      def self.call(header, available: I18n.available_locales, default: I18n.default_locale)
        available_codes = available.map(&:to_s)
        ranked(header).each do |base|
          return base.to_sym if available_codes.include?(base)
        end
        default.to_sym
      end

      # Base language codes from the header, ordered by quality (desc) then by
      # original position. Returns [] for a nil/blank header.
      def self.ranked(header)
        return [] if header.nil? || header.strip.empty?

        header.split(",").each_with_index.filter_map { |part, index|
          tag, *params = part.strip.split(";")
          base = tag.to_s.downcase.split("-").first
          next unless base&.match?(/\A[a-z]{2,3}\z/)

          [ base, quality_of(params), index ]
        }.sort_by { |(_base, quality, index)| [ -quality, index ] }.map(&:first)
      end

      # Extracts the q-value (0.0–1.0) from a tag's parameters, defaulting to 1.0
      # when absent or unparseable.
      def self.quality_of(params)
        q = params.find { |p| p.strip.start_with?("q=") }
        return 1.0 unless q

        Float(q.strip.delete_prefix("q="), exception: false) || 1.0
      end
      private_class_method :quality_of
    end
  end
end
