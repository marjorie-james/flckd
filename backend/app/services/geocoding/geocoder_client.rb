module Geocoding
  # Forward/reverse geocoding via self-hosted Nominatim. Runs on our own
  # infrastructure (the OSM extract imported locally) so typed addresses are
  # never sent to a third party (FR-012a).
  class GeocoderClient < Geo::HttpClient
    # USPS two-letter abbreviations for all 50 states + DC. Used to strip the
    # state component from a typed address (see #normalize_query). No US place is
    # named after a bare state code, so dropping these as standalone query
    # components is unambiguous.
    US_STATE_ABBREVIATIONS = %w[
      AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO
      MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC
    ].to_set.freeze

    # Full state name → USPS abbreviation, for building a standard US address
    # label ("…, IA 50322" instead of "…, Iowa, United States" — see #humanized_label).
    US_STATE_ABBR = {
      "Alabama" => "AL", "Alaska" => "AK", "Arizona" => "AZ", "Arkansas" => "AR",
      "California" => "CA", "Colorado" => "CO", "Connecticut" => "CT", "Delaware" => "DE",
      "Florida" => "FL", "Georgia" => "GA", "Hawaii" => "HI", "Idaho" => "ID",
      "Illinois" => "IL", "Indiana" => "IN", "Iowa" => "IA", "Kansas" => "KS",
      "Kentucky" => "KY", "Louisiana" => "LA", "Maine" => "ME", "Maryland" => "MD",
      "Massachusetts" => "MA", "Michigan" => "MI", "Minnesota" => "MN", "Mississippi" => "MS",
      "Missouri" => "MO", "Montana" => "MT", "Nebraska" => "NE", "Nevada" => "NV",
      "New Hampshire" => "NH", "New Jersey" => "NJ", "New Mexico" => "NM", "New York" => "NY",
      "North Carolina" => "NC", "North Dakota" => "ND", "Ohio" => "OH", "Oklahoma" => "OK",
      "Oregon" => "OR", "Pennsylvania" => "PA", "Rhode Island" => "RI", "South Carolina" => "SC",
      "South Dakota" => "SD", "Tennessee" => "TN", "Texas" => "TX", "Utah" => "UT",
      "Vermont" => "VT", "Virginia" => "VA", "Washington" => "WA", "West Virginia" => "WV",
      "Wisconsin" => "WI", "Wyoming" => "WY", "District of Columbia" => "DC"
    }.freeze

    # viewbox restricts search results to the loaded region.
    # Format: "min_lng,max_lat,max_lng,min_lat" (Nominatim left,top,right,bottom).
    def self.build
      new(base_url: ENV.fetch("GEOCODER_URL", "http://geocoder:8080"),
          viewbox: ENV["GEOCODER_VIEWBOX"].presence,
          region_state: ENV["GEOCODER_REGION_STATE"].presence)
    end

    # region_state is the full name of the single state this deployment's OSM
    # extract covers (e.g. "Iowa"). It is stripped from queries alongside the
    # USPS abbreviations — see #normalize_query for why.
    def initialize(base_url:, viewbox: nil, region_state: nil, **opts)
      super(base_url: base_url, **opts)
      @viewbox = viewbox
      @region_state = region_state&.strip
    end

    # Forward search / autocomplete.
    # Returns an array of result hashes: { label:, lat:, lng:, type:, confidence: }
    def search(text, lang: "en", limit: 5)
      params = { q: normalize_query(text), format: "jsonv2", addressdetails: 1,
                 limit: limit, "accept-language": lang }
      params.merge!(viewbox: @viewbox, bounded: 1) if @viewbox
      body = get("/search", **params)
      Array(body).map { |f| to_result(f) }
    end

    # Reverse geocode. Returns a single result hash, or nil when nothing matches.
    # `lang` localizes place names, consistent with #search (FR-015).
    def reverse(lat:, lng:, lang: "en")
      body = get("/reverse", lat: lat, lon: lng, format: "jsonv2",
                            addressdetails: 1, "accept-language": lang)
      return nil unless body.is_a?(Hash) && body["lat"]

      to_result(body)
    end

    private

    # Drops the state component from a typed US address before it reaches
    # Nominatim. Our geocoder runs on a single-state OSM extract whose import
    # does not include the state-level (admin_level 4) boundary, so a state
    # token like "IA" or "Iowa" matches nothing in any result's address
    # hierarchy. Nominatim then treats it as an unsatisfied required term and
    # discards every house-number match — so "1007 East Grand Avenue, Des Moines,
    # IA, 50319" returns nothing while the same query without the state resolves.
    # The viewbox already constrains results to the region, so the state token
    # is redundant; removing it is strictly safe here (no cross-state ambiguity
    # is possible in a single-state extract).
    #
    # Only a comma-delimited component that is exactly a USPS abbreviation or the
    # configured region's state name is removed, and never the first component
    # (the street) — so a city sharing a state's name, e.g. "Washington, IA",
    # keeps "Washington" and only loses "IA".
    def normalize_query(text)
      return text unless text.is_a?(String) && text.include?(",")

      parts = text.split(",").map(&:strip)
      kept = parts.each_with_index.reject do |part, index|
        index.positive? && state_token?(part)
      end.map(&:first)

      kept.length == parts.length ? text : kept.join(", ")
    end

    def state_token?(part)
      US_STATE_ABBREVIATIONS.include?(part.upcase) ||
        (@region_state.present? && part.casecmp?(@region_state))
    end

    # Maps a Nominatim jsonv2 place into our normalized result shape. Nominatim
    # returns lat/lon as strings.
    def to_result(place)
      {
        label: humanized_label(place),
        lat: place["lat"]&.to_f,
        lng: place["lon"]&.to_f,
        type: place["type"] || place["category"],
        confidence: confidence_for(place)
      }
    end

    # Builds a glanceable, US-standard address label from Nominatim's structured
    # `address` components instead of its verbose `display_name`. So
    # "1007, East Grand Avenue, East Village, Des Moines, Polk County, 50319, United States"
    # becomes "1007 East Grand Avenue, Des Moines, IA 50319". Drops the neighbourhood,
    # county, and country; abbreviates the state; folds house number + street into
    # one line. Falls back to `display_name` when address details are absent.
    def humanized_label(place)
      addr = place["address"]
      return place["display_name"].to_s unless addr.is_a?(Hash)

      # A street address leads with "house number + street"; everything else (a
      # city, a named POI, a bare street) leads with its own name. This keeps POIs
      # and cities free of road noise ("Old Capitol, Iowa City, IA").
      lead =
        if addr["house_number"]
          [ addr["house_number"], addr["road"] ].compact.join(" ")
        else
          place["name"].presence || addr["road"]
        end

      # The single-state extract usually omits `state` from address details — it
      # has no state-level boundary (the same gap #normalize_query works around) —
      # so fall back to the configured region state, otherwise every label would
      # be missing "IA".
      region = [ state_abbr(addr["state"].presence || @region_state), addr["postcode"] ]
                 .compact.join(" ").presence
      parts = [ lead, city_of(addr), region ].compact.reject(&:blank?).uniq

      parts.join(", ").presence || place["display_name"].to_s
    end

    # The most specific populated-place name Nominatim provides for the address.
    def city_of(addr)
      addr["city"] || addr["town"] || addr["village"] || addr["hamlet"] ||
        addr["municipality"] || addr["suburb"] || addr["neighbourhood"]
    end

    def state_abbr(state)
      return nil if state.blank?

      US_STATE_ABBR[state] || state
    end

    # Confidence reflects how *precisely* the result matches an address, derived
    # from Nominatim's place_rank — its address-specificity scale (30 = an exact
    # house number, ~26 a street, lower = broader areas like city or county).
    # Dividing by the exact-address rank yields a monotonic value in [0, 1], so
    # an exact address scores highest. We deliberately avoid Nominatim's
    # `importance` (a Wikipedia-style prominence signal): it is near-zero or
    # negative for interpolated TIGER house numbers, which would rank the most
    # precise matches as the least confident. Falls back to a neutral 0.5 when
    # Nominatim omits the rank.
    EXACT_ADDRESS_RANK = 30.0

    def confidence_for(place)
      rank = place["place_rank"]&.to_f
      return 0.5 unless rank&.positive?

      (rank / EXACT_ADDRESS_RANK).clamp(0.0, 1.0).round(2)
    end
  end
end
