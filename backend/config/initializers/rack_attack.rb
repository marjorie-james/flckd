# Rate limiting via rack-attack (FR — abuse protection without tracking).
#
# Anonymity note: throttle buckets are keyed on a COARSE, NON-RETAINED hash of
# the client IP held only in the cache for the rolling window, never persisted
# and never linked to route data. This bounds abuse without building a profile.
class Rack::Attack
  # Counters live in Rack::Attack.cache.store, which defaults to Rails.cache;
  # entries expire with the rolling window. In production Rails.cache is Solid Cache
  # on the dedicated `cache` database (config/environments/production.rb +
  # config/cache.yml), so counters are durable and SHARED across Kamal containers —
  # throttling aggregates cluster-wide rather than per-container. In tests we pin an
  # isolated in-process store so counts don't leak between examples.
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new if Rails.env.test?

  # The real client IP. Rack::Request#ip does NOT honour Rails' trusted-proxy
  # filtering, so behind the Kamal/Thruster proxy it would either return the proxy's
  # own IP (collapsing every client into one bucket) or an attacker-controlled
  # X-Forwarded-For. ActionDispatch::Request#remote_ip walks X-Forwarded-For,
  # stripping trusted (private-range) proxies, to recover the true client edge IP.
  # (For full spoof-resistance the proxy should overwrite, not append, XFF.)
  def self.client_ip(req)
    ActionDispatch::Request.new(req.env).remote_ip
  rescue StandardError
    req.ip
  end

  # Coarse, non-identifying discriminator: a truncated HMAC of the client IP, so
  # the raw IP is never stored as a key. A plain digest would be trivially
  # reversible (the ~4.3B IPv4 space is brute-forceable), recovering a client
  # identifier while the entry lives. Keying with secret_key_base — which never
  # enters the cache — makes the bucket key non-reversible without the secret,
  # while staying stable across processes so bucketing is deterministic/distinct.
  def self.coarse_key(req)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, client_ip(req).to_s)[0, 12]
  end

  # General API throttle: 60 requests / minute / coarse-bucket.
  throttle("api/ip", limit: 60, period: 60) do |req|
    coarse_key(req) if req.path.start_with?("/api/")
  end

  # Tighter throttle on the expensive routing endpoint.
  throttle("routes/ip", limit: 20, period: 60) do |req|
    coarse_key(req) if req.path == "/api/v1/routes" && req.post?
  end

  self.throttled_responder = lambda do |_req|
    [ 429, { "Content-Type" => "application/json" },
     [ { code: "rate_limited", message: "Too many requests. Please slow down." }.to_json ] ]
  end
end
