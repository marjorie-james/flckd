require "rails_helper"

RSpec.describe CameraData::Sources::Base do
  # A bare subclass exposing the shared private normalizers for direct testing.
  let(:source) do
    Class.new(described_class) do
      public :normalize_direction, :normalize_camera_type
    end.new
  end

  describe "#normalize_direction" do
    it "rounds fractional degrees instead of truncating them" do
      # Regression: Integer(value, exception: false) used to truncate floats and
      # short-circuit the rounding branch (359.9 -> 359, 271.6 -> 271).
      expect(source.normalize_direction(359.9)).to eq(0)   # rounds up, then % 360
      expect(source.normalize_direction(271.6)).to eq(272)
    end

    it "parses integer-like strings" do
      expect(source.normalize_direction("90")).to eq(90)
    end

    it "maps cardinal strings" do
      expect(source.normalize_direction("NE")).to eq(45)
    end

    it "wraps values into 0..359" do
      expect(source.normalize_direction(360)).to eq(0)
      expect(source.normalize_direction(450)).to eq(90)
    end

    it "returns nil for nil or invalid input" do
      expect(source.normalize_direction(nil)).to be_nil
      expect(source.normalize_direction("not-a-bearing")).to be_nil
    end
  end
end
