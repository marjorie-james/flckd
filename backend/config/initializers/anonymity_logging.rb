# Anonymity: keep route coordinates, addresses, and client IPs out of the logs
# (FR-011, SC-008). Three layers:
#   1. filter_parameters redacts geo params from Rails' parameter logging.
#   2. A request-logger subclass strips the client IP from the "Started" line,
#      and the request tags omit :ip / :remote_ip.
#   3. A formatter scrubs any lat/lng-looking coordinate that slips through.
#
# Combined with the stateless, account-less design, this ensures a completed
# request leaves no log record linking an origin/destination to a user.

# 1. Redact geo-bearing params anywhere in the parameter tree.
Rails.application.config.filter_parameters += %i[
  origin destination lat lng coordinate bbox q address
]

# 2. Strip the client IP from request logs. Rails::Rack::Logger's "Started" line
#    interpolates request.remote_ip ("Started GET \"/path\" for 203.0.113.4 at …"),
#    which the param filter and the coordinate scrubber below do NOT cover. We
#    subclass it to drop the "for <ip>" token (everything else — request-id
#    tagging, timing — is inherited unchanged) and swap it into the stack. The
#    `:request_id` tag still applies; we never tag with :ip / :remote_ip.
class AnonymousRackLogger < Rails::Rack::Logger
  # Reuse the parent's message, then excise the " for <ip>" segment so no client
  # IP is ever written, regardless of the surrounding format/time representation.
  def started_request_message(request)
    super.sub(/ for \S+ at /, " at ")
  end
end

Rails.application.config.log_tags = [ :request_id ]
Rails.application.config.middleware.swap(
  Rails::Rack::Logger, AnonymousRackLogger, Rails.application.config.log_tags
)

# 3. Belt-and-suspenders: scrub any lat/lng-looking coordinate that slips into a
#    log line (e.g. from a backtrace or a stray `logger.info`) before it is
#    written.
#
#    This MUST happen in the formatter — the single chokepoint every log line
#    passes through after `Logger#add` has resolved which argument actually
#    carries the message. Overriding `Logger#add` instead (the previous
#    approach) silently missed the common cases: `logger.info("…")` passes the
#    string as `progname` (not `message`), `logger.info { "…" }` passes it via a
#    block, and on Rails 8 `Rails.logger` is a BroadcastLogger whose severity
#    methods fan out to sink loggers without calling its own `add` at all.
module AnonymityLogScrubber
  COORD = /-?\d{1,3}\.\d{3,}/ # 3+ decimal places ~ a precise coordinate
  REPLACEMENT = "[redacted-coord]"

  def self.scrub(string)
    string.is_a?(String) ? string.gsub(COORD, REPLACEMENT) : string
  end

  # Wraps an existing log formatter, scrubbing the fully-rendered line so every
  # logging form is covered regardless of how the message was passed. Delegates
  # everything else (e.g. TaggedLogging's tag bookkeeping) to the inner
  # formatter so tagged logging keeps working.
  class Formatter
    def initialize(inner)
      @inner = inner || ::Logger::Formatter.new
    end

    def call(severity, time, progname, msg)
      AnonymityLogScrubber.scrub(@inner.call(severity, time, progname, msg))
    end

    def method_missing(name, *args, &block)
      @inner.respond_to?(name) ? @inner.public_send(name, *args, &block) : super
    end

    def respond_to_missing?(name, include_private = false)
      @inner.respond_to?(name, include_private) || super
    end
  end
end

# Apply to every underlying logger. A BroadcastLogger fans out to several sinks
# (e.g. STDOUT + file), each with its own formatter, so wrap them all.
scrubber_targets =
  if Rails.logger.respond_to?(:broadcasts)
    Rails.logger.broadcasts
  else
    [ Rails.logger ]
  end

scrubber_targets.each do |logger|
  next unless logger.respond_to?(:formatter) && logger.respond_to?(:formatter=)
  next if logger.formatter.is_a?(AnonymityLogScrubber::Formatter) # idempotent

  logger.formatter = AnonymityLogScrubber::Formatter.new(logger.formatter)
end
