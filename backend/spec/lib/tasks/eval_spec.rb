require "rails_helper"
require "rake"

# Guards the regression where eval:routes called RoutePlanner#plan with a
# `preference:` keyword removed in spec 004 — every invocation raised an
# uncaught ArgumentError (the only rescue is Geo::HttpClient::ServiceError), so
# the eval couldn't run at all. The task must drive the current
# `plan(origin:, destination:)` signature and read the fastest-route camera
# count off the avoid result's comparison.
RSpec.describe "eval:routes rake task" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment) # no-op; Rails is already loaded
    load Rails.root.join("lib/tasks/eval.rake").to_s
  end

  after { Rake::Task["eval:routes"].reenable }

  # A Routing::Result-shaped double: the task reads
  # fastest_comparison[:cameras_passed_count], is_fully_clean, and
  # cameras_avoided_count off each plan() return.
  def result_double(passed:, clean: true, avoided: 0)
    instance_double(Routing::Result,
                    fastest_comparison: { cameras_passed_count: passed },
                    is_fully_clean: clean,
                    cameras_avoided_count: avoided)
  end

  it "runs over the O/D pairs without raising (correct plan signature)" do
    planner = instance_double(Routing::RoutePlanner)
    # plan is called once per O/D pair with the current keyword signature only.
    allow(planner).to receive(:plan)
      .with(origin: kind_of(Hash), destination: kind_of(Hash))
      .and_return(result_double(passed: 2, clean: true, avoided: 2))
    allow(Routing::RoutePlanner).to receive(:new).and_return(planner)

    expect { Rake::Task["eval:routes"].invoke }.not_to raise_error
    expect(planner).to have_received(:plan).at_least(:once)
  end

  it "skips pairs whose fastest route passes no cameras (no avoidance needed)" do
    planner = instance_double(Routing::RoutePlanner)
    allow(planner).to receive(:plan).and_return(result_double(passed: 0))
    allow(Routing::RoutePlanner).to receive(:new).and_return(planner)

    expect { Rake::Task["eval:routes"].invoke }.not_to raise_error
  end

  it "tolerates a routing service error on a pair without aborting the run" do
    planner = instance_double(Routing::RoutePlanner)
    allow(planner).to receive(:plan).and_raise(Geo::HttpClient::ServiceError, "engine down")
    allow(Routing::RoutePlanner).to receive(:new).and_return(planner)

    expect { Rake::Task["eval:routes"].invoke }.not_to raise_error
  end
end
