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
end
