# Rack::Attack throttle counters live in a single in-process MemoryStore for the
# whole test run (config/initializers/rack_attack.rb). Without a reset between
# examples the per-window counts ACCUMULATE across the suite — all request specs
# share the loopback IP, so a long enough run eventually trips the 60-req/minute
# throttle and an unrelated example gets a spurious 429. Clear the store before
# each example so every spec starts from a clean throttle window.
RSpec.configure do |config|
  config.before(:each) { Rack::Attack.cache.store.clear }
end
