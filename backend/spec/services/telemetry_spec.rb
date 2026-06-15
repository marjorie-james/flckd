require "rails_helper"

RSpec.describe Telemetry do
  around do |example|
    original = described_class.handler
    example.run
    described_class.handler = original
  end

  it "routes exceptions to the configured handler with context" do
    seen = []
    described_class.handler = ->(kind, payload, ctx) { seen << [ kind, payload, ctx ] }
    err = StandardError.new("boom")

    described_class.notify(err, source: "overpass")

    expect(seen).to eq([ [ :exception, err, { source: "overpass" } ] ])
  end

  it "routes operational alerts to the configured handler" do
    seen = []
    described_class.handler = ->(kind, payload, ctx) { seen << [ kind, payload, ctx ] }

    described_class.alert("refresh degraded", run_id: 7)

    expect(seen).to eq([ [ :message, "refresh degraded", { run_id: 7 } ] ])
  end

  it "never lets a raising handler escape to the caller" do
    described_class.handler = ->(*) { raise "tracker is down" }

    expect { described_class.notify(StandardError.new("x")) }.not_to raise_error
  end

  it "falls back to logging when no error tracker is loaded" do
    described_class.handler = described_class.default_handler

    expect(Rails.logger).to receive(:error).with(/refresh degraded/)
    described_class.alert("refresh degraded", run_id: 7)
  end
end
