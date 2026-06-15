require "rails_helper"

# The recurring schedule (config/recurring.yml) drives Solid Queue's dispatcher.
# These pin that the dev camera refresh is configured and points at a real job, so
# a typo can't silently disable scheduled refreshes locally.
RSpec.describe "config/recurring.yml" do
  let(:config) { YAML.load_file(Rails.root.join("config/recurring.yml")) }

  it "schedules the camera refresh in development against DataRefreshJob" do
    task = config.dig("development", "camera_data_refresh")
    expect(task).to include("class" => "DataRefreshJob", "args" => [ "aggregate" ])
    expect(task["schedule"]).to be_present
    expect { DataRefreshJob }.not_to raise_error # the referenced job class exists
  end

  it "keeps every scheduled task pointing at a defined job class" do
    config.values_at("development", "production").compact.each do |env_tasks|
      env_tasks.each_value do |task|
        expect(Object.const_defined?(task["class"])).to be(true), "missing job class #{task['class']}"
      end
    end
  end
end
