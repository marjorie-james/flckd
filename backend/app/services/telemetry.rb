# Provider-agnostic error/telemetry seam. Application code reports operational
# failures here instead of binding directly to a specific SaaS, so an error
# tracker (Sentry/Honeybadger/etc.) can be wired in ONE place later without
# touching call sites. Until one is configured, failures go to the logs.
#
# ANONYMITY (Constitution / FR-012a): never pass user route data — origin,
# destination, coordinates, or client IPs — in `context`. This seam is intended
# for reference-data pipeline failures (the camera refresh), which carry no user
# data. Keep it that way.
#
# Wiring a real tracker later: define `Telemetry.handler = ->(kind, payload, ctx)`
# in an initializer, or simply load the Sentry SDK — the default handler detects
# and uses `Sentry` automatically.
module Telemetry
  module_function

  # Report an exception with optional structured context.
  def notify(error, context = {})
    dispatch(:exception, error, context)
  end

  # Report a non-exception operational alert (e.g. "refresh finished degraded").
  def alert(message, context = {})
    dispatch(:message, message, context)
  end

  def handler
    @handler ||= default_handler
  end

  # Override in an initializer to plug in a tracker; pass nil to restore default.
  def handler=(handler)
    @handler = handler
  end

  def dispatch(kind, payload, context)
    handler.call(kind, payload, context)
  rescue StandardError => e
    # Telemetry must never break or mask the caller's own flow.
    Rails.logger.error("[telemetry] handler raised #{e.class}: #{e.message}")
  end

  def default_handler
    lambda do |kind, payload, context|
      if defined?(::Sentry) && ::Sentry.respond_to?(:capture_exception)
        if kind == :exception
          ::Sentry.capture_exception(payload, extra: context)
        else
          ::Sentry.capture_message(payload.to_s, extra: context)
        end
      else
        Rails.logger.error("[telemetry] #{payload} #{context.inspect}")
      end
    end
  end
end
