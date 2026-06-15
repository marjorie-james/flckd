require "rails_helper"
require "fugit"

# The daily camera refresh must fire at a fixed 08:00 UTC (= 2am CST / 3am CDT),
# not adjusted for daylight saving (spec clarification + FR-010 / SC-006).
RSpec.describe "camera data refresh schedule (config/recurring.yml)" do
  let(:config) { YAML.load_file(Rails.root.join("config/recurring.yml")) }
  let(:entry) { config.dig("production", "camera_data_refresh") }

  it "runs DataRefreshJob in aggregate mode" do
    expect(entry["class"]).to eq("DataRefreshJob")
    expect(entry["args"]).to eq([ "aggregate" ])
  end

  it "is a fixed 08:00 UTC daily cron" do
    cron = Fugit::Cron.parse(entry["schedule"])
    expect(cron).not_to be_nil
    expect(cron.hours).to eq([ 8 ])
    expect(cron.minutes).to eq([ 0 ])
  end
end
