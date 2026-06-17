require "rails_helper"

RSpec.describe Routing::RoutePlanner do
  let(:origin) { { lat: 39.7392, lng: -104.9903 } }
  let(:destination) { { lat: 39.7294, lng: -104.8319 } }

  # Stub exclusion builder: pretend the given segments are in the bbox, and hand
  # back a non-empty (shape-irrelevant) ring for any subset the planner excludes.
  def exclusion_with(segments)
    instance_double(Routing::SegmentExclusionBuilder,
                    segments_in_bbox: segments,
                    rings_for: [ [ [ 0.0, 0.0 ] ] ])
  end

  # Planner wired with injected fakes: a detector keyed on route geometry and a
  # proximity scorer keyed on geometry — so the prefer-clean / minimum-exposure
  # selection is fully deterministic.
  def planner(engine, segments:, passes: {}, costs: {})
    described_class.new(routing_client: engine,
                        exclusion_builder: exclusion_with(segments),
                        detector: GeoFakes::FakeDetector.new(passes),
                        proximity_scorer: GeoFakes::FakeProximityScorer.new(costs))
  end

  let(:fastest) { sample_route(distance_m: 5_000, duration_s: 600, geometry: "FAST") }

  describe "selection objective (time vs exposure)" do
    it "returns the fastest route, fully clean, when it passes no cameras" do
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest)

      result = planner(engine, segments: [], passes: { "FAST" => [] })
               .plan(origin: origin, destination: destination)

      expect(result.is_fully_clean).to be(true)
      expect(result.distance_m).to eq(5_000)
      expect(result.cameras_avoided_count).to eq(0)
      expect(engine.exclude_calls).to eq(0) # no avoidance attempted
    end

    it "picks the lower-exposure reroute when the detour is worth it" do
      a, b = build_stubbed_list(:monitored_segment, 2)
      clean = sample_route(distance_m: 6_000, duration_s: 800, geometry: "CLEAN")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: clean, quiet: clean)

      # Fastest hugs both cameras (proximity 10); excluding them is fully clean
      # (proximity 0) for only +200s — at λ=90 it is a clear win.
      result = planner(engine, segments: [ a, b ],
                               passes: { "FAST" => [ a, b ], "CLEAN" => [] },
                               costs: { "FAST" => 10.0, "CLEAN" => 0.0 })
               .plan(origin: origin, destination: destination)

      expect(result.distance_m).to eq(6_000)        # the avoiding route, not the fastest
      expect(result.is_fully_clean).to be(true)
      expect(result.cameras_avoided_count).to eq(2)
      expect(result.remaining_cameras).to be_empty
    end

    it "rejects a pathological detour that barely lowers exposure at a big time cost" do
      segs = build_stubbed_list(:monitored_segment, 5)
      a, b, c, = segs
      # Excluding the arterials reroutes onto a long loop that only drops on-segment
      # 5 -> 3 and proximity 9 -> 6, at double the time. Not worth it at λ=90: the
      # planner keeps the fastest route (minimum exposure, no silly loop).
      loop_route = sample_route(distance_m: 13_000, duration_s: 1_200, geometry: "LOOP")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: loop_route, quiet: fastest)

      result = planner(engine, segments: segs,
                               passes: { "FAST" => segs, "LOOP" => [ a, b, c ] },
                               costs: { "FAST" => 9.0, "LOOP" => 6.0 })
               .plan(origin: origin, destination: destination)

      expect(result.distance_m).to eq(5_000)        # the fastest route
      expect(result.cameras_avoided_count).to eq(0)
      expect(result.remaining_cameras.size).to eq(5)
    end

    it "prefers a fully-clean detour over the fastest route that passes a camera" do
      a = build_stubbed(:monitored_segment)
      avoid = sample_route(distance_m: 6_000, duration_s: 800, geometry: "AVOID")
      # The fastest route passes the camera; the avoiding route is fully clean for
      # +200s. A clean route is always preferred, so it's taken.
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: avoid, quiet: fastest)

      result = planner(engine, segments: [ a ],
                               passes: { "FAST" => [ a ], "AVOID" => [] },
                               costs: { "FAST" => 4.0, "AVOID" => 0.0 })
               .plan(origin: origin, destination: destination)

      expect(result.distance_m).to eq(6_000) # the clean avoiding route
      expect(result.is_fully_clean).to be(true)
      expect(result.cameras_avoided_count).to eq(1)
    end

    it "can pick the quiet (surface-street) candidate when it scores best" do
      a, b = build_stubbed_list(:monitored_segment, 2)
      excl = sample_route(distance_m: 9_000, duration_s: 900, geometry: "EXCL")
      quiet = sample_route(distance_m: 7_000, duration_s: 700, geometry: "QUIET")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: excl, quiet: quiet)

      # Quiet is cheaper (700s) AND lowest exposure (proximity 1, passes none) — it
      # wins over both the fastest (proximity 8) and the costly exclusion route.
      result = planner(engine, segments: [ a, b ],
                               passes: { "FAST" => [ a, b ], "EXCL" => [ a ], "QUIET" => [] },
                               costs: { "FAST" => 8.0, "EXCL" => 4.0, "QUIET" => 1.0 })
               .plan(origin: origin, destination: destination)

      expect(result.distance_m).to eq(7_000)
      expect(result.is_fully_clean).to be(true)
      expect(result.cameras_avoided_count).to eq(2)
    end

    it "drops an absurd-time minimum-exposure detour past the cap, keeping the fastest" do
      a, b = build_stubbed_list(:monitored_segment, 2)
      # No fully-clean route exists. The lower-exposure detour (passes only b) takes
      # 3.3x the fastest's time — beyond MAX_DETOUR_RATIO — so it's dropped and the
      # fastest route stands as minimum exposure.
      far = sample_route(distance_m: 30_000, duration_s: 2_000, geometry: "FAR")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: far, quiet: fastest)

      result = planner(engine, segments: [ a, b ],
                               passes: { "FAST" => [ a, b ], "FAR" => [ b ] },
                               costs: { "FAST" => 8.0, "FAR" => 2.0 })
               .plan(origin: origin, destination: destination)

      expect(result.distance_m).to eq(5_000)
      expect(result.is_fully_clean).to be(false)
      expect(result.remaining_cameras.size).to eq(2)
    end
  end

  describe "prefer-clean then minimum-exposure fallback" do
    it "returns a fully-clean route when one exists, whatever the detour costs" do
      a, b = build_stubbed_list(:monitored_segment, 2)
      clean = sample_route(distance_m: 9_000, duration_s: 2_500, geometry: "CLEAN") # ~4x fastest: no cap on a clean route
      near = sample_route(distance_m: 6_000, duration_s: 650, geometry: "NEAR")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: clean, quiet: near)

      result = planner(engine, segments: [ a, b ],
                               passes: { "FAST" => [ a, b ], "CLEAN" => [], "NEAR" => [ a ] })
               .plan(origin: origin, destination: destination)

      expect(result.is_fully_clean).to be(true)
      expect(result.distance_m).to eq(9_000)        # the fully-clean route, despite the cost
      expect(result.cameras_avoided_count).to eq(2)
      expect(result.remaining_cameras).to be_empty
    end

    it "falls back to the fewest-cameras route when none avoids every camera" do
      a, b, c = build_stubbed_list(:monitored_segment, 3)
      # No candidate is fully clean. MIN passes only camera c (the fewest) and is the
      # least-exposed by proximity, so the planner returns it rather than failing.
      min = sample_route(distance_m: 8_000, duration_s: 1_100, geometry: "MIN")
      near = sample_route(distance_m: 7_000, duration_s: 800, geometry: "NEAR")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: min, quiet: near)

      result = planner(engine, segments: [ a, b, c ],
                               passes: { "FAST" => [ a, b, c ], "MIN" => [ c ], "NEAR" => [ b, c ] },
                               costs: { "FAST" => 9.0, "MIN" => 1.0, "NEAR" => 5.0 })
               .plan(origin: origin, destination: destination)

      expect(result.is_fully_clean).to be(false)
      expect(result.distance_m).to eq(8_000)        # the minimum-exposure route
      expect(result.cameras_avoided_count).to eq(2) # avoided a and b; c is unavoidable
      expect(result.remaining_cameras).to eq([ { osm_way_id: c.osm_way_id } ])
    end
  end

  describe "minimum-exposure exclusion generator" do
    it "avoids the feasible subset when excluding all passed segments at once is impossible" do
      a, b = build_stubbed_list(:monitored_segment, 2)
      mid = sample_route(distance_m: 7_500, duration_s: 700, geometry: "MID")
      # FAST passes {a,b}. Excluding both at once has no path (call 1 raises), and
      # excluding b alone is impossible too — but excluding a reroutes to MID (still
      # passing b). MID hugs far fewer cameras (proximity 3 vs 10) for only +100s, so
      # it's chosen.
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: [ :raise, mid, :raise ], quiet: fastest)

      result = planner(engine, segments: [ a, b ],
                               passes: { "FAST" => [ a, b ], "MID" => [ b ] },
                               costs: { "FAST" => 10.0, "MID" => 3.0 })
               .plan(origin: origin, destination: destination)

      expect(result.is_fully_clean).to be(false)
      expect(result.distance_m).to eq(7_500)         # the feasible reroute
      expect(result.cameras_avoided_count).to eq(1)  # avoided a; b is unavoidable
      expect(result.remaining_cameras).to eq([ { osm_way_id: b.osm_way_id } ])
      expect(engine.exclude_calls).to eq(3)          # {a,b} fails, {a} routes, {a,b} fails again
    end

    it "keeps trying avoidable segments past the first fan-out batch across passes" do
      # FAST passes 9 cameras — one more than FALLBACK_FANOUT_LIMIT (8). Excluding
      # them all at once is infeasible, and each of the first 8 is individually
      # unavoidable too; only the 9th is excludable. The fallback fan-out is capped
      # at 8 per pass, so the 9th is reached only on a *later* pass — which it must
      # be (the bug: `break unless progressed` abandoned the whole avoid loop after
      # the first all-unavoidable batch, returning the fastest route unchanged).
      segs = build_stubbed_list(:monitored_segment, 9)
      last = segs.last
      clean = sample_route(distance_m: 6_000, duration_s: 800, geometry: "CLEAN")

      # Call sequence across reroutes:
      #   pass 1: exclude-all (1, fails) + first-8 one-at-a-time (8, all fail) = 9 :raise
      #   pass 2: exclude the lone remaining 9th segment -> CLEAN
      avoiding = ([ :raise ] * 9) + [ clean ]
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: avoiding, quiet: fastest)

      result = planner(engine, segments: segs,
                               passes: { "FAST" => segs, "CLEAN" => [] },
                               costs: { "FAST" => 10.0, "CLEAN" => 0.0 })
               .plan(origin: origin, destination: destination)

      expect(result.distance_m).to eq(6_000)        # the later-pass avoiding route, not the fastest
      expect(result.is_fully_clean).to be(true)
      expect(result.cameras_avoided_count).to eq(9) # excluding seg 9 reroutes clear of all 9
      expect(result.remaining_cameras).to be_empty
      expect(engine.exclude_calls).to eq(10)        # 9 infeasible attempts, then the clean reroute
      expect(engine.last_exclude_polygons).not_to be_empty # the final reroute excluded the 9th
      expect(last.osm_way_id).to be_present          # (the 9th camera is the one that unlocks avoidance)
    end

    it "falls back to the fastest route when every exclusion is impossible" do
      segs = build_stubbed_list(:monitored_segment, 3)
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, raise_on_exclude: true, quiet: fastest)

      result = planner(engine, segments: segs, passes: { "FAST" => segs },
                               costs: { "FAST" => 9.0 })
               .plan(origin: origin, destination: destination)

      expect(result.is_fully_clean).to be(false)
      expect(result.distance_m).to eq(5_000)
      expect(result.cameras_avoided_count).to eq(0)
      expect(result.remaining_cameras.size).to eq(3)
    end
  end

  describe "fastest comparison + result shape" do
    it "surfaces the fastest route's geometry, cameras passed, and a non-negative added cost" do
      a, b = build_stubbed_list(:monitored_segment, 2)
      clean = sample_route(distance_m: 6_500, duration_s: 900, geometry: "CLEAN")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: clean, quiet: clean)

      result = planner(engine, segments: [ a, b ],
                               passes: { "FAST" => [ a, b ], "CLEAN" => [] },
                               costs: { "FAST" => 12.0, "CLEAN" => 0.0 })
               .plan(origin: origin, destination: destination)

      fc = result.fastest_comparison
      expect(fc[:geometry]).to eq("FAST")
      expect(fc[:cameras_passed_count]).to eq(2)
      expect(fc[:added_duration_s]).to eq(300) # 900 - 600
      expect(fc[:added_distance_m]).to eq(1_500)
      expect(fc[:added_duration_s]).to be >= 0
      expect(fc[:added_distance_m]).to be >= 0
    end

    it "reports zero added cost and the fastest geometry when avoidance falls back" do
      segs = build_stubbed_list(:monitored_segment, 3)
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, raise_on_exclude: true, quiet: fastest)

      result = planner(engine, segments: segs, passes: { "FAST" => segs }, costs: { "FAST" => 9.0 })
               .plan(origin: origin, destination: destination)

      fc = result.fastest_comparison
      expect(fc[:added_duration_s]).to eq(0)
      expect(fc[:added_distance_m]).to eq(0)
      expect(fc[:geometry]).to eq(result.geometry) # chosen route IS the fastest route
    end

    it "counts distinct cameras, not segments, when one camera owns several segments" do
      cam = build_stubbed(:camera)
      s1 = build_stubbed(:monitored_segment, camera: cam)
      s2 = build_stubbed(:monitored_segment, camera: cam) # same camera, second segment
      clean = sample_route(distance_m: 6_000, duration_s: 800, geometry: "CLEAN")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: clean, quiet: clean)

      result = planner(engine, segments: [ s1, s2 ],
                               passes: { "FAST" => [ s1, s2 ], "CLEAN" => [] },
                               costs: { "FAST" => 10.0, "CLEAN" => 0.0 })
               .plan(origin: origin, destination: destination)

      expect(result.fastest_comparison[:cameras_passed_count]).to eq(1) # one camera, not two segments
      expect(result.cameras_avoided_count).to eq(1)
    end

    it "never reports a negative added distance when the avoiding route is shorter" do
      a = build_stubbed(:monitored_segment)
      # The chosen avoiding route is longer in time (+200s) but SHORTER in distance.
      shorter = sample_route(distance_m: 4_000, duration_s: 800, geometry: "SHORT")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: shorter, quiet: shorter)

      result = planner(engine, segments: [ a ], passes: { "FAST" => [ a ], "SHORT" => [] },
                               costs: { "FAST" => 10.0, "SHORT" => 0.0 })
               .plan(origin: origin, destination: destination)

      expect(result.distance_m).to eq(4_000)
      expect(result.fastest_comparison[:added_distance_m]).to eq(0) # clamped, not -1000
    end

    it "localizes maneuvers" do
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest)
      result = planner(engine, segments: [], passes: { "FAST" => [] })
               .plan(origin: origin, destination: destination, locale: "en")

      expect(result.maneuvers.first).to include(:localized_text, :type, :distance_m)
    end
  end

  describe "wall-clock deadline" do
    it "returns the best route so far without running the avoid fan-out once the budget is spent" do
      a = build_stubbed(:monitored_segment)
      avoid = sample_route(distance_m: 6_000, duration_s: 800, geometry: "AVOID")
      engine = GeoFakes::FakeRoutingEngine.new(fastest: fastest, avoiding: avoid, quiet: avoid)

      # With a normal budget this O/D yields the fully-clean AVOID route; an
      # already-exceeded deadline must short-circuit to the fastest route and make
      # zero avoidance reroutes (no thread-pinning fan-out under a slow engine).
      result = planner(engine, segments: [ a ], passes: { "FAST" => [ a ], "AVOID" => [] })
               .plan(origin: origin, destination: destination, deadline_s: -1)

      expect(result.distance_m).to eq(5_000) # the fastest route
      expect(engine.exclude_calls).to eq(0)  # no avoidance attempted
    end
  end
end
