require "rails_helper"

RSpec.describe Routing::ProximityScorer do
  # A polyline (precision 6) that runs along the segment below — the same fixture the
  # detector specs use, so it genuinely passes within camera-reading range.
  let(:on_segment_route) { { geometry: "_snxjAnwbggE?od@" } }
  let(:near_geometry) { "SRID=4326;LINESTRING(-104.9905 39.7392, -104.9901 39.7392)" }

  it "scores a candidate the route runs along above zero" do
    seg = create(:monitored_segment, geometry: near_geometry)
    expect(described_class.new.cost(on_segment_route, [ seg ])).to be > 0.0
  end

  it "scores zero when the candidate is well outside reading range" do
    far = create(:monitored_segment, geometry: "SRID=4326;LINESTRING(-80.0 25.0, -80.001 25.0)")
    expect(described_class.new.cost(on_segment_route, [ far ])).to eq(0.0)
  end

  it "scores higher with more nearby candidates" do
    a = create(:monitored_segment, geometry: near_geometry)
    b = create(:monitored_segment, geometry: near_geometry)
    one = described_class.new.cost(on_segment_route, [ a ])
    two = described_class.new.cost(on_segment_route, [ a, b ])
    expect(two).to be > one
  end

  it "scores only the candidate set it is given, ignoring other DB segments" do
    candidate = create(:monitored_segment, geometry: near_geometry)
    create(:monitored_segment, geometry: near_geometry) # on the same road but not a candidate
    only_candidate = described_class.new.cost(on_segment_route, [ candidate ])
    both = described_class.new.cost(on_segment_route, [ candidate, MonitoredSegment.last ])
    expect(both).to be > only_candidate
  end

  it "returns zero when there are no candidates" do
    create(:monitored_segment, geometry: near_geometry)
    expect(described_class.new.cost(on_segment_route, [])).to eq(0.0)
  end

  it "returns zero for geometry that does not decode to a line" do
    seg = create(:monitored_segment, geometry: near_geometry)
    expect(described_class.new.cost({ geometry: "" }, [ seg ])).to eq(0.0)
    expect(described_class.new.cost({ geometry: nil }, [ seg ])).to eq(0.0)
  end

  describe "directional discount" do
    # near_geometry runs E–W (bearing ~90°/270°) and on_segment_route runs along it,
    # so the route's heading is controlled by the fixture and we vary only the
    # camera's facing_direction to set the alignment.
    def cost_for_facing(facing)
      camera = create(:camera, facing_direction: facing)
      seg = create(:monitored_segment, camera: camera, geometry: near_geometry)
      described_class.new.cost(on_segment_route, [ seg ])
    end

    it "applies no discount when the camera's facing direction is unknown" do
      # Default factory camera has facing_direction = nil (omnidirectional).
      seg = create(:monitored_segment, geometry: near_geometry)
      expect(described_class.new.cost(on_segment_route, [ seg ])).to be > 0.0
    end

    it "charges full proximity when the route runs along the camera's facing axis" do
      aligned = cost_for_facing(90)   # route bearing ~90°, |cos(0)| ~ 1
      perpendicular = cost_for_facing(0) # |cos(90)| ~ 0 → floored
      expect(aligned).to be > perpendicular
    end

    it "discounts a perpendicular pass toward the floor (but never to zero)" do
      aligned = cost_for_facing(90)
      perpendicular = cost_for_facing(0)
      expect(perpendicular).to be > 0.0
      # Perpendicular cost is ~FLOOR of the aligned cost (same proximity, factor → floor).
      ratio = perpendicular / aligned
      expect(ratio).to be_within(0.05).of(described_class::DIRECTIONAL_FLOOR)
    end

    it "treats anti-aligned facing the same as aligned (axis-based |cos|)" do
      # 90° and 270° point along the same E–W axis; both are fully exposed.
      expect(cost_for_facing(270)).to be_within(0.001).of(cost_for_facing(90))
    end

    it "weights an aligned camera more than a perpendicular one in a mixed set" do
      aligned_cam = create(:camera, facing_direction: 90)
      perp_cam = create(:camera, facing_direction: 0)
      aligned_seg = create(:monitored_segment, camera: aligned_cam, geometry: near_geometry)
      perp_seg = create(:monitored_segment, camera: perp_cam, geometry: near_geometry)

      scorer = described_class.new
      expect(scorer.cost(on_segment_route, [ aligned_seg ]))
        .to be > scorer.cost(on_segment_route, [ perp_seg ])
    end
  end

  describe "#directional_factor" do
    subject(:scorer) { described_class.new }

    def factor(route_bearing, facing)
      scorer.send(:directional_factor, route_bearing, facing)
    end

    it "is 1.0 when the route runs along the facing axis (aligned or anti-aligned)" do
      expect(factor(90, 90)).to be_within(1e-9).of(1.0)
      expect(factor(90, 270)).to be_within(1e-9).of(1.0)
    end

    it "is DIRECTIONAL_FLOOR for a perpendicular pass" do
      expect(factor(90, 0)).to be_within(1e-9).of(described_class::DIRECTIONAL_FLOOR)
      expect(factor(90, 180)).to be_within(1e-9).of(described_class::DIRECTIONAL_FLOOR)
    end

    it "is 1.0 (no discount) when either bearing is unknown" do
      expect(factor(nil, 90)).to eq(1.0)
      expect(factor(90, nil)).to eq(1.0)
      expect(factor(nil, nil)).to eq(1.0)
    end
  end
end
