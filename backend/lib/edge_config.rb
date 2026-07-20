require "ipaddr"

# Parses edge-proxy network configuration from the environment so production
# request handling is spoof-resistant WITHOUT hardcoding deployment topology.
#
# Two independent concerns, both defense-in-depth behind the Kamal/Thruster edge:
#
#   * trusted_proxies — CIDRs of the reverse-proxy tier. ActionDispatch's RemoteIp
#     strips these from X-Forwarded-For so an anonymous client cannot forge a
#     throttle-bucket identity by appending fake hops (finding M1: rate-limit
#     bypass via client-controlled X-Forwarded-For).
#
#   * allowed_hosts — the Host-header allow-list. Enabling config.hosts closes the
#     DNS-rebinding / direct-container-exposure gap (config.hosts left open).
#
# When the environment variables are unset both return empty lists, so the prior
# deploy-contract-only behavior is preserved unchanged.
module EdgeConfig
  module_function

  # CIDRs from TRUSTED_PROXIES, comma/whitespace separated, e.g.
  # "10.0.0.0/8, 172.16.0.0/12". Returns an array of IPAddr. Invalid entries are
  # skipped rather than crashing boot. Empty when unset.
  def trusted_proxies(env = ENV)
    parse_list(env["TRUSTED_PROXIES"]).filter_map do |cidr|
      IPAddr.new(cidr)
    rescue IPAddr::Error
      nil
    end
  end

  # Hostnames from APP_HOSTS (comma/whitespace separated), falling back to the
  # legacy single-value API_DOMAIN. Returns an array of strings. Empty when unset.
  def allowed_hosts(env = ENV)
    parse_list(env["APP_HOSTS"] || env["API_DOMAIN"])
  end

  def parse_list(raw)
    raw.to_s.split(/[,\s]+/).map(&:strip).reject(&:empty?)
  end
end
