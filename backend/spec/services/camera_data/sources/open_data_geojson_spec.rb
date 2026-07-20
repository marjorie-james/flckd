require "rails_helper"

RSpec.describe CameraData::Sources::OpenDataGeojson do
  let(:url) { "https://data.example.gov/resource/abcd-1234.geojson" }

  subject(:source) do
    described_class.new(
      url: url,
      name: "Example City ALPR Open Data",
      license: "CC0-1.0"
    )
  end

  # A Socrata/ArcGIS-style GeoJSON FeatureCollection served over HTTP.
  let(:body) do
    {
      type: "FeatureCollection",
      features: [
        { type: "Feature",
          geometry: { type: "Point", coordinates: [ -104.99, 39.74 ] },
          properties: { id: "alpr-1", brand: "Flock", direction: "S", confidence: 0.9 } },
        { type: "Feature", # no id → deterministic coord-derived ref
          geometry: { type: "Point", coordinates: [ -104.93, 39.73 ] },
          properties: { type: "ALPR" } },
        { type: "Feature", # non-point → skipped
          geometry: { type: "LineString", coordinates: [ [ -104.9, 39.7 ], [ -104.8, 39.6 ] ] },
          properties: {} }
      ]
    }.to_json
  end

  def stub_endpoint(status: 200, response_body: body)
    stub_request(:get, url)
      .to_return(status: status, body: response_body, headers: { "Content-Type" => "application/json" })
  end

  it "carries the supplied per-dataset provenance and an open-data kind" do
    expect(source.source_name).to eq("Example City ALPR Open Data")
    expect(source.license).to eq("CC0-1.0")
    expect(source.source_kind).to eq("open-data")
    expect(source.source_url).to eq(url)
  end

  it "fetches the FeatureCollection over HTTP and normalizes points (skipping non-points)" do
    stub_endpoint
    records = source.fetch

    expect(records.size).to eq(2) # the LineString is skipped
    expect(records.map { |r| r[:lat] }).to all(be_a(Numeric))
  end

  it "reuses GeojsonFile normalization (ids, direction, type, confidence)" do
    stub_endpoint
    by_ref = source.fetch.index_by { |r| r[:external_ref] }

    expect(by_ref["alpr-1"][:camera_type]).to eq("Flock")
    expect(by_ref["alpr-1"][:facing_direction]).to eq(180) # "S"
    expect(by_ref["alpr-1"][:confidence]).to eq(0.9)
    # id-less feature gets a deterministic coord ref + default confidence.
    expect(by_ref["geojson:39.730000,-104.930000"][:confidence]).to eq(0.5)
  end

  it "identifies the app honestly in the User-Agent" do
    stub = stub_endpoint
    source.fetch

    expect(stub).to have_been_requested
    expect(WebMock).to have_requested(:get, url)
      .with { |req| req.headers["User-Agent"].to_s.include?("flckd") }
  end

  it "raises FetchError on a non-success response (isolated per-source upstream)" do
    stub_endpoint(status: 503, response_body: "upstream down")
    expect { source.fetch }.to raise_error(described_class::FetchError, /503/)
  end
end
