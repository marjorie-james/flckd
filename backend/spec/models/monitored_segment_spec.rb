require "rails_helper"

RSpec.describe MonitoredSegment, type: :model do
  it "is valid with a camera, way id, and geometry" do
    expect(build(:monitored_segment)).to be_valid
  end

  it ".for_routing only includes segments of routable cameras" do
    keep = create(:monitored_segment, camera: create(:camera, confidence: 0.9))
    create(:monitored_segment, camera: create(:camera, :removed))
    create(:monitored_segment, camera: create(:camera, confidence: 0.1))

    expect(MonitoredSegment.for_routing(0.5)).to contain_exactly(keep)
  end
end
