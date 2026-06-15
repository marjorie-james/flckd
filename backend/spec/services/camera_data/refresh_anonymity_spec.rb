require "rails_helper"

# Anonymity guarantees for the camera-data pipeline (FR-016/FR-017): the refresh
# operates on reference data only and persists no user data. The RefreshRun audit
# must never contain coordinates, IPs, origins, destinations, or routes.
RSpec.describe "camera-data refresh anonymity" do
  # Exact field names that would indicate user data leaking into the audit.
  USER_DATA_KEYS = %w[lat lng latitude longitude ip client_ip origin destination route coordinates address].freeze

  def all_keys(obj)
    case obj
    when Hash then obj.keys.map(&:to_s) + obj.values.flat_map { |v| all_keys(v) }
    when Array then obj.flat_map { |v| all_keys(v) }
    else []
    end
  end

  it "RefreshRun audit exposes only reference-data keys (no user-data fields)" do
    RefreshRun.create!(
      trigger: "scheduled", status: "partial",
      started_at: Time.utc(2026, 6, 1, 10), finished_at: Time.utc(2026, 6, 1, 10, 5), duration_ms: 300_000,
      per_source: {
        "OpenStreetMap" => { "status" => "success", "added" => 3, "updated" => 9, "skipped" => 0, "retired" => 1 },
        "DeFlock" => { "status" => "failed", "added" => 0, "updated" => 0, "skipped" => 0, "retired" => 0, "error_class" => "Faraday::TimeoutError" }
      },
      totals: { "added" => 3, "updated" => 9, "skipped" => 0, "retired" => 1 }
    )

    keys = all_keys(CameraData::RefreshStatus.new.as_json)
    expect(keys & USER_DATA_KEYS).to be_empty
  end

  it "the refresh_runs table has no column that could hold user coordinates or IPs" do
    expect(RefreshRun.column_names & USER_DATA_KEYS).to be_empty
  end
end
