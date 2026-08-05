module Geo
  # Base HTTP client for the self-hosted geo services (routing, geocoding).
  # These run on our own infrastructure over a private network — never a third
  # party — so user coordinates are not exposed externally (FR-012a).
  #
  # In test, subclasses are replaced by fakes backed by recorded fixtures
  # (see spec/support/geo_fakes.rb), so the suite stays deterministic with no
  # network calls (Constitution Principle II).
  class HttpClient
    class ServiceError < StandardError; end

    DEFAULT_TIMEOUT = 5 # seconds

    def initialize(base_url:, timeout: DEFAULT_TIMEOUT)
      @base_url = base_url
      @timeout = timeout
    end

    private

    def connection
      @connection ||= Faraday.new(url: @base_url) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.options.timeout = @timeout
        f.options.open_timeout = @timeout
      end
    end

    def get(path, params = {}, timeout: nil, **query)
      timeout = request_timeout(timeout)
      handle { connection.get(path, params.merge(query)) { |request| apply_timeout(request, timeout) } }
    end

    def post(path, body = {}, timeout: nil)
      timeout = request_timeout(timeout)
      handle { connection.post(path, body) { |request| apply_timeout(request, timeout) } }
    end

    def request_timeout(timeout)
      return if timeout.nil?

      timeout = Float(timeout)
      raise ArgumentError, "timeout must be positive" unless timeout.positive?

      [ timeout, @timeout ].min
    end

    def apply_timeout(request, timeout)
      return if timeout.nil?

      request.options.timeout = timeout
      request.options.open_timeout = timeout
    end

    def handle
      response = yield
      raise ServiceError, "geo service returned #{response.status}" unless response.success?

      response.body
    rescue Faraday::Error => e
      raise ServiceError, "geo service unreachable: #{e.class}"
    end
  end
end
