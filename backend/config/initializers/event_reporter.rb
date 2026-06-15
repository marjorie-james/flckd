# Observability for route/geocode latency (Constitution Principle IV).
#
# Subscribes to the controller processing notification and emits a structured
# latency event for each API request. ANONYMITY: only the controller, action,
# HTTP status, and timings are reported — never params, query strings, request
# bodies, or client IPs, so no origin/destination/route coordinate can leak into
# observability (FR-011, FR-012a). This complements the log redaction in
# config/initializers/anonymity_logging.rb.
#
# Uses Rails' structured event reporter (Rails.event, Rails 8.1) when available,
# falling back to a structured log line so the initializer is boot-safe on any
# 8.1.x patch.
ActiveSupport::Notifications.subscribe("process_action.action_controller") do |event|
  payload = event.payload
  controller = payload[:controller].to_s
  next unless controller.start_with?("Api::V1::")

  data = {
    name: "api.request",
    controller: controller,
    action: payload[:action],
    status: payload[:status],
    duration_ms: event.duration.round(1),
    db_ms: payload[:db_runtime]&.round(1),
    view_ms: payload[:view_runtime]&.round(1)
  }.compact

  if defined?(Rails.event) && Rails.event.respond_to?(:notify)
    Rails.event.notify("api.request", data)
  else
    Rails.logger.info(data.to_json)
  end
end
