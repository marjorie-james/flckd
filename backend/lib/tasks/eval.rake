namespace :eval do
  # Measures the camera-avoidance success rate (SC-001) and server-side route
  # latency (SC-004) over a fixed set of Iowa city origin/destination pairs.
  #
  # Requires the LIVE geo stack (Valhalla + seeded cameras/coverage) — it is an
  # ops/eval harness, not a deterministic unit test:
  #   docker compose -f infra/docker-compose.yml up -d postgres routing backend
  #   docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=development backend bin/rails db:seed
  #   docker compose -f infra/docker-compose.yml run --rm -e RAILS_ENV=development backend bin/rails eval:routes

  desc "Evaluate avoidance success (SC-001) + plan latency (SC-004) over Iowa O/D pairs"
  task routes: :environment do
    cities = {
      "Des Moines" => [ 41.5868, -93.6250 ],
      "Iowa City" => [ 41.6611, -91.5302 ],
      "Cedar Rapids" => [ 41.9779, -91.6656 ],
      "Davenport" => [ 41.5236, -90.5776 ],
      "Ames" => [ 42.0347, -93.6199 ],
      "Waterloo" => [ 42.4928, -92.3426 ],
      "Council Bluffs" => [ 41.2619, -95.8608 ],
      "Dubuque" => [ 42.5006, -90.6646 ]
    }

    planner = Routing::RoutePlanner.new
    durations = []
    rows = []

    cities.keys.combination(2).each do |a, b|
      origin = { lat: cities[a][0], lng: cities[a][1] }
      dest   = { lat: cities[b][0], lng: cities[b][1] }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      avoid = planner.plan(origin: origin, destination: dest)
      durations << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)

      passed = avoid.fastest_comparison[:cameras_passed_count] # cameras the fastest route drives past
      next unless passed.positive?            # only pairs where avoidance is actually needed

      rows << { pair: "#{a} → #{b}", passed: passed, clean: avoid.is_fully_clean,
                avoided: avoid.cameras_avoided_count }
    rescue Geo::HttpClient::ServiceError => e
      warn "  skipped #{a} → #{b}: #{e.message}"
    end

    needing = rows.size
    clean = rows.count { |r| r[:clean] }
    p95 = percentile(durations, 95)

    puts "\n== Route eval (#{durations.size} O/D pairs) =="
    puts "SC-001  camera-free route when avoidance is needed: " \
         "#{needing.zero? ? 'n/a (no camera-crossing pairs in this dataset)' : "#{clean}/#{needing} = #{(100.0 * clean / needing).round(1)}%"}"
    puts "SC-004  server-side plan latency p95: #{(p95 * 1000).round(1)} ms (budget 2000 ms)"
    puts "\nPairs needing avoidance:"
    rows.each { |r| puts "  #{r[:pair]}: fastest passes #{r[:passed]} camera(s), avoid clean=#{r[:clean]} (avoided #{r[:avoided]})" }
    puts "  (none — seed more cameras on inter-city corridors to exercise SC-001)" if rows.empty?
  end

  # Nearest-rank percentile of an array of numbers.
  def percentile(values, pct)
    return 0.0 if values.empty?

    sorted = values.sort
    sorted[[ (pct / 100.0 * sorted.length).ceil - 1, 0 ].max]
  end
end
