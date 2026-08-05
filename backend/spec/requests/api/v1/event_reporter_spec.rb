require "rails_helper"
require "stringio"

# Observability: each Api::V1 request must emit a structured latency log line
# (config/initializers/event_reporter.rb). The Rails.event branch was dead code
# (no subscriber registered), so the initializer now always writes the JSON line
# to Rails.logger directly — this guards that it actually appears.
RSpec.describe "API request latency telemetry", type: :request do
  def capture_log
    io = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(Logger.new(io))
    allow(Rails).to receive(:logger).and_return(logger)
    yield
    io.string
  end

  it "emits a structured latency line for an Api::V1 controller" do
    log = capture_log { get "/api/v1/health" }

    expect(response).to have_http_status(:ok)

    json_line = log.lines.map(&:strip).find do |line|
      line.include?(%q("name":"api.request"))
    end
    expect(json_line).not_to be_nil, "expected a structured api.request log line"

    # The logger prepends a severity/timestamp tag (e.g. "I, [..] INFO -- : ")
    # before the payload, so parse from the start of the JSON object.
    data = JSON.parse(json_line[json_line.index("{")..])
    expect(data["name"]).to eq("api.request")
    expect(data["controller"]).to eq("Api::V1::HealthController")
    expect(data["action"]).to eq("show")
    expect(data["status"]).to eq(200)
    expect(data["duration_ms"]).to be_a(Numeric)
  end

  it "emits candidate lookup count and duration without bbox or coordinates" do
    create(:monitored_segment,
           geometry: "SRID=4326;LINESTRING(-92.5410 41.6963, -92.5400 41.6963)")

    log = capture_log do
      Routing::SegmentExclusionBuilder.new.segments_in_bbox([ -92.60, 41.65, -92.50, 41.72 ])
    end
    json_line = log.lines.map(&:strip).find do |line|
      line.include?(%q("name":"routing.candidate_lookup"))
    end
    expect(json_line).not_to be_nil, "expected a structured routing.candidate_lookup log line"

    data = JSON.parse(json_line[json_line.index("{")..])
    expect(data.keys).to contain_exactly("name", "candidate_count", "duration_ms")
    expect(data["candidate_count"]).to eq(1)
    expect(data["duration_ms"]).to be_a(Numeric)
  end
end
