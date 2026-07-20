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

    # Leading house number in a typed address: "1234 …", "123A …". Captured so it
    # can be echoed onto a street-only match (see #humanized_label).
    HOUSE_NUMBER_RE = /\A\s*(\d+[a-z]?)\b/i

    # A trailing US ZIP (with optional +4) on a humanized label. Stripped so two
    # rows that differ ONLY by ZIP collapse to one street (see #dedupe_streets).
    ZIP_SUFFIX_RE = /\s+\d{5}(?:-\d{4})?\z/

    # Builds the configured client. By default the deployment spans a whole
    # country (CountryRegistry, default US): the viewbox is derived from the
    # country's bbox and the single-state workarounds are off — the whole-country
    # index has admin_level-4 boundaries, so the state disambiguates rather than
    # nullifies (FR-003/FR-004, research R3).
    #
    # GEOCODER_REGION_STATE is an explicit single-region DEV override (an extract
    # lacking the country's state boundaries): it keeps the legacy strip-and-fall-
    # back behavior so a state-only dev stack still geocodes correctly.
    def self.build
      base_url = ENV.fetch("GEOCODER_URL", "http://geocoder:8080")

      # CountryRegistry.single_state? is the single source of the mode decision
      # (shared with Geocoding::MapFraming) so geocoding and map framing always agree.
      if CountryRegistry.single_state?
        new(base_url: base_url, viewbox: ENV["GEOCODER_VIEWBOX"].presence,
            region_state: ENV["GEOCODER_REGION_STATE"])
      else
        country = CountryRegistry.resolve
        new(base_url: base_url, viewbox: country.viewbox, country_spanning: true)
      end
    end

    # `country_spanning` marks an index that covers a whole country (admin_level-4
    # boundaries present): the state token is kept (it disambiguates) and labels
    # use the result's real addr["state"].
    #
    # `region_state` is the legacy single-region dev path — the full name of the
    # single state a dev extract covers (e.g. "Iowa"); it is stripped from queries
    # and used as the label fallback (see #normalize_query / #humanized_label).
    def initialize(base_url:, viewbox: nil, region_state: nil, country_spanning: false, **opts)
      super(base_url: base_url, **opts)
      @viewbox = viewbox
      @region_state = region_state&.strip
      @country_spanning = country_spanning
    end

    # Forward search / autocomplete.
    # Returns an array of result hashes: { label:, lat:, lng:, type:, confidence: }
    #
    # We over-fetch from Nominatim (#fetch_limit) and then collapse duplicate
    # street segments (#dedupe_streets) before trimming back to the caller's
    # `limit`. A street is commonly split into several OSM ways (one per
    # subdivision / ZIP), so a plain request returns the same road many times
    # (one residential street can come back 7×); collapsing first means the
    # trimmed list still holds that many *distinct* places instead of one road
    # repeated.
    def search(text, lang: "en", limit: 5)
      # Guard: a non-positive limit would reach fetch_limit (limit * 4) and
      # Array#first(negative) below and raise ArgumentError -> 500. The controller
      # already clamps, but this keeps the shared client safe for any caller
      # (defense in depth — the real crash site is here, not the boundary).
      limit = [ limit.to_i, 1 ].max
      typed_house_number = leading_house_number(text)
      params = { q: normalize_query(text), format: "jsonv2", addressdetails: 1,
                 limit: fetch_limit(limit), "accept-language": lang }
      params.merge!(viewbox: @viewbox, bounded: 1) if @viewbox
      body = get("/search", **params)
      results = Array(body).map { |f| to_result(f, typed_house_number: typed_house_number) }
      dedupe_streets(results).first(limit)
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
    #
    # Disabled for a country-spanning index (FR-004): with whole-country data the
    # state boundary EXISTS, so the token disambiguates same-named cities across
    # states instead of nullifying the query — stripping it would be the bug.
    def normalize_query(text)
      return text if @country_spanning
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

    # The leading house number a user typed, or nil. Read from the raw text (not
    # the state-normalized query) so the digits survive regardless of #normalize_query.
    def leading_house_number(text)
      text.to_s[HOUSE_NUMBER_RE, 1]
    end

    # How many candidates to request from Nominatim for a caller asking for
    # `limit`. We over-fetch so that collapsing duplicate street segments (a
    # single road returns once per OSM way) still leaves enough *distinct* places
    # to fill the caller's limit. Capped at 20 to bound the response size.
    def fetch_limit(limit)
      [ limit * 4, 20 ].min
    end

    # Collapses results that refer to the same street into one. OSM splits a road
    # into a way per subdivision, so "1234 Larkmoor Drive" comes back as the same
    # road seven times across three ZIPs. Results whose labels match once the ZIP
    # is removed are grouped; the highest-confidence member represents the group
    # (ties keep Nominatim's original, relevance-ordered position). When a group
    # collapsed more than one member, the ZIP was its only differentiator, so the
    # surviving label drops it ("…, Fairhaven, IA"). A lone result is untouched —
    # a precise house match keeps its full "…, IA 50319" label.
    def dedupe_streets(results)
      results.each_with_index
             .group_by { |result, _index| dedupe_key(result[:label]) }
             .map do |_key, group|
               representative, = group.min_by { |result, index| [ -result[:confidence], index ] }
               next representative if group.one?

               representative.merge(label: representative[:label].sub(ZIP_SUFFIX_RE, ""))
             end
    end

    def dedupe_key(label)
      label.to_s.sub(ZIP_SUFFIX_RE, "").downcase
    end

    # Maps a Nominatim jsonv2 place into our normalized result shape. Nominatim
    # returns lat/lon as strings. `typed_house_number` (parsed from the query) is
    # echoed into the label when the geocoder can only resolve the street (see
    # #humanized_label).
    def to_result(place, typed_house_number: nil)
      {
        label: humanized_label(place, typed_house_number: typed_house_number),
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
    def humanized_label(place, typed_house_number: nil)
      addr = place["address"]
      return place["display_name"].to_s unless addr.is_a?(Hash)

      # A street address leads with "house number + street"; everything else (a
      # city, a named POI, a bare street) leads with its own name. This keeps POIs
      # and cities free of road noise ("Old Capitol, Iowa City, IA").
      #
      # When the user typed a house number but the geocoder could only resolve the
      # street (no data for that exact house — common where TIGER has no
      # interpolation for the road), we echo the typed number onto the street as a
      # best-effort match: "1234 Larkmoor Drive, …". The pin is still the street
      # (confidence stays at the street rank — see #confidence_for), but the label
      # reflects what the user asked for instead of silently dropping it.
      lead =
        if addr["house_number"]
          [ addr["house_number"], addr["road"] ].compact.join(" ")
        elsif typed_house_number.present? && addr["road"].present?
          "#{typed_house_number} #{addr['road']}"
        else
          place["name"].presence || addr["road"]
        end

      # A whole-country index carries the real `state` in address details, so the
      # label uses it directly (FR-004). The single-region dev extract usually
      # omits `state` (no state-level boundary — the gap #normalize_query works
      # around), so there we fall back to the configured region state, otherwise
      # every label would be missing "IA".
      state = addr["state"].presence
      state ||= @region_state unless @country_spanning
      region = [ state_abbr(state), addr["postcode"] ].compact.join(" ").presence
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
