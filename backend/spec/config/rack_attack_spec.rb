require "rails_helper"

# M3: the throttle bucket must be keyed on the real client IP recovered through the
# proxy, not Rack::Request#ip (which would be the proxy's own IP behind Kamal/Thruster).
RSpec.describe "Rack::Attack#coarse_key" do
  def request_with(remote_addr:, forwarded: nil)
    env = Rack::MockRequest.env_for("/api/v1/routes", "REQUEST_METHOD" => "POST", "REMOTE_ADDR" => remote_addr)
    env["HTTP_X_FORWARDED_FOR"] = forwarded if forwarded
    Rack::Request.new(env)
  end

  let(:proxy) { "10.0.0.5" } # a trusted, private-range reverse proxy

  it "buckets two distinct clients behind the same proxy separately" do
    a = Rack::Attack.coarse_key(request_with(remote_addr: proxy, forwarded: "203.0.113.7"))
    b = Rack::Attack.coarse_key(request_with(remote_addr: proxy, forwarded: "198.51.100.9"))
    expect(a).not_to eq(b)
  end

  it "buckets the same client deterministically" do
    a = Rack::Attack.coarse_key(request_with(remote_addr: proxy, forwarded: "203.0.113.7"))
    b = Rack::Attack.coarse_key(request_with(remote_addr: proxy, forwarded: "203.0.113.7"))
    expect(a).to eq(b)
  end

  it "does not key on the proxy's own IP (which would collapse all clients)" do
    client = Rack::Attack.coarse_key(request_with(remote_addr: proxy, forwarded: "203.0.113.7"))
    proxy_only = Rack::Attack.coarse_key(request_with(remote_addr: proxy))
    expect(client).not_to eq(proxy_only)
  end

  # The bucket key is an HMAC of the client IP keyed with secret_key_base, not a
  # plain digest: a plain SHA256 of an IP is brute-forceable across the ~4.3B
  # IPv4 space, recovering a client identifier while the entry lives. Keying with
  # a secret that never enters the cache makes the bucket key non-reversible.
  describe "secret-keyed (non-reversible) bucketing" do
    let(:ip) { "203.0.113.7" }
    let(:digest) { ->(secret) { OpenSSL::HMAC.hexdigest("SHA256", secret, ip)[0, 12] } }

    it "produces equal keys for the same IP and secret (stable across processes)" do
      expect(digest.call("secret-base")).to eq(digest.call("secret-base"))
    end

    it "produces different keys for the same IP under a different secret" do
      expect(digest.call("secret-base")).not_to eq(digest.call("other-secret-base"))
    end

    it "keys coarse_key with the application's secret_key_base" do
      expected = OpenSSL::HMAC.hexdigest(
        "SHA256", Rails.application.secret_key_base, "203.0.113.7"
      )[0, 12]
      key = Rack::Attack.coarse_key(request_with(remote_addr: proxy, forwarded: "203.0.113.7"))
      expect(key).to eq(expected)
    end
  end
end
