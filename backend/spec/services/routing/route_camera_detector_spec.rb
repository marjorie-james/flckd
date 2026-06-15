require "rails_helper"

RSpec.describe Routing::RouteCameraDetector do
  # The detector consumes Valhalla polyline6, and the app only ships a decoder, so
  # this local encoder builds route fixtures from real coordinates. It's the exact
  # inverse of Routing::Polyline.decode (zig-zag varint, precision 1e6).
  def encode(coords)
    out = +""
    prev_lat = 0
    prev_lng = 0
    coords.each do |lng, lat|
      ilat = (lat * 1_000_000).round
      ilng = (lng * 1_000_000).round
      out << encode_value(ilat - prev_lat) << encode_value(ilng - prev_lng)
      prev_lat = ilat
      prev_lng = ilng
    end
    out
  end

  def encode_value(value)
    v = value.negative? ? ~(value << 1) : (value << 1)
    out = +""
    while v >= 0x20
      out << ((0x20 | (v & 0x1f)) + 63).chr
      v >>= 5
    end
    (out << (v + 63).chr)
  end

  # A short E–W road segment at latitude 39.7392.
  let(:segment_geom) { "SRID=4326;LINESTRING(-104.9905 39.7392, -104.9901 39.7392)" }
  let(:on_segment) { { geometry: encode([ [ -104.9905, 39.7392 ], [ -104.9901, 39.7392 ] ]) } }
  # A parallel street ~22 m north (0.0002° lat) — clearly outside DETECTION_BUFFER (~9 m).
  let(:parallel_street) { { geometry: encode([ [ -104.9905, 39.7394 ], [ -104.9901, 39.7394 ] ]) } }

  it "round-trips the encoder against Routing::Polyline.decode (fixture sanity)" do
    decoded = Routing::Polyline.decode(on_segment[:geometry])
    expect(decoded.first[0]).to be_within(1e-6).of(-104.9905)
    expect(decoded.first[1]).to be_within(1e-6).of(39.7392)
  end

  it "reports a route running along a monitored segment as passed" do
    seg = create(:monitored_segment, geometry: segment_geom)
    expect(described_class.new.passed(on_segment, [ seg ])).to eq([ seg ])
  end

  it "does NOT report a parallel street ~22 m away (DETECTION_BUFFER stays tight)" do
    seg = create(:monitored_segment, geometry: segment_geom)
    expect(described_class.new.passed(parallel_street, [ seg ])).to be_empty
  end

  it "returns [] for blank or undecodable geometry" do
    seg = create(:monitored_segment, geometry: segment_geom)
    expect(described_class.new.passed({ geometry: "" }, [ seg ])).to eq([])
    expect(described_class.new.passed({ geometry: nil }, [ seg ])).to eq([])
  end

  it "returns [] when there are no candidate segments (no query)" do
    expect(described_class.new.passed(on_segment, [])).to eq([])
  end

  it "preserves the input order of the candidate segments" do
    a = create(:monitored_segment, geometry: segment_geom)
    b = create(:monitored_segment, geometry: segment_geom)
    expect(described_class.new.passed(on_segment, [ b, a ])).to eq([ b, a ])
  end

  it "only considers the candidate set it is given" do
    on_route = create(:monitored_segment, geometry: segment_geom)
    create(:monitored_segment, geometry: segment_geom) # also on the road, but not a candidate
    expect(described_class.new.passed(on_segment, [ on_route ])).to eq([ on_route ])
  end
end
