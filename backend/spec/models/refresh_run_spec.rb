require "rails_helper"

RSpec.describe RefreshRun do
  it "defaults status to running" do
    run = RefreshRun.create!(trigger: "scheduled", started_at: Time.current)
    expect(run.status).to eq("running")
  end

  it "validates trigger and status inclusion and started_at presence" do
    expect(RefreshRun.new(trigger: "nope", status: "running", started_at: Time.current)).not_to be_valid
    expect(RefreshRun.new(trigger: "manual", status: "bogus", started_at: Time.current)).not_to be_valid
    expect(RefreshRun.new(trigger: "manual", status: "success")).not_to be_valid
    expect(RefreshRun.new(trigger: "manual", status: "success", started_at: Time.current)).to be_valid
  end

  describe ".running?" do
    it "is true while a run is in progress and false otherwise" do
      expect(RefreshRun.running?).to be(false)
      run = RefreshRun.create!(trigger: "scheduled", started_at: Time.current)
      expect(RefreshRun.running?).to be(true)
      run.update!(status: "success", finished_at: Time.current)
      expect(RefreshRun.running?).to be(false)
    end
  end

  it "stores per_source and totals as structured data" do
    run = RefreshRun.create!(
      trigger: "manual", status: "success", started_at: Time.current,
      per_source: { "OpenStreetMap" => { "added" => 1, "status" => "success" } },
      totals: { "added" => 1, "updated" => 0, "skipped" => 0, "retired" => 0 }
    )
    expect(run.reload.per_source["OpenStreetMap"]["added"]).to eq(1)
    expect(run.totals["added"]).to eq(1)
  end
end
