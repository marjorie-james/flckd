# Make `travel_to` / `freeze_time` available in specs that assert time-dependent
# behavior (freshness stamping, stale auto-retire windows, scheduled refresh).
RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
end
