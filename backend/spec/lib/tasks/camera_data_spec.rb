require "rails_helper"
require "rake"

# Guards the regression where a rate-limited / unreachable Overpass run was
# isolated by AggregateImport (status "failed") but the rake task still exited 0
# — so the setup script printed "Real cameras imported" while only the 5 demo
# fixtures remained. The import must exit non-zero on a non-success run.
RSpec.describe "camera_data:import rake task" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment) # no-op; Rails is already loaded
    load Rails.root.join("lib/tasks/camera_data.rake").to_s
  end

  after { Rake::Task["camera_data:import"].reenable }

  around do |example|
    original = ENV.to_hash.slice("SOURCE", "BBOX")
    ENV["SOURCE"] = "overpass"
    ENV["BBOX"]   = "40.3,-96.7,43.6,-90.0"
    example.run
  ensure
    %w[SOURCE BBOX].each { |k| ENV.delete(k) }
    original.each { |k, v| ENV[k] = v }
  end

  def aggregate_result(status:, added: 0)
    CameraData::AggregateImport::Result.new(
      per_source: { "OpenStreetMap" => { "status" => status, "added" => added, "updated" => 0, "skipped" => 0 } },
      totals: { "added" => added, "updated" => 0, "skipped" => 0 },
      snapped_total: 0,
      status: status
    )
  end

  before do
    # Keep the task off the network: the road lookup is built but unused once the
    # importer is stubbed.
    allow(CameraData::ValhallaRoadLookup).to receive(:new)
      .and_return(instance_double(CameraData::ValhallaRoadLookup))
  end

  it "exits non-zero when the Overpass source fails (no false 'imported')" do
    importer = instance_double(CameraData::AggregateImport, call: aggregate_result(status: "failed"))
    allow(CameraData::AggregateImport).to receive(:new).and_return(importer)

    expect { Rake::Task["camera_data:import"].invoke }.to raise_error(SystemExit)
  end

  it "completes without aborting when the import succeeds" do
    importer = instance_double(CameraData::AggregateImport, call: aggregate_result(status: "success", added: 1_099))
    allow(CameraData::AggregateImport).to receive(:new).and_return(importer)

    expect { Rake::Task["camera_data:import"].invoke }.not_to raise_error
  end

  it "imports from the local PBF extract (no Overpass) when SOURCE=pbf" do
    ENV["SOURCE"] = "pbf" # the rate-limit-free default substrate (ADR 0002)
    allow(CameraData::Sources::OsmExtractFile).to receive(:new)
      .and_return(instance_double(CameraData::Sources::OsmExtractFile))
    importer = instance_double(CameraData::AggregateImport, call: aggregate_result(status: "success", added: 717))
    allow(CameraData::AggregateImport).to receive(:new).and_return(importer)

    expect { Rake::Task["camera_data:import"].invoke }.not_to raise_error
    expect(CameraData::Sources::OsmExtractFile).to have_received(:new)
  end
end
