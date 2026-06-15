require "rails_helper"
require "stringio"

# Regression: the coordinate log scrubber must catch every logging form, not
# just the rare positional-message one. See config/initializers/anonymity_logging.rb
# (FR-011, SC-008 — no route coordinates in logs).
RSpec.describe AnonymityLogScrubber do
  describe ".scrub" do
    it "redacts precise coordinates" do
      expect(described_class.scrub("origin 39.7392,-104.9903"))
        .to eq("origin [redacted-coord],[redacted-coord]")
    end

    it "leaves low-precision numbers (durations, counts) alone" do
      expect(described_class.scrub("rendered in 3.5ms, 12 segments"))
        .to eq("rendered in 3.5ms, 12 segments")
    end

    it "passes non-string messages through untouched" do
      expect(described_class.scrub(nil)).to be_nil
      expect(described_class.scrub({ a: 1 })).to eq({ a: 1 })
    end
  end

  describe AnonymityLogScrubber::Formatter do
    # Build a logger wired exactly like the initializer does, then exercise the
    # three logging forms that the previous `Logger#add` override silently
    # missed.
    let(:io) { StringIO.new }
    let(:logger) do
      ActiveSupport::Logger.new(io).tap do |l|
        l.formatter = AnonymityLogScrubber::Formatter.new(l.formatter)
      end
    end

    it "scrubs the positional-message form" do
      logger.add(Logger::INFO, "lat 39.7392 lng -104.9903")
      expect(io.string).to include("[redacted-coord]")
      expect(io.string).not_to match(/39\.7392|-104\.9903/)
    end

    it "scrubs `logger.info(\"…\")` (string arrives as progname)" do
      logger.info("planning route to 41.5868,-93.6250")
      expect(io.string).to include("[redacted-coord]")
      expect(io.string).not_to match(/41\.5868|-93\.6250/)
    end

    it "scrubs the block form" do
      logger.info { "destination 51.5074,-0.1278" }
      expect(io.string).to include("[redacted-coord]")
      expect(io.string).not_to match(/51\.5074|-0\.1278/)
    end
  end

  describe "Rails.logger wiring" do
    it "wraps every underlying formatter with the scrubber" do
      targets =
        if Rails.logger.respond_to?(:broadcasts)
          Rails.logger.broadcasts
        else
          [ Rails.logger ]
        end

      formatters = targets.select { |l| l.respond_to?(:formatter) }.map(&:formatter)
      expect(formatters).to all(be_a(AnonymityLogScrubber::Formatter))
    end
  end
end
