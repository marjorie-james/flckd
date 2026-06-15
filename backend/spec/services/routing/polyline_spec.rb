require "rails_helper"

RSpec.describe Routing::Polyline do
  describe ".decode" do
    # Canonical Google example string (precision 1e5) decodes to three known
    # points. Returned as [lng, lat] pairs (GeoJSON order).
    it "decodes an encoded polyline to [lng, lat] coordinates" do
      coords = described_class.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 1e5)

      expect(coords.length).to eq(3)
      expect(coords[0][0]).to be_within(0.0001).of(-120.2)
      expect(coords[0][1]).to be_within(0.0001).of(38.5)
      expect(coords[2][0]).to be_within(0.0001).of(-126.453)
      expect(coords[2][1]).to be_within(0.0001).of(43.252)
    end

    it "returns an empty array for blank input" do
      expect(described_class.decode(nil)).to eq([])
      expect(described_class.decode("")).to eq([])
    end

    it "stops cleanly at the last complete pair on truncated input" do
      expect { described_class.decode("_p~iF~ps") }.not_to raise_error
    end
  end

  describe ".to_linestring_ewkt" do
    it "builds a SRID 4326 LINESTRING from an encoded shape" do
      ewkt = described_class.to_linestring_ewkt("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 1e5)

      expect(ewkt).to start_with("SRID=4326;LINESTRING(")
      expect(ewkt).to include("-120.2 38.5")
    end

    it "returns nil when fewer than two points decode" do
      expect(described_class.to_linestring_ewkt("")).to be_nil
    end
  end
end
