require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # ActiveStorage is not loaded (engine removed in application.rb — M5 remediation).
  # config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default file cache store with Solid Cache on the dedicated `cache`
  # database (see config/cache.yml and the create_solid_cache_entries migration in
  # db/cache_migrate). This is durable and SHARED across Kamal containers, which is
  # what Rack::Attack's throttle counters need to aggregate cluster-wide rather than
  # counting per-container in a process-local store.
  config.cache_store = :solid_cache_store

  # Durable Active Job backend: Solid Queue, on the primary database (no dedicated
  # queue DB — see config/queue.yml and the create_solid_queue_tables migration).
  config.active_job.queue_adapter = :solid_queue

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Spoof-resistant client IP + Host validation at the app layer (defense in depth
  # behind the Kamal/Thruster edge). Both are wired from the environment so the
  # deployment topology is not hardcoded; when the vars are unset the behavior is
  # unchanged (empty allow-lists), preserving the prior deploy-contract-only model.
  require_relative "../../lib/edge_config"

  # TRUSTED_PROXIES (e.g. "10.0.0.0/8, 172.16.0.0/12"): CIDRs of our reverse-proxy
  # tier. ActionDispatch::RemoteIp strips these from X-Forwarded-For so an
  # anonymous client cannot forge its throttle-bucket identity by appending fake
  # XFF hops (finding M1).
  #
  # IMPORTANT: assigning config.action_dispatch.trusted_proxies REPLACES Rails'
  # built-in trusted ranges (loopback + RFC1918) rather than extending them (see
  # ActionDispatch::RemoteIp#initialize). We prepend the defaults so the
  # Thruster/Kamal loopback hop stays trusted; otherwise remote_ip could resolve
  # to the proxy or raise IpSpoofAttackError.
  trusted_proxies = EdgeConfig.trusted_proxies
  if trusted_proxies.any?
    config.action_dispatch.trusted_proxies =
      ActionDispatch::RemoteIp::TRUSTED_PROXIES + trusted_proxies
  end

  # DNS-rebinding / Host-header protection — fail closed. APP_HOSTS (comma-
  # separated) or API_DOMAIN must be set; the /up health check stays excluded so
  # load-balancer probes are never rejected. RAILS_ENV_SKIP_HOST_CHECK is the
  # escape hatch for CI/staging environments that legitimately lack a domain.
  allowed_hosts = EdgeConfig.allowed_hosts
  if allowed_hosts.any?
    config.hosts = allowed_hosts
    config.host_authorization = { exclude: ->(request) { request.path.in?(%w[/up /api/v1/health]) } }
  else
    raise "APP_HOSTS or API_DOMAIN must be set in production" unless ENV["RAILS_ENV_SKIP_HOST_CHECK"]
  end
end
