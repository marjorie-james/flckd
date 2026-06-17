module CameraData
  module Sources
    # Pulls ALPR/Flock camera nodes from OpenStreetMap via an Overpass API
    # endpoint and normalizes them for the Importer.
    #
    # OSM tagging convention (see research R5):
    #   man_made=surveillance + surveillance:type=ALPR
    #   man_made=surveillance + camera:type~alpr/anpr
    #   man_made=surveillance + brand/operator~Flock
    #
    # This is the canonical ALPR substrate. Community projects like DeFlock
    # contribute their locations *into* OSM, so querying OSM already covers that
    # data — there is no separate DeFlock fetch (ADR 0001).
    #
    # Provenance/legitimacy notes:
    #   * OSM data is ODbL-licensed; we record that license and attribute it.
    #   * We query only a coverage-region bounding box — never a user location.
    #   * We identify our application honestly in the User-Agent, as the Overpass
    #     usage policy requires, and back off on 429/504 rate-limit responses.
    #   * The endpoint is configurable (OVERPASS_URL) so this can run against a
    #     self-hosted Overpass instance instead of the public API.
    class Overpass < Base
      include OsmTagging

      # Same OpenStreetMap origin + ODbL license as the PBF-extract source — they
      # differ only in *mechanism* (live API vs. local file), so they share one
      # provenance identity (ADR 0002).
      source(**OsmTagging::PROVENANCE)

      DEFAULT_ENDPOINT = "https://overpass-api.de/api/interpreter".freeze
      DEFAULT_USER_AGENT = "flckd-camera-import/1.0 (+https://github.com/bruschill/flckd; ALPR avoidance reference data)".freeze
      DEFAULT_TIMEOUT = 90 # seconds; Overpass queries over a metro bbox are slow

      # Delta fetches are only valid for recent windows; beyond this age a full
      # fetch is cheaper and more reliable than a diff covering weeks of changes.
      DELTA_MAX_AGE = 14.days
      private_constant :DELTA_MAX_AGE

      class FetchError < StandardError; end

      # Provide exactly one of:
      #   bbox:  { south:, west:, north:, east: }   — a single bounding box
      #   tiles: [ {south:,west:,north:,east:}, ... ] — many cells (e.g. UsTiles.cells)
      # Tiles are fetched sequentially (concurrency bound = 1) to respect source
      # fair-use, with per-request rate-limit backoff; results are de-duplicated
      # by external_ref across cells.
      def initialize(bbox: nil, tiles: nil, endpoint: nil, user_agent: nil, timeout: DEFAULT_TIMEOUT, max_retries: 2, backoff: ->(n) { sleep(2**n) })
        raise ArgumentError, "provide exactly one of bbox: or tiles:" unless bbox.nil? ^ tiles.nil?

        @bbox = bbox
        @tiles = tiles
        @endpoint = endpoint || ENV.fetch("OVERPASS_URL", DEFAULT_ENDPOINT)
        @user_agent = user_agent || ENV.fetch("OVERPASS_USER_AGENT", DEFAULT_USER_AGENT)
        @timeout = timeout
        @max_retries = max_retries
        @backoff = backoff
      end

      # True when `since` falls within the delta window — callers should check
      # this before calling #fetch_delta to avoid over-wide diffs.
      def supports_delta?(since:)
        since.present? && since >= DELTA_MAX_AGE.ago
      end

      def fetch
        return normalize_body(request(query_for(@bbox))) if @bbox

        seen = {}
        @tiles.each do |cell|
          normalize_body(request(query_for(cell))).each { |rec| seen[rec[:external_ref]] = rec }
        end
        seen.values
      end

      # Fetches only cameras that changed (added, modified, or deleted in OSM)
      # since `since`. Returns { upserted: [...records], deleted_refs: [...refs] }.
      # `upserted` records have the same shape as #fetch. `deleted_refs` are
      # "osm:node/<id>" strings for cameras that were explicitly deleted from OSM
      # — callers should treat them like cameras absent from this run.
      def fetch_delta(since:)
        since_iso = since.utc.iso8601
        return parse_diff_body(request(diff_query_for(@bbox, since: since_iso))) if @bbox

        upserted = {}
        deleted_refs = []
        @tiles.each do |cell|
          result = parse_diff_body(request(diff_query_for(cell, since: since_iso)))
          result[:upserted].each { |rec| upserted[rec[:external_ref]] = rec }
          deleted_refs.concat(result[:deleted_refs])
        end
        { upserted: upserted.values, deleted_refs: deleted_refs.uniq }
      end

      private

      def normalize_body(body)
        elements = body.is_a?(Hash) ? Array(body["elements"]) : []
        elements.filter_map { |el| normalize(el) }
      end

      def normalize(element)
        return nil unless element["type"] == "node"

        lat = element["lat"]
        lng = element["lon"]
        return nil if lat.nil? || lng.nil?

        # The query already narrows to ALPR nodes server-side, so every returned
        # node maps straight through the shared OSM record builder (parity with
        # the PBF-extract source — ADR 0002).
        osm_node_record(osm_id: element["id"], lat: lat, lng: lng, tags: element["tags"] || {})
      end

      # Overpass QL with [diff:...] — returns nodes that changed since `since`.
      # The response includes "action": "create"|"modify"|"delete" per element.
      # Delegates to query_for so node filters stay in one place.
      def diff_query_for(box, since:)
        query_for(box, diff_since: since)
      end

      # Splits a [diff:...] response body into upserted records and deleted refs.
      # Nodes with action "delete" have no coordinates — we only need their id.
      # Ways are ignored (same as in normalize_body for full fetches).
      def parse_diff_body(body)
        elements = body.is_a?(Hash) ? Array(body["elements"]) : []
        upserted = []
        deleted_refs = []

        elements.each do |el|
          next unless el["type"] == "node"
          if el["action"] == "delete"
            deleted_refs << "osm:node/#{el['id']}" if el["id"]
          else
            rec = normalize(el)
            upserted << rec if rec
          end
        end

        { upserted: upserted, deleted_refs: deleted_refs }
      end

      # Overpass QL: ALPR-flavored surveillance nodes within the given bbox.
      # Pass diff_since: to emit a [diff:"..."] directive for delta fetches —
      # keeps the node filter set in one place so full and delta queries stay in sync.
      def query_for(box, diff_since: nil)
        coords = box.fetch_values(:south, :west, :north, :east)
        # Defense-in-depth: only numeric coordinates are ever interpolated into
        # the Overpass QL (bbox comes from constants/validated floats today).
        raise ArgumentError, "Overpass bbox values must be numeric" unless coords.all?(Numeric)

        bbox = coords.join(",")
        diff_directive = diff_since ? %([diff:"#{diff_since}"]) : ""
        <<~QL
          [out:json][timeout:#{@timeout}]#{diff_directive};
          (
            node["man_made"="surveillance"]["surveillance:type"~"^ALPR$",i](#{bbox});
            node["man_made"="surveillance"]["camera:type"~"alpr|anpr",i](#{bbox});
            node["man_made"="surveillance"]["brand"~"flock",i](#{bbox});
            node["man_made"="surveillance"]["operator"~"flock",i](#{bbox});
          );
          out body;
        QL
      end

      def request(ql)
        attempt = 0
        begin
          response = connection.post(@endpoint, "data=#{CGI.escape(ql)}")
          if rate_limited?(response.status)
            raise FetchError, "Overpass rate-limited (#{response.status})"
          end
          unless response.success?
            raise FetchError, "Overpass returned #{response.status}"
          end

          response.body
        rescue FetchError, Faraday::Error => e
          attempt += 1
          if attempt <= @max_retries
            @backoff.call(attempt)
            retry
          end
          raise FetchError, "Overpass unreachable after #{@max_retries} retries: #{e.message}"
        end
      end

      def rate_limited?(status)
        [ 429, 504 ].include?(status)
      end

      def connection
        @connection ||= Faraday.new do |f|
          f.headers["User-Agent"] = @user_agent
          f.headers["Content-Type"] = "application/x-www-form-urlencoded"
          f.response :json, content_type: /\bjson$/
          f.options.timeout = @timeout
          f.options.open_timeout = 10
          # Reuse one keep-alive connection across the tiled requests instead of
          # a fresh TCP handshake per tile.
          f.adapter :net_http_persistent
        end
      end
    end
  end
end
