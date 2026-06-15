# Rate limiting via rack-attack (FR — abuse protection without tracking).
#
# Anonymity note: throttle buckets are keyed on a COARSE, NON-RETAINED hash of
# the client IP held only in the cache for the rolling window, never persisted
# and never linked to route data. This bounds abuse without building a profile.
class Rack::Attack
  # Use the Rails cache (Solid Cache) for counters; entries expire with the window.
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

  # Coarse, non-identifying discriminator: a truncated digest of the client IP, so
  # the raw IP is never stored as a key.
  def self.coarse_key(req)
    Digest::SHA256.hexdigest(client_ip(req).to_s)[0, 12]
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
