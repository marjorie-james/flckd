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

    # Regression: low-precision coordinate PAIRS used to slip through because the
    # single-coordinate COORD regex only matched 3+ decimals. The structural
    # COORD_PAIR matcher catches them even at 0-2 decimals, while a lone number
    # ("3.5ms" above) is still left alone.
    it "redacts a 1-decimal coordinate pair (e.g. a bbox corner)" do
      expect(described_class.scrub("bbox 41.5,-93.6"))
        .to eq("bbox [redacted-coord],[redacted-coord]")
    end

    it "redacts a 2-decimal coordinate pair" do
      expect(described_class.scrub("at 41.59,-93.62"))
        .to eq("at [redacted-coord],[redacted-coord]")
    end

    it "redacts an integer coordinate pair" do
      expect(described_class.scrub("near 41,-93"))
        .to eq("near [redacted-coord],[redacted-coord]")
    end

    it "redacts a pair with whitespace around the separator" do
      expect(described_class.scrub("point 41.59, -93.62"))
        .to eq("point [redacted-coord], [redacted-coord]")
    end

    it "leaves a lone low-precision number alone (no comma-joined pair)" do
      expect(described_class.scrub("took 3.5ms")).to eq("took 3.5ms")
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

    # Regression: wrapping snapshotted Rails.logger.broadcasts at boot, so a sink
    # attached LATER (by a subsequently-loaded initializer/gem) emitted unscrubbed
    # output. Re-running the wrap lambda (as the after_initialize hook does) must
    # cover the newly-added sink.
    it "wraps a sink attached after boot when the wrap lambda re-runs", if: Rails.logger.respond_to?(:broadcast_to) do
      extra = ActiveSupport::Logger.new(StringIO.new)
      original_broadcasts = Rails.logger.broadcasts.dup

      Rails.logger.broadcast_to(extra)
      # Newly-attached sink starts with its own (non-scrubbing) formatter.
      expect(extra.formatter).not_to be_a(AnonymityLogScrubber::Formatter)

      AnonymityLogScrubber.wrap_logger_sinks.call

      expect(extra.formatter).to be_a(AnonymityLogScrubber::Formatter)
    ensure
      Rails.logger.stop_broadcasting_to(extra) if defined?(extra) && extra
      # Sanity: the broadcast list is restored for following examples.
      expect(Rails.logger.broadcasts).to match_array(original_broadcasts) if defined?(original_broadcasts)
    end
  end
end
