require "rails_helper"

RSpec.describe CameraData::Sources::Overpass do
  let(:bbox) { { south: 41.5, west: -93.7, north: 41.8, east: -92.0 } }
  let(:endpoint) { "https://overpass.test/api/interpreter" }
  let(:fixture) { Rails.root.join("spec/fixtures/overpass/alpr_response.json").read }

  subject(:source) do
    described_class.new(bbox: bbox, endpoint: endpoint, max_retries: 0)
  end

  def stub_overpass(status: 200, body: fixture)
    stub_request(:post, endpoint)
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  it "declares ODbL provenance" do
    expect(source.source_name).to match(/OpenStreetMap/)
    expect(source.license).to eq("ODbL-1.0")
    expect(source.source_kind).to eq("community")
  end

  it "identifies the app honestly in the User-Agent and queries only the bbox" do
    stub = stub_overpass
    source.fetch

    expect(stub).to have_been_requested
    expect(WebMock).to have_requested(:post, endpoint).with { |req|
      req.headers["User-Agent"].to_s.include?("flckd") &&
        CGI.unescape(req.body).include?("41.5,-93.7,41.8,-92.0")
    }
  end

  it "normalizes ALPR nodes and skips non-nodes" do
    stub_overpass
    records = source.fetch

    expect(records.size).to eq(3) # the way is filtered out
    refs = records.map { |r| r[:external_ref] }
    expect(refs).to contain_exactly("osm:node/1001", "osm:node/1002", "osm:node/1003")
  end

  it "maps brand/type tags to a coarse camera_type" do
    stub_overpass
    by_ref = source.fetch.index_by { |r| r[:external_ref] }

    expect(by_ref["osm:node/1001"][:camera_type]).to eq("Flock") # brand=Flock Safety
    expect(by_ref["osm:node/1002"][:camera_type]).to eq("ALPR")  # camera:type=ALPR
    expect(by_ref["osm:node/1003"][:camera_type]).to eq("Flock") # operator=Flock
  end

  it "normalizes facing direction from degrees and cardinals" do
    stub_overpass
    by_ref = source.fetch.index_by { |r| r[:external_ref] }

    expect(by_ref["osm:node/1001"][:facing_direction]).to eq(90)  # "90"
    expect(by_ref["osm:node/1002"][:facing_direction]).to eq(45)  # "NE"
    expect(by_ref["osm:node/1003"][:facing_direction]).to be_nil  # untagged
  end

  it "raises a FetchError when the endpoint is unreachable after retries" do
    stub_overpass(status: 429, body: "rate limited")

    expect { source.fetch }.to raise_error(described_class::FetchError)
  end

  it "retries on rate-limit then succeeds" do
    calls = 0
    stub_request(:post, endpoint).to_return do
      calls += 1
      calls < 2 ? { status: 429, body: "slow down" } : { status: 200, body: fixture, headers: { "Content-Type" => "application/json" } }
    end
    retrying = described_class.new(bbox: bbox, endpoint: endpoint, max_retries: 1, backoff: ->(_) { })

    expect(retrying.fetch.size).to eq(3)
    expect(calls).to eq(2)
  end

  it "refuses to build a query from non-numeric bbox values (QL-injection guard)" do
    bad = described_class.new(bbox: { south: "1); evil", west: 0, north: 1, east: 1 }, endpoint: endpoint, max_retries: 0)
    expect { bad.fetch }.to raise_error(ArgumentError, /numeric/)
  end

  describe "#supports_delta?" do
    it "returns true when since is within the 14-day window" do
      expect(source.supports_delta?(since: 1.day.ago)).to be(true)
      expect(source.supports_delta?(since: 13.days.ago)).to be(true)
    end

    it "returns false when since is nil" do
      expect(source.supports_delta?(since: nil)).to be(false)
    end

    it "returns false when since is older than 14 days" do
      expect(source.supports_delta?(since: 15.days.ago)).to be(false)
    end
  end

  describe "#fetch_delta" do
    let(:diff_fixture) { Rails.root.join("spec/fixtures/overpass/alpr_diff_response.json").read }

    def stub_overpass_diff(status: 200, body: diff_fixture)
      stub_request(:post, endpoint)
        .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
    end

    it "sends a [diff:...] query with the since timestamp" do
      stub = stub_overpass_diff
      source.fetch_delta(since: 1.day.ago)

      expect(stub).to have_been_requested
      expect(WebMock).to have_requested(:post, endpoint).with { |req|
        CGI.unescape(req.body).match?(/\[diff:"[^"]+"\]/)
      }
    end

    it "returns upserted records for created and modified nodes" do
      stub_overpass_diff
      result = source.fetch_delta(since: 1.day.ago)

      expect(result[:upserted].map { |r| r[:external_ref] })
        .to contain_exactly("osm:node/2001", "osm:node/1001")
    end

    it "returns deleted_refs for deleted nodes" do
      stub_overpass_diff
      result = source.fetch_delta(since: 1.day.ago)

      expect(result[:deleted_refs]).to contain_exactly("osm:node/1002")
    end

    it "skips way elements (only nodes are cameras)" do
      stub_overpass_diff
      result = source.fetch_delta(since: 1.day.ago)

      refs = result[:upserted].map { |r| r[:external_ref] }
      expect(refs).not_to include("osm:node/3001")
      expect(result[:deleted_refs]).not_to include("osm:node/3001")
    end

    it "normalizes updated camera attributes from the diff" do
      stub_overpass_diff
      result = source.fetch_delta(since: 1.day.ago)

      modified = result[:upserted].find { |r| r[:external_ref] == "osm:node/1001" }
      expect(modified[:facing_direction]).to eq(270) # updated from 90 to 270
      expect(modified[:camera_type]).to eq("Flock")
    end

    it "raises FetchError when the endpoint is unreachable" do
      stub_overpass_diff(status: 429, body: "rate limited")
      expect { source.fetch_delta(since: 1.day.ago) }.to raise_error(described_class::FetchError)
    end

    it "refuses non-numeric bbox values in the diff query (QL-injection guard)" do
      bad = described_class.new(bbox: { south: "1); evil", west: 0, north: 1, east: 1 }, endpoint: endpoint, max_retries: 0)
      expect { bad.fetch_delta(since: 1.day.ago) }.to raise_error(ArgumentError, /numeric/)
    end
  end
end
