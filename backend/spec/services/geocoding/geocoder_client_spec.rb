require "rails_helper"

# Exercises the real Nominatim HTTP boundary (request shape + jsonv2 parsing)
# against recorded fixtures rather than stubbing the client's own #get, so the
# Faraday call, params, and shared HttpClient error path are covered too
# (Constitution Principle II).
RSpec.describe Geocoding::GeocoderClient do
  let(:base_url) { "http://geocoder.test" }
  subject(:client) { described_class.new(base_url: base_url) }

  def fixture(name) = Rails.root.join("spec/fixtures/geocoder/#{name}").read

  describe "#search" do
    it "maps Nominatim jsonv2 places to normalized results" do
      stub_request(:get, "#{base_url}/search")
        .with(query: hash_including("q" => "des moines", "format" => "jsonv2"))
        .to_return(status: 200, body: fixture("search.json"),
                   headers: { "Content-Type" => "application/json" })

      results = client.search("des moines", lang: "en", limit: 5)

      expect(results.first).to eq(
        # Humanized from address details (not Nominatim's verbose display_name).
        label: "Des Moines, IA",
        # confidence is place_rank/30: a city (rank 16) is a broad match.
        lat: 41.5910323, lng: -93.6046655, type: "city", confidence: 0.53
      )
      expect(results.size).to eq(2)
    end

    it "humanizes a street address to a standard US one-liner" do
      house = {
        "name" => "1007", "display_name" => "1007, East Grand Avenue, East Village, Des Moines, Polk County, 50319, United States",
        "lat" => "41.591200", "lon" => "-93.603000", "type" => "house", "place_rank" => 30,
        "address" => { "house_number" => "1007", "road" => "East Grand Avenue", "neighbourhood" => "East Village",
                       "city" => "Des Moines", "county" => "Polk County", "state" => "Iowa", "postcode" => "50319",
                       "country" => "United States", "country_code" => "us" }
      }
      stub_request(:get, "#{base_url}/search").with(query: hash_including("q" => "x"))
        .to_return(status: 200, body: [ house ].to_json, headers: { "Content-Type" => "application/json" })

      expect(client.search("x").first[:label]).to eq("1007 East Grand Avenue, Des Moines, IA 50319")
    end

    it "falls back to display_name when no address details are present" do
      bare = { "display_name" => "Somewhere, Iowa", "lat" => "41.6", "lon" => "-93.6", "type" => "x" }
      stub_request(:get, "#{base_url}/search").with(query: hash_including("q" => "x"))
        .to_return(status: 200, body: [ bare ].to_json, headers: { "Content-Type" => "application/json" })

      expect(client.search("x").first[:label]).to eq("Somewhere, Iowa")
    end

    it "fills in the region state when the single-state extract omits it from address details" do
      regional = described_class.new(base_url: base_url, region_state: "Iowa")
      house = {
        "lat" => "41.6", "lon" => "-93.7", "type" => "house",
        # No "state" key — the Iowa extract has no state boundary.
        "address" => { "house_number" => "1007", "road" => "East Grand Avenue", "city" => "Des Moines", "postcode" => "50319" }
      }
      stub_request(:get, "#{base_url}/search").with(query: hash_including("q" => "x"))
        .to_return(status: 200, body: [ house ].to_json, headers: { "Content-Type" => "application/json" })

      expect(regional.search("x").first[:label]).to eq("1007 East Grand Avenue, Des Moines, IA 50319")
    end

    it "threads the requested language and limit into the query" do
      stub = stub_request(:get, "#{base_url}/search")
        .with(query: hash_including("accept-language" => "es", "limit" => "3"))
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      client.search("madrid", lang: "es", limit: 3)
      expect(stub).to have_been_requested
    end

    it "sends viewbox and bounded=1 when constructed with a viewbox" do
      viewboxed = described_class.new(base_url: base_url, viewbox: "-96.7,43.6,-90.0,40.3")
      stub = stub_request(:get, "#{base_url}/search")
        .with(query: hash_including("viewbox" => "-96.7,43.6,-90.0,40.3", "bounded" => "1"))
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      viewboxed.search("des moines")
      expect(stub).to have_been_requested
    end

    it "omits viewbox when none is configured" do
      stub = stub_request(:get, "#{base_url}/search")
        .with(query: hash_excluding("viewbox", "bounded"))
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      client.search("des moines")
      expect(stub).to have_been_requested
    end

    it "returns [] when Nominatim finds nothing" do
      stub_request(:get, "#{base_url}/search")
        .with(query: hash_including("q" => "nowhere"))
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      expect(client.search("nowhere")).to eq([])
    end
  end

  # Confidence is derived from Nominatim's place_rank (address specificity),
  # NOT its `importance` prominence signal — importance is negative for
  # interpolated TIGER house numbers, which would rank exact matches lowest.
  describe "#search confidence from place_rank" do
    def confidence_for(place)
      stub_request(:get, "#{base_url}/search")
        .with(query: hash_including("q" => "x"))
        .to_return(status: 200, body: [ place ].to_json,
                   headers: { "Content-Type" => "application/json" })
      client.search("x").first[:confidence]
    end

    it "scores an exact house number (place_rank 30) at full confidence" do
      # An interpolated TIGER house has negative importance but rank 30 — the
      # most precise match must score highest, which importance would invert.
      expect(confidence_for("place_rank" => 30, "importance" => -0.62)).to eq(1.0)
    end

    it "scores a street (place_rank 26) below an exact address" do
      expect(confidence_for("place_rank" => 26)).to eq(0.87)
    end

    it "scores a city (place_rank 16) as a broad match" do
      expect(confidence_for("place_rank" => 16)).to eq(0.53)
    end

    it "falls back to a neutral 0.5 when Nominatim omits place_rank" do
      expect(confidence_for("importance" => 0.9)).to eq(0.5)
    end
  end

  # The single-state OSM extract has no admin_level-4 boundary, so a typed state
  # token ("IA"/"Iowa") filters out every house-number match. The client strips
  # it before the query reaches Nominatim (the viewbox already bounds results).
  describe "#search state-token normalization" do
    subject(:client) { described_class.new(base_url: base_url, region_state: "Iowa") }

    def expect_query(input, sent)
      stub = stub_request(:get, "#{base_url}/search")
        .with(query: hash_including("q" => sent))
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })
      client.search(input)
      expect(stub).to have_been_requested
    end

    it "strips a USPS state abbreviation component" do
      expect_query("1007 East Grand Avenue, Des Moines, IA, 50319",
                   "1007 East Grand Avenue, Des Moines, 50319")
    end

    it "strips the configured region's full state name" do
      expect_query("1007 East Grand Avenue, Des Moines, Iowa", "1007 East Grand Avenue, Des Moines")
    end

    it "strips a lowercase abbreviation case-insensitively" do
      expect_query("Main St, Ames, ia", "Main St, Ames")
    end

    it "keeps a city that shares a state's name, dropping only the abbreviation" do
      expect_query("100 1st Ave, Washington, IA", "100 1st Ave, Washington")
    end

    it "never strips the first component" do
      expect_query("IA", "IA")
    end

    it "leaves a query with no state token unchanged" do
      expect_query("Des Moines, 50309", "Des Moines, 50309")
    end

    it "leaves a comma-free query untouched" do
      expect_query("des moines", "des moines")
    end

    it "does not strip another state's name when not the configured region" do
      # Only Iowa is configured/loaded; an out-of-region full name is left as-is
      # (it simply won't match anything), while its abbreviation is still dropped.
      expect_query("Springfield, Illinois", "Springfield, Illinois")
    end
  end

  describe "#reverse" do
    it "maps a single reverse result" do
      stub_request(:get, "#{base_url}/reverse")
        .with(query: hash_including("lat" => "41.6611277", "lon" => "-91.5354708"))
        .to_return(status: 200, body: fixture("reverse.json"),
                   headers: { "Content-Type" => "application/json" })

      result = client.reverse(lat: 41.6611277, lng: -91.5354708)

      expect(result).to include(
        label: "Old Capitol, Iowa City, IA",
        lat: 41.6611277, lng: -91.5354708
      )
    end

    it "localizes place names via the requested language (FR-015)" do
      stub = stub_request(:get, "#{base_url}/reverse")
        .with(query: hash_including("accept-language" => "es"))
        .to_return(status: 200, body: fixture("reverse.json"),
                   headers: { "Content-Type" => "application/json" })

      client.reverse(lat: 41.66, lng: -91.53, lang: "es")
      expect(stub).to have_been_requested
    end

    it "returns nil when Nominatim cannot reverse the point" do
      stub_request(:get, "#{base_url}/reverse")
        .with(query: hash_including("format" => "jsonv2"))
        .to_return(status: 200, body: { "error" => "Unable to geocode" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect(client.reverse(lat: 0.0, lng: 0.0)).to be_nil
    end
  end

  it "raises ServiceError when the geocoder is unreachable" do
    stub_request(:get, "#{base_url}/search")
      .with(query: hash_including("q" => "anything")).to_timeout

    expect { client.search("anything") }.to raise_error(Geo::HttpClient::ServiceError)
  end
end
