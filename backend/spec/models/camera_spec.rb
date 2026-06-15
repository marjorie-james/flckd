require "rails_helper"

RSpec.describe Camera, type: :model do
  it "is valid with a location, source, and confidence" do
    expect(build(:camera)).to be_valid
  end

  it "rejects confidence outside 0..1" do
    expect(build(:camera, confidence: 1.5)).not_to be_valid
  end

  it "rejects an unknown verification status" do
    expect(build(:camera, verification_status: "bogus")).not_to be_valid
  end

  it "rejects a facing_direction of 360 or more" do
    expect(build(:camera, facing_direction: 360)).not_to be_valid
    expect(build(:camera, facing_direction: 180)).to be_valid
  end

  describe "scopes" do
    it ".active excludes removed and auto-retired cameras" do
      keep = create(:camera)
      create(:camera, :removed)
      create(:camera, auto_retired: true)
      expect(Camera.active).to contain_exactly(keep)
    end

    it ".routable filters by minimum confidence" do
      high = create(:camera, confidence: 0.9)
      create(:camera, confidence: 0.2)
      expect(Camera.routable(0.5)).to contain_exactly(high)
    end
  end

  describe "#remove! / #verify!" do
    it "transitions verification status" do
      camera = create(:camera)
      camera.verify!
      expect(camera.verification_status).to eq("verified")
      camera.remove!
      expect(camera.verification_status).to eq("removed")
    end
  end

  describe "freshness" do
    it "rejects a negative consecutive_missing_count" do
      expect(build(:camera, consecutive_missing_count: -1)).not_to be_valid
      expect(build(:camera, consecutive_missing_count: 0)).to be_valid
    end

    it ".stale returns only flagged cameras" do
      fresh = create(:camera)
      stale = create(:camera, stale: true)
      expect(Camera.stale).to contain_exactly(stale)
      expect(Camera.stale).not_to include(fresh)
    end
  end

  describe "#seen_in_source! / #mark_missing!" do
    it "seen_in_source! resets the missing counter, clears stale, and revives auto-retired" do
      camera = create(:camera, consecutive_missing_count: 2, stale: true, auto_retired: true)
      camera.seen_in_source!
      expect(camera.consecutive_missing_count).to eq(0)
      expect(camera.stale).to be(false)
      expect(camera.auto_retired).to be(false) # recovered — avoidable again
    end

    it "mark_missing! increments the counter and flags stale" do
      camera = create(:camera)
      camera.mark_missing!(limit: 3)
      expect(camera.consecutive_missing_count).to eq(1)
      expect(camera.stale).to be(true)
      expect(camera.auto_retired).to be(false)
    end

    it "mark_missing! auto-retires (recoverably, not human-removed) at the limit unless verified" do
      camera = create(:camera, consecutive_missing_count: 2)
      camera.mark_missing!(limit: 3)
      expect(camera.auto_retired).to be(true)
      # Auto-retirement must NOT use the terminal human-removal status.
      expect(camera.verification_status).to eq("unverified")
    end

    it "mark_missing! never auto-retires a verified camera" do
      camera = create(:camera, verification_status: "verified", consecutive_missing_count: 9)
      camera.mark_missing!(limit: 3)
      expect(camera.verification_status).to eq("verified")
      expect(camera.auto_retired).to be(false)
      expect(camera.stale).to be(true)
    end
  end
end
