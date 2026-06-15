require "rails_helper"

RSpec.describe CameraData::Importer do
  let(:records) do
    [
      { external_ref: "a", lat: 39.7392, lng: -104.9903, confidence: 0.9, camera_type: "Flock" },
      { external_ref: "b", lat: 39.7300, lng: -104.9300, confidence: 0.6, camera_type: "ALPR" }
    ]
  end

  it "imports new cameras and records provenance" do
    importer = described_class.new(source_name: "deflock", source_kind: "community")
    stats = importer.import(records)

    expect(stats.added).to eq(2)
    expect(stats.total).to eq(2)
    expect(Camera.count).to eq(2)
    expect(DataSource.find_by(name: "deflock").last_imported_at).to be_present
  end

  it "is idempotent on (data_source, external_ref)" do
    importer = described_class.new(source_name: "deflock")
    importer.import(records)
    second = importer.import(records) # second run updates, doesn't duplicate

    expect(Camera.count).to eq(2)
    expect(second.added).to eq(0)
    expect(second.updated).to eq(2)
  end

  it "stamps last_seen_in_source_at on every imported camera (T017)" do
    freeze = Time.utc(2026, 6, 1, 10, 0, 0)
    travel_to(freeze) do
      described_class.new(source_name: "deflock").import(records)
    end
    expect(Camera.pluck(:last_seen_in_source_at)).to all(be_within(1.second).of(freeze))
  end

  it "records the source license on the DataSource (FR-004)" do
    source = instance_double(
      CameraData::Sources::Base,
      source_name: "OpenStreetMap", source_kind: "community",
      source_url: "https://www.openstreetmap.org/", license: "ODbL-1.0"
    )
    described_class.for_source(source).import(records)
    expect(DataSource.find_by(name: "OpenStreetMap").license).to eq("ODbL-1.0")
  end

  it "refuses a source with no license (FR-005)" do
    source = instance_double(
      CameraData::Sources::Base,
      source_name: "Mystery Feed", source_kind: "community", source_url: nil, license: nil
    )
    expect { described_class.for_source(source) }.to raise_error(ArgumentError, /license/)
  end

  it "skips malformed records without aborting the import" do
    bad = records + [ { external_ref: "c", lat: nil, lng: nil, camera_type: "ALPR" } ]
    stats = described_class.new(source_name: "deflock").import(bad)
    expect(stats.added).to eq(2)
    expect(stats.skipped).to eq(1)
  end

  it "skips a record with no external_ref (now required — no anonymous rows)" do
    no_ref = records + [ { lat: 39.9, lng: -105.0, camera_type: "Flock", confidence: 0.5 } ]
    stats = described_class.new(source_name: "deflock").import(no_ref)
    expect(stats.added).to eq(2)
    expect(stats.skipped).to eq(1)
  end

  it "collapses a duplicate external_ref within one batch (added then updated)" do
    dup = records + [ { external_ref: "a", lat: 39.9, lng: -105.0, confidence: 0.7, camera_type: "Flock" } ]
    stats = described_class.new(source_name: "deflock").import(dup)

    expect(Camera.count).to eq(2)
    expect(stats.added).to eq(2)
    expect(stats.updated).to eq(1)
  end

  it "looks existing cameras up in a single batched query, not one per record" do
    importer = described_class.new(source_name: "deflock")
    importer.import(records) # seed two cameras

    camera_selects = 0
    counter = lambda do |_n, _s, _f, _id, payload|
      camera_selects += 1 if payload[:sql] =~ /SELECT.+FROM "cameras"/
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      importer.import(records) # re-import the same two
    end

    expect(camera_selects).to eq(1) # one IN (...) lookup, not one find_by per record
  end

  describe "re-snapping moved cameras (H2)" do
    let(:geom) { "SRID=4326;LINESTRING(-104.9905 39.7392, -104.9901 39.7392)" }

    def seed_with_segment
      importer = described_class.new(source_name: "deflock")
      importer.import([ { external_ref: "a", lat: 39.7392, lng: -104.9903, confidence: 0.9 } ])
      cam = Camera.find_by(external_ref: "a")
      seg = cam.monitored_segments.create!(osm_way_id: 1, geometry: geom, direction: "both", snap_distance_m: 3.0)
      [ importer, cam, seg ]
    end

    it "drops the stale monitored segment when the camera's location changes" do
      importer, cam, seg = seed_with_segment
      importer.import([ { external_ref: "a", lat: 39.7395, lng: -104.9900, confidence: 0.9 } ]) # ~35 m away

      expect(MonitoredSegment.exists?(seg.id)).to be(false)
      expect(cam.reload.monitored_segments).to be_empty
    end

    it "keeps the segment when the camera has not moved" do
      importer, _cam, seg = seed_with_segment
      importer.import([ { external_ref: "a", lat: 39.7392, lng: -104.9903, confidence: 0.9 } ]) # same coords

      expect(MonitoredSegment.exists?(seg.id)).to be(true)
    end
  end

  it "isolates a record that fails at the DB level, skipping only it" do
    # Force a DB-level failure (one that validations don't catch) on record "b"
    # to exercise the slice-rollback → record-by-record replay path.
    allow_any_instance_of(Camera).to receive(:save!).and_wrap_original do |original, *args|
      raise ActiveRecord::StatementInvalid, "boom" if original.receiver.external_ref == "b"

      original.call(*args)
    end

    stats = described_class.new(source_name: "deflock").import(records)

    expect(stats.added).to eq(1)
    expect(stats.skipped).to eq(1)
    expect(Camera.where(external_ref: "a")).to exist
    expect(Camera.where(external_ref: "b")).not_to exist
  end
end
