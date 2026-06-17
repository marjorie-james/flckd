require "rails_helper"

# The pure Accept-Language negotiator (contracts §2/§4). Verified against the
# shared scenario table with backend q-value semantics; available locales are
# en + es (the launch catalog), default en.
RSpec.describe Api::V1::LocaleNegotiator do
  def negotiate(header)
    described_class.call(header, available: %i[en es], default: :en)
  end

  it "row 1: picks the top supported language" do
    expect(negotiate("es, en")).to eq(:es)
  end

  it "row 2: falls back to the default when nothing is supported" do
    expect(negotiate("fr, de")).to eq(:en)
  end

  it "row 3: matches a regional variant to its base language" do
    expect(negotiate("es-MX, en")).to eq(:es)
  end

  it "row 4: skips an unsupported higher-q entry for a supported one" do
    expect(negotiate("de;q=0.9, es;q=0.8")).to eq(:es)
  end

  it "row 5: orders by quality, not header position" do
    expect(negotiate("en;q=0.7, es;q=0.9")).to eq(:es)
  end

  it "row 6: ignores a wildcard entry" do
    expect(negotiate("*")).to eq(:en)
  end

  it "row 7: returns the default for an empty or nil header" do
    expect(negotiate("")).to eq(:en)
    expect(negotiate(nil)).to eq(:en)
  end

  it "row 8: reduces multiple regional variants to the base" do
    expect(negotiate("es-ES, es-MX")).to eq(:es)
  end

  it "row 9: breaks equal-quality ties by header order (deterministic)" do
    expect(negotiate("en, es")).to eq(:en)
    expect(negotiate("es, en")).to eq(:es)
  end

  it "treats an unparseable q-value as 1.0" do
    expect(negotiate("es;q=bogus, en")).to eq(:es)
  end

  it "parses an RFC-valid uppercase Q= weight case-insensitively" do
    expect(negotiate("en;Q=0.1, es;Q=0.9")).to eq(:es)
  end
end
