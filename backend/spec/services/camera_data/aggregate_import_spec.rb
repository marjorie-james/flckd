require "rails_helper"

RSpec.describe CameraData::AggregateImport do
  # Minimal source double matching the Sources::Base contract. Pass `raises:` to
  # simulate a source whose fetch fails.
  def source(name:, license:, records: [], kind: "community", url: nil, raises: nil)
    dbl = instance_double(
      CameraData::Sources::Base,
      source_name: name, source_kind: kind, source_url: url, license: license
    )
    allow(dbl).to receive(:supports_delta?).and_return(false)
    if raises
      allow(dbl).to receive(:fetch).and_raise(raises)
    else
      allow(dbl).to receive(:fetch).and_return(records)
    end
    dbl
  end

  let(:osm) do
    source(
      name: "OpenStreetMap", license: "ODbL-1.0",
      records: [
        { external_ref: "osm:node/1", lat: 41.68, lng: -93.13, camera_type: "Flock", confidence: 0.5 },
        { external_ref: "osm:node/2", lat: 41.69, lng: -92.54, camera_type: "ALPR", confidence: 0.5 }
      ]
    )
  end

  let(:open_data) do
    source(
      name: "City Open Data", license: "CC0-1.0", url: "https://opendata.example.gov",
      records: [ { external_ref: "city:7", lat: 39.73, lng: -104.99, camera_type: "Flock", confidence: 0.8 } ]
    )
  end

  it "imports every source with its own provenance + license and per-source counts" do
    result = described_class.new(sources: [ osm, open_data ]).call

    expect(result.per_source["OpenStreetMap"]).to include("status" => "success", "added" => 2)
    expect(result.per_source["City Open Data"]).to include("status" => "success", "added" => 1)
    expect(result.totals["added"]).to eq(3)
    expect(result.status).to eq("success")
    expect(Camera.count).to eq(3)
    expect(DataSource.find_by(name: "OpenStreetMap").license).to eq("ODbL-1.0")
    expect(DataSource.find_by(name: "City Open Data").license).to eq("CC0-1.0")
  end

  it "is idempotent across re-runs" do
    described_class.new(sources: [ osm, open_data ]).call
    second = described_class.new(sources: [ osm, open_data ]).call

    expect(Camera.count).to eq(3)
    expect(second.totals["added"]).to eq(0)
    expect(second.totals["updated"]).to eq(3)
  end

  it "keeps same-coordinate cameras from different sources as distinct rows" do
    a = source(name: "Source A", license: "ODbL-1.0",
               records: [ { external_ref: "a:1", lat: 41.68, lng: -93.13, camera_type: "Flock", confidence: 0.5 } ])
    b = source(name: "Source B", license: "CC0-1.0",
               records: [ { external_ref: "b:1", lat: 41.68, lng: -93.13, camera_type: "Flock", confidence: 0.6 } ])
    described_class.new(sources: [ a, b ]).call
    expect(Camera.count).to eq(2)
  end

  # T013: per-source failure isolation
  it "continues with healthy sources when one source fails, recording the failure" do
    boom = source(name: "Flaky Source", license: "ODbL-1.0", raises: StandardError.new("network down"))
    result = described_class.new(sources: [ osm, boom ]).call

    expect(Camera.count).to eq(2) # OSM still imported
    expect(result.per_source["Flaky Source"]).to include("status" => "failed", "error_class" => "StandardError")
    expect(result.per_source["OpenStreetMap"]).to include("status" => "success")
    expect(result.status).to eq("partial")
  end

  # T013a: license enforcement (FR-005)
  it "skips and does not import a source with a blank license" do
    licenseless = source(name: "Unlicensed Feed", license: nil,
                         records: [ { external_ref: "x:1", lat: 40.0, lng: -100.0, camera_type: "ALPR" } ])
    result = described_class.new(sources: [ osm, licenseless ]).call

    expect(Camera.where(external_ref: "x:1")).to be_empty
    expect(result.per_source["Unlicensed Feed"]["status"]).to eq("skipped_no_license")
    expect(Camera.count).to eq(2)
  end

  describe "segment snapping (dedup at segment layer)" do
    # Road lookup that snaps any camera near (41.68, -93.13) to the same OSM way.
    let(:road_lookup) do
      lookup = double("road_lookup")
      allow(lookup).to receive(:nearest_road) do |lng:, lat:|
        way = (lat.round(1) == 41.7 ? 111 : (lat * 1000).to_i)
        { osm_way_id: way, geometry_ewkt: "SRID=4326;LINESTRING(#{lng} #{lat}, #{lng + 0.01} #{lat})", distance_m: 5.0 }
      end
      lookup
    end

    it "snaps newly imported cameras when a road lookup is provided" do
      result = described_class.new(sources: [ osm, open_data ], road_lookup: road_lookup).call
      expect(result.snapped_total).to eq(3)
      expect(MonitoredSegment.count).to eq(3)
    end

    it "skips snapping entirely when no road lookup is configured" do
      result = described_class.new(sources: [ osm ]).call
      expect(result.snapped_total).to eq(0)
      expect(MonitoredSegment.count).to eq(0)
    end

    # T020: two sources reporting a camera on the same road = one avoidance target
    it "collapses duplicate cameras on the same road to a single avoidance target" do
      a = source(name: "OpenStreetMap", license: "ODbL-1.0",
                 records: [ { external_ref: "osm:node/9", lat: 41.68, lng: -93.13, camera_type: "Flock", confidence: 0.5 } ])
      b = source(name: "DeFlock", license: "ODbL-1.0",
                 records: [ { external_ref: "deflock:9", lat: 41.68, lng: -93.13, camera_type: "Flock", confidence: 0.6 } ])

      described_class.new(sources: [ a, b ], road_lookup: road_lookup).call

      expect(Camera.count).to eq(2)                              # both observations retained
      expect(MonitoredSegment.distinct.count(:osm_way_id)).to eq(1) # one avoidance target
    end
  end

  describe "stale reconciliation across refreshes (US3)" do
    def osm_with(records)
      source(name: "OpenStreetMap", license: "ODbL-1.0", records: records)
    end
    let(:two) do
      [ { external_ref: "osm:1", lat: 41.68, lng: -93.13, camera_type: "Flock", confidence: 0.5 },
        { external_ref: "osm:2", lat: 41.69, lng: -92.54, camera_type: "ALPR", confidence: 0.5 } ]
    end

    it "increments missing + flags stale when a camera drops from a source" do
      travel_to(Time.utc(2026, 6, 1, 10)) { described_class.new(sources: [ osm_with(two) ]).call }
      travel_to(Time.utc(2026, 6, 2, 10)) { described_class.new(sources: [ osm_with([ two.first ]) ]).call }

      cam2 = Camera.find_by(external_ref: "osm:2")
      expect(cam2.consecutive_missing_count).to eq(1)
      expect(cam2.stale).to be(true)
    end

    it "reports retired counts and auto-retires a camera after 3 missed refreshes" do
      travel_to(Time.utc(2026, 6, 1, 10)) { described_class.new(sources: [ osm_with(two) ]).call }
      result = nil
      travel_to(Time.utc(2026, 6, 2, 10)) { described_class.new(sources: [ osm_with([ two.first ]) ]).call }
      travel_to(Time.utc(2026, 6, 3, 10)) { described_class.new(sources: [ osm_with([ two.first ]) ]).call }
      travel_to(Time.utc(2026, 6, 4, 10)) { result = described_class.new(sources: [ osm_with([ two.first ]) ]).call }

      retired_cam = Camera.find_by(external_ref: "osm:2")
      expect(retired_cam.auto_retired).to be(true)
      expect(retired_cam.verification_status).to eq("unverified") # recoverable, not human-removed
      expect(Camera.active).not_to include(retired_cam)
      expect(result.per_source["OpenStreetMap"]["retired"]).to eq(1)
      expect(result.totals["retired"]).to eq(1)
    end

    it "revives an auto-retired camera when the source reports it again" do
      travel_to(Time.utc(2026, 6, 1, 10)) { described_class.new(sources: [ osm_with(two) ]).call }
      [ 2, 3, 4 ].each do |day|
        travel_to(Time.utc(2026, 6, day, 10)) { described_class.new(sources: [ osm_with([ two.first ]) ]).call }
      end
      expect(Camera.find_by(external_ref: "osm:2").auto_retired).to be(true)

      travel_to(Time.utc(2026, 6, 5, 10)) { described_class.new(sources: [ osm_with(two) ]).call }
      revived = Camera.find_by(external_ref: "osm:2")
      expect(revived.auto_retired).to be(false)
      expect(revived.consecutive_missing_count).to eq(0)
      expect(Camera.active).to include(revived)
    end

    it "leaves a failed source's cameras untouched (FR-012)" do
      travel_to(Time.utc(2026, 6, 1, 10)) { described_class.new(sources: [ osm_with(two) ]).call }
      boom = source(name: "OpenStreetMap", license: "ODbL-1.0", raises: StandardError.new("down"))
      travel_to(Time.utc(2026, 6, 2, 10)) { described_class.new(sources: [ boom ]).call }

      expect(Camera.find_by(external_ref: "osm:1").consecutive_missing_count).to eq(0)
    end
  end

  it "records only counts/status per source (no user data) — FR-013" do
    result = described_class.new(sources: [ osm ]).call
    expect(result.per_source["OpenStreetMap"].keys).to match_array(%w[status added updated skipped retired])
  end

  describe "delta import" do
    def delta_source(name:, license:, since:, upserted:, deleted_refs:)
      dbl = instance_double(
        CameraData::Sources::Base,
        source_name: name, source_kind: "community", source_url: nil, license: license
      )
      allow(dbl).to receive(:supports_delta?).with(since: since).and_return(true)
      allow(dbl).to receive(:fetch_delta).with(since: since).and_return(
        { upserted: upserted, deleted_refs: deleted_refs }
      )
      dbl
    end

    let(:base_records) do
      [ { external_ref: "osm:node/1", lat: 41.68, lng: -93.13, camera_type: "Flock", confidence: 0.5 },
        { external_ref: "osm:node/2", lat: 41.69, lng: -92.54, camera_type: "ALPR",  confidence: 0.5 } ]
    end

    it "upserts changed cameras and does not flag unchanged ones as missing" do
      # Seed an existing import so last_imported_at is set.
      travel_to(Time.utc(2026, 6, 1, 10)) { described_class.new(sources: [ osm ]).call }
      ds = DataSource.find_by!(name: "OpenStreetMap")

      # Delta: node/1 was modified; node/2 unchanged.
      updated = base_records.first.merge(confidence: 0.9)
      delta_src = delta_source(
        name: "OpenStreetMap", license: "ODbL-1.0",
        since: ds.last_imported_at,
        upserted: [ updated ], deleted_refs: []
      )

      travel_to(Time.utc(2026, 6, 2, 10)) do
        result = described_class.new(sources: [ delta_src ]).call
        expect(result.per_source["OpenStreetMap"]).to include("status" => "success", "updated" => 1)
      end

      # node/2 must not be flagged — it was not in the diff but is still live.
      cam2 = Camera.find_by!(external_ref: "osm:node/2")
      expect(cam2.consecutive_missing_count).to eq(0)
      expect(cam2.stale).to be(false)
    end

    it "flags deleted cameras as missing via the reconciler" do
      travel_to(Time.utc(2026, 6, 1, 10)) { described_class.new(sources: [ osm ]).call }
      ds = DataSource.find_by!(name: "OpenStreetMap")

      delta_src = delta_source(
        name: "OpenStreetMap", license: "ODbL-1.0",
        since: ds.last_imported_at,
        upserted: [], deleted_refs: [ "osm:node/2" ]
      )

      travel_to(Time.utc(2026, 6, 2, 10)) { described_class.new(sources: [ delta_src ]).call }

      cam2 = Camera.find_by!(external_ref: "osm:node/2")
      expect(cam2.consecutive_missing_count).to be >= 1
      expect(cam2.stale).to be(true)
    end

    it "falls back to full fetch when the source does not support delta" do
      # `osm` stubs supports_delta? to return false (see the source helper above).
      described_class.new(sources: [ osm ]).call
      expect(Camera.count).to eq(2)
    end
  end
end
