require "rails_helper"

RSpec.describe MonitoredSegment, type: :model do
  it "is valid with a camera, way id, and geometry" do
    expect(build(:monitored_segment)).to be_valid
  end

  it "allows the same camera to monitor different OSM ways (opposing carriageways)" do
    camera = create(:camera)
    create(:monitored_segment, camera: camera, osm_way_id: 100)

    expect { create(:monitored_segment, camera: camera, osm_way_id: 200) }.not_to raise_error
    expect(camera.monitored_segments.count).to eq(2)
  end

  it "rejects a duplicate (camera, osm_way_id) at the database level" do
    camera = create(:camera)
    create(:monitored_segment, camera: camera, osm_way_id: 100)

    expect { create(:monitored_segment, camera: camera, osm_way_id: 100) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it ".for_routing only includes segments of routable cameras" do
    keep = create(:monitored_segment, camera: create(:camera, confidence: 0.9))
    create(:monitored_segment, camera: create(:camera, :removed))
    create(:monitored_segment, camera: create(:camera, confidence: 0.1))

    expect(MonitoredSegment.for_routing(0.5)).to contain_exactly(keep)
  end
end
