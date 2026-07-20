module CameraData
  module Sources
    # Fetches a GeoJSON FeatureCollection of camera points over HTTP from an open
    # government / municipal data endpoint, and normalizes it through the exact
    # same path as the on-disk GeojsonFile source (parse_features -> normalize).
    #
    # It works with any URL that returns a GeoJSON FeatureCollection, notably:
    #   * Socrata:  https://data.city.gov/resource/<id>.geojson
    #   * ArcGIS:   https://services.../FeatureServer/0/query?where=1=1&outFields=*&f=geojson
    #
    # Why this exists: it unlocks OFFICIAL, permissively-licensed ALPR datasets
    # that municipalities publish but that are NOT in OpenStreetMap — additive
    # coverage on top of the OSM/DeFlock substrate. Because provenance + license
    # vary per dataset they are supplied at construction; AggregateImport drops
    # any source with no license (FR-005), so a caller MUST record the dataset's
    # license, and the operator is responsible for pointing this at an
    # ALPR-specific dataset (every point is ingested as a camera, exactly like
    # GeojsonFile — there is no server-side ALPR narrowing for open data).
    #
    # Anonymity: we fetch the WHOLE published dataset from a fixed public URL,
    # never a user location — consistent with every other source (FR-012a).
    class OpenDataGeojson < GeojsonFile
      class FetchError < StandardError; end

      DEFAULT_USER_AGENT =
        "flckd-camera-import/1.0 (+https://github.com/marjorie-james/flckd; ALPR avoidance reference data)".freeze
      DEFAULT_TIMEOUT = 60 # seconds; open-data exports can be large

      def initialize(url:, name:, kind: "open-data", license: nil,
                     user_agent: nil, timeout: DEFAULT_TIMEOUT, connection: nil)
        super(path: nil, name: name, kind: kind, url: url, license: license)
        @user_agent = user_agent || DEFAULT_USER_AGENT
        @timeout = timeout
        @connection = connection
      end

      # Reuses GeojsonFile's feature normalization, but sources the raw document
      # over HTTP instead of from disk.
      def fetch
        parse_features(http_get(@source_url))
      end

      private

      def http_get(url)
        response = connection.get(url)
        unless response.success?
          raise FetchError, "open-data endpoint returned #{response.status}"
        end

        # With no JSON response middleware the body is a raw String (what
        # parse_features wants). Guard the case a caller wired JSON parsing in.
        response.body.is_a?(String) ? response.body : JSON.generate(response.body)
      end

      def connection
        @connection ||= Faraday.new do |f|
          f.headers["User-Agent"] = @user_agent
          f.options.timeout = @timeout
          f.options.open_timeout = 10
        end
      end
    end
  end
end
