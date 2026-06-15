require "rails_helper"

RSpec.describe Geo::SubstrateFreshness do
  let(:routing) { instance_double(Routing::RoutingEngineClient) }

  def check(days_old:, stale_after: 30)
    allow(routing).to receive(:status)
      .and_return("tileset_last_modified" => (Time.current - days_old.days).to_i)
    described_class.new(routing: routing, stale_after_days: stale_after).check
  end

  it "reports fresh and does not alert when within the threshold" do
    expect(Telemetry).not_to receive(:alert)
    expect(check(days_old: 5).state).to eq(:fresh)
  end

  it "reports stale and alerts when the tileset exceeds the threshold" do
    expect(Telemetry).to receive(:alert)
      .with(a_string_including("stale"), hash_including(:age_days, :threshold_days))
    expect(check(days_old: 45).state).to eq(:stale)
  end

  it "alerts unknown when status lacks tileset_last_modified" do
    allow(routing).to receive(:status).and_return({})
    expect(Telemetry).to receive(:alert).with(a_string_including("unknown"))

    expect(described_class.new(routing: routing).check.state).to eq(:unknown)
  end

  it "notifies telemetry and reports unknown when routing is unreachable" do
    allow(routing).to receive(:status).and_raise(Geo::HttpClient::ServiceError, "down")
    expect(Telemetry).to receive(:notify)
      .with(an_instance_of(Geo::HttpClient::ServiceError), hash_including(:check))

    expect(described_class.new(routing: routing).check.state).to eq(:unknown)
  end
end
