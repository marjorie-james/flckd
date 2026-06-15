require "rails_helper"
require "json"

# Backs `rake camera_data:refresh:status` (FR-013). The --json form must match
# contracts/refresh-run.schema.json and carry no user data.
RSpec.describe CameraData::RefreshStatus do
  let!(:run) do
    RefreshRun.create!(
      trigger: "manual", status: "partial",
      started_at: Time.utc(2026, 6, 1, 10), finished_at: Time.utc(2026, 6, 1, 10, 12), duration_ms: 720_000,
      per_source: {
        "OpenStreetMap" => { "status" => "success", "added" => 5, "updated" => 100, "skipped" => 0, "retired" => 2 },
        "DeFlock" => { "status" => "failed", "added" => 0, "updated" => 0, "skipped" => 0, "retired" => 0, "error_class" => "Faraday::TimeoutError" }
      },
      totals: { "added" => 5, "updated" => 100, "skipped" => 0, "retired" => 2 }
    )
  end

  it "serializes recent runs with the contract shape" do
    json = described_class.new(limit: 5).as_json
    row = json.first

    expect(row["trigger"]).to eq("manual")
    expect(row["status"]).to eq("partial")
    expect(row["started_at"]).to eq("2026-06-01T10:00:00Z")
    expect(row["duration_ms"]).to eq(720_000)
    expect(row["totals"]).to eq("added" => 5, "updated" => 100, "skipped" => 0, "retired" => 2)
    expect(row["per_source"]["DeFlock"]["error_class"]).to eq("Faraday::TimeoutError")
  end

  it "carries no user data — only counts, source names, status, error class" do
    allowed_source_keys = %w[status added updated skipped retired error_class]
    described_class.new.as_json.each do |row|
      row["per_source"].each_value { |o| expect(o.keys - allowed_source_keys).to be_empty }
    end
  end

  it "renders a human-readable table" do
    text = described_class.new.to_text
    expect(text).to include("manual", "partial", "OpenStreetMap")
  end
end
