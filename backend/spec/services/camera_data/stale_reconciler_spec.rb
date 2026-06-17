require "rails_helper"

RSpec.describe CameraData::StaleReconciler do
  let(:source) { DataSource.create!(name: "OpenStreetMap", kind: "community", license: "ODbL-1.0") }
  let(:cutoff) { Time.utc(2026, 6, 1, 10, 0, 0) }

  def camera(seen_at:, status: "unverified", missing: 0)
    create(:camera, data_source: source, last_seen_in_source_at: seen_at,
                    verification_status: status, consecutive_missing_count: missing, stale: missing.positive?)
  end

  it "resets the missing counter and clears stale for cameras seen this run" do
    cam = camera(seen_at: cutoff, missing: 2)
    described_class.new.reconcile(data_source: source, cutoff: cutoff)
    cam.reload
    expect(cam.consecutive_missing_count).to eq(0)
    expect(cam.stale).to be(false)
  end

  it "increments the missing counter and flags stale for cameras absent this run" do
    cam = camera(seen_at: cutoff - 1.day, missing: 0)
    described_class.new.reconcile(data_source: source, cutoff: cutoff)
    cam.reload
    expect(cam.consecutive_missing_count).to eq(1)
    expect(cam.stale).to be(true)
    expect(cam.verification_status).to eq("unverified") # still avoided
  end

  it "auto-retires a camera after 3 consecutive missing refreshes" do
    cam = camera(seen_at: cutoff - 1.day, missing: 2) # this run makes it the 3rd miss
    result = described_class.new(missing_limit: 3).reconcile(data_source: source, cutoff: cutoff)
    cam.reload
    expect(cam.consecutive_missing_count).to eq(3)
    expect(cam.auto_retired).to be(true)
    expect(cam.verification_status).to eq("unverified") # not the terminal human-removed status
    expect(result.retired).to eq(1)
  end

  it "revives an auto-retired camera the source reports again" do
    cam = camera(seen_at: cutoff, missing: 5)
    cam.update!(auto_retired: true)
    described_class.new(missing_limit: 3).reconcile(data_source: source, cutoff: cutoff)
    cam.reload
    expect(cam.auto_retired).to be(false) # recovered — back in the avoidance set
    expect(cam.consecutive_missing_count).to eq(0)
    expect(cam.stale).to be(false)
  end

  it "does not re-count an already auto-retired camera that is still missing" do
    cam = camera(seen_at: cutoff - 1.day, missing: 5)
    cam.update!(auto_retired: true)
    result = described_class.new(missing_limit: 3).reconcile(data_source: source, cutoff: cutoff)
    cam.reload
    expect(result.retired).to eq(0) # already retired, not newly retired
    expect(cam.consecutive_missing_count).to eq(5) # left untouched (no unbounded growth)
  end

  it "never revives a human-removed camera (terminal)" do
    cam = camera(seen_at: cutoff, status: "removed", missing: 0)
    described_class.new.reconcile(data_source: source, cutoff: cutoff)
    expect(cam.reload.verification_status).to eq("removed") # excluded from reconciliation
  end

  it "never auto-retires a human-verified camera (exempt)" do
    cam = camera(seen_at: cutoff - 1.day, status: "verified", missing: 5)
    result = described_class.new(missing_limit: 3).reconcile(data_source: source, cutoff: cutoff)
    cam.reload
    expect(cam.verification_status).to eq("verified")
    expect(cam.stale).to be(true)
    expect(result.retired).to eq(0)
  end

  describe "#touch_seen (delta path)" do
    it "does not stamp auto_retired cameras (so reconcile won't revive ones the source never re-reported)" do
      cam = camera(seen_at: cutoff - 5.days, missing: 5)
      cam.update!(auto_retired: true)

      # Delta run touches everything-not-in-the-diff; the auto-retired camera is in
      # neither upserted nor deleted_refs, so it must be left untouched.
      described_class.new.touch_seen(data_source: source, except_refs: [])
      described_class.new(missing_limit: 3).reconcile(data_source: source, cutoff: cutoff)

      cam.reload
      expect(cam.auto_retired).to be(true) # NOT revived
      expect(cam.consecutive_missing_count).to eq(5) # unchanged
    end

    it "still revives an auto_retired camera the source actually re-reports in the delta" do
      cam = camera(seen_at: cutoff - 5.days, missing: 5)
      cam.update!(auto_retired: true)

      # In a real delta the re-reported camera is upserted: the importer stamps its
      # last_seen_in_source_at to now (>= cutoff). Simulate that here, then reconcile.
      cam.update!(last_seen_in_source_at: cutoff + 1.minute)
      described_class.new.touch_seen(data_source: source, except_refs: [ cam.external_ref ])
      described_class.new(missing_limit: 3).reconcile(data_source: source, cutoff: cutoff)

      cam.reload
      expect(cam.auto_retired).to be(false) # revived
      expect(cam.consecutive_missing_count).to eq(0)
    end
  end

  it "only touches the given source's cameras" do
    other = DataSource.create!(name: "DeFlock", kind: "community", license: "ODbL-1.0")
    untouched = create(:camera, data_source: other, last_seen_in_source_at: cutoff - 1.day, consecutive_missing_count: 0)
    described_class.new.reconcile(data_source: source, cutoff: cutoff)
    expect(untouched.reload.consecutive_missing_count).to eq(0)
  end
end
