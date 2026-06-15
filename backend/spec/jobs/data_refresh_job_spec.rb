require "rails_helper"

RSpec.describe DataRefreshJob, type: :job do
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  let(:iowa) { { south: 41.0, west: -94.0, north: 42.0, east: -93.0 } }
  let(:records) { [ { external_ref: "osm:1", lat: 41.5, lng: -93.5, camera_type: "Flock", confidence: 0.5 } ] }

  def fake_source(records, license: "ODbL-1.0")
    instance_double(
      CameraData::Sources::Base,
      source_name: "OpenStreetMap", source_kind: "community",
      source_url: nil, license: license, fetch: records,
      supports_delta?: false
    )
  end

  # Factory returning a fresh fake source (same records) for any tile.
  def factory_for(records) = ->(_bbox) { fake_source(records) }

  def run!(**opts)
    described_class.new.perform("aggregate", tiles: [ iowa ], source_factory: factory_for(records),
                                             road_lookup: nil, **opts)
  end

  it "is a background job (enqueued, not run inline) — FR-011" do
    expect { DataRefreshJob.perform_later("aggregate") }
      .to have_enqueued_job(DataRefreshJob).with("aggregate")
  end

  it "defaults to the PBF-derived OSM extract source (ADR 0002)" do
    src = described_class.new.send(:pbf_source, iowa)
    expect(src).to be_a(CameraData::Sources::OsmExtractFile)
    expect(src.source_name).to eq("OpenStreetMap")
  end

  it "uses the live Overpass API as the escape hatch (same provenance identity)" do
    src = described_class.new.send(:default_source, iowa)
    expect(src).to be_a(CameraData::Sources::Overpass)
    # Same DataSource name as the PBF source, so flipping CAMERA_OSM_SOURCE is seamless.
    expect(src.source_name).to eq("OpenStreetMap")
  end

  it "in PBF mode (default) imports from the prebuilt extract GeoJSON over CONUS" do
    geojson = {
      type: "FeatureCollection",
      features: [ {
        type: "Feature", id: "n4242",
        geometry: { type: "Point", coordinates: [ -93.5, 41.5 ] },
        properties: { "man_made" => "surveillance", "surveillance:type" => "ALPR" }
      } ]
    }.to_json
    file = Tempfile.new([ "cameras", ".geojson" ])
    file.write(geojson)
    file.flush
    allow(CameraData).to receive(:osm_extract_geojson_path).and_return(file.path)

    # No tiles:/source_factory: injection → exercises the real default (pbf) path.
    expect { described_class.new.perform("aggregate", road_lookup: nil) }
      .to change(Camera, :count).by(1)
    expect(Camera.last.external_ref).to eq("osm:node/4242")
    expect(RefreshRun.last.status).to eq("success")
  ensure
    file&.close
    file&.unlink
  end

  it "honors CAMERA_OSM_SOURCE=overpass — tiles over UsTiles via the Overpass factory" do
    allow(CameraData).to receive(:osm_source).and_return("overpass")
    job = described_class.new
    expect(CameraData::Sources::UsTiles).to receive(:cells).and_return([ iowa ])
    # TiledRefresh calls the factory more than once per tile (name derivation +
    # fetch), so allow rather than expect-exactly-once.
    allow(job).to receive(:default_source).with(iowa).and_return(fake_source(records))

    expect { job.perform("aggregate", road_lookup: nil) }.to change(Camera, :count).by(1)
    expect(job).to have_received(:default_source).with(iowa).at_least(:once)
  end

  it "tiles the refresh and records a scheduled RefreshRun" do
    expect { run! }.to change(Camera, :count).by(1)

    run = RefreshRun.last
    expect(run.trigger).to eq("scheduled")
    expect(run.status).to eq("success")
    expect(run.totals["added"]).to eq(1)
    expect(run.duration_ms).to be >= 0
  end

  it "refreshes coverage freshness (no 002 regression)" do
    area = create(:coverage_area, data_freshness_at: 2.days.ago)
    run!
    expect(area.reload.data_freshness_at).to be_within(1.minute).of(Time.current)
  end

  it "does not start while another run is in progress (FR-014)" do
    RefreshRun.create!(trigger: "manual", started_at: Time.current)
    expect { expect(run!).to eq(:skipped) }.not_to change(Camera, :count)
  end

  it "supports a manual trigger" do
    run!(trigger: "manual")
    expect(RefreshRun.last.trigger).to eq("manual")
  end

  it "isolates a failed tile: healthy tiles still import, run is partial" do
    good = iowa
    bad = { south: 42.0, west: -94.0, north: 43.0, east: -93.0 }
    factory = lambda do |bbox|
      next fake_source(records) unless bbox == bad

      fake_source([]).tap { |s| allow(s).to receive(:fetch).and_raise(StandardError, "tile down") }
    end

    expect(Telemetry).to receive(:alert)
      .with(a_string_including("status=partial"), hash_including(status: "partial"))

    run = described_class.new.perform("aggregate", tiles: [ good, bad ], source_factory: factory, road_lookup: nil)

    expect(run.status).to eq("partial")
    expect(run.per_source["OpenStreetMap"]["tiles_failed"]).to eq(1)
    expect(Camera.count).to eq(1) # the good tile still imported
  end

  it "alerts telemetry when every tile fails (status failed)" do
    failing = ->(_bbox) { fake_source([]).tap { |s| allow(s).to receive(:fetch).and_raise(StandardError, "boom") } }
    expect(Telemetry).to receive(:alert)
      .with(a_string_including("status=failed"), hash_including(status: "failed"))

    described_class.new.perform("aggregate", tiles: [ iowa ], source_factory: failing, road_lookup: nil)
  end

  it "does not alert telemetry on a fully successful run" do
    expect(Telemetry).not_to receive(:alert)
    run!
  end

  it "marks the run failed and notifies telemetry if the refresh crashes hard" do
    allow_any_instance_of(CameraData::TiledRefresh).to receive(:import_next).and_raise(StandardError, "kaboom")
    expect(Telemetry).to receive(:notify).with(an_instance_of(StandardError), hash_including(:run_id))

    expect { run! }.to raise_error(StandardError, "kaboom")

    run = RefreshRun.last
    expect(run.status).to eq("failed")
    expect(run.finished_at).to be_present
    expect(RefreshRun.running?).to be(false)
  end
end
