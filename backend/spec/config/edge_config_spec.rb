require "rails_helper"

# EdgeConfig parses the edge-proxy network configuration used by production.rb to
# make request handling spoof-resistant: trusted_proxies (so X-Forwarded-For can't
# forge a throttle-bucket identity — finding M1) and allowed_hosts (so config.hosts
# closes the DNS-rebinding / direct-exposure gap).
RSpec.describe EdgeConfig do
  describe ".trusted_proxies" do
    it "parses a comma/whitespace separated CIDR list into IPAddr ranges" do
      env = { "TRUSTED_PROXIES" => "10.0.0.0/8, 172.16.0.0/12" }
      proxies = described_class.trusted_proxies(env)
      expect(proxies.map(&:to_s)).to eq(%w[10.0.0.0 172.16.0.0])
      expect(proxies).to all(be_a(IPAddr))
    end

    it "includes a spoofed public hop's proxy so RemoteIp can strip it" do
      env = { "TRUSTED_PROXIES" => "203.0.113.0/24" }
      proxies = described_class.trusted_proxies(env)
      expect(proxies.first.include?("203.0.113.7")).to be(true)
    end

    it "skips invalid CIDR entries rather than crashing boot" do
      env = { "TRUSTED_PROXIES" => "10.0.0.0/8, not-an-ip, 192.168.0.0/16" }
      expect(described_class.trusted_proxies(env).map(&:to_s)).to eq(%w[10.0.0.0 192.168.0.0])
    end

    it "returns an empty list when unset (preserves prior behavior)" do
      expect(described_class.trusted_proxies({})).to eq([])
    end
  end

  describe ".allowed_hosts" do
    it "parses a comma-separated host list from APP_HOSTS" do
      env = { "APP_HOSTS" => "flckd.example, www.flckd.example" }
      expect(described_class.allowed_hosts(env)).to eq(%w[flckd.example www.flckd.example])
    end

    it "falls back to the legacy single-value API_DOMAIN" do
      env = { "API_DOMAIN" => "flckd.example" }
      expect(described_class.allowed_hosts(env)).to eq(%w[flckd.example])
    end

    it "prefers APP_HOSTS over API_DOMAIN when both are set" do
      env = { "APP_HOSTS" => "a.example, b.example", "API_DOMAIN" => "legacy.example" }
      expect(described_class.allowed_hosts(env)).to eq(%w[a.example b.example])
    end

    it "returns an empty list when unset (config.hosts stays open, unchanged)" do
      expect(described_class.allowed_hosts({})).to eq([])
    end
  end
end
