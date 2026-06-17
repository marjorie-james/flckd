require "rails_helper"

RSpec.describe CameraData::TiledRefresh do
  # Two disjoint tiles, each with one camera at its centre.
  let(:tile_a) { { south: 41.0, west: -94.0, north: 42.0, east: -93.0 } }
  let(:tile_b) { { south: 42.0, west: -94.0, north: 43.0, east: -93.0 } }
  let(:cam_a) { { external_ref: "osm:a", lat: 41.5, lng: -93.5, camera_type: "Flock", confidence: 0.5 } }
  let(:cam_b) { { external_ref: "osm:b", lat: 42.5, lng: -93.5, camera_type: "Flock", confidence: 0.5 } }

  def src(records, raises: nil)
    s = instance_double(
      CameraData::Sources::Base,
      source_name: "OpenStreetMap", source_kind: "community",
      source_url: nil, license: "ODbL-1.0"
    )
    allow(s).to receive(:supports_delta?).and_return(false)
    raises ? allow(s).to(receive(:fetch).and_raise(raises)) : allow(s).to(receive(:fetch).and_return(records))
    s
  end

  # Factory dispatching per tile from a {bbox => source} map.
  def factory(map) = ->(bbox) { map.fetch(bbox) }

  it "imports each tile and reports per-tile counts" do
    result = described_class.new(
      tiles: [ tile_a, tile_b ],
      source_factory: factory(tile_a => src([ cam_a ]), tile_b => src([ cam_b ]))
    ).call

    expect(result.status).to eq("success")
    expect(Camera.count).to eq(2)
    osm = result.per_source["OpenStreetMap"]
    expect(osm).to include("added" => 2, "tiles_ok" => 2, "tiles_failed" => 0)
  end

  it "isolates a failed tile and reports partial" do
    result = described_class.new(
      tiles: [ tile_a, tile_b ],
      source_factory: factory(tile_a => src([ cam_a ]), tile_b => src(nil, raises: StandardError.new("down")))
    ).call

    expect(result.status).to eq("partial")
    expect(Camera.count).to eq(1)
    expect(result.per_source["OpenStreetMap"]).to include("tiles_failed" => 1, "error_class" => "StandardError")
  end

  it "reconciles only within successfully-fetched tiles — a failed tile never retires its cameras" do
    # First run: both tiles succeed; both cameras seen.
    described_class.new(
      tiles: [ tile_a, tile_b ],
      source_factory: factory(tile_a => src([ cam_a ]), tile_b => src([ cam_b ]))
    ).call
    a = Camera.find_by!(external_ref: "osm:a")
    b = Camera.find_by!(external_ref: "osm:b")

    # Second run: tile A succeeds but no longer reports cam_a; tile B FAILS.
    described_class.new(
      tiles: [ tile_a, tile_b ],
      source_factory: factory(tile_a => src([]), tile_b => src(nil, raises: StandardError.new("down")))
    ).call

    # Cam A's tile succeeded and it was missing → flagged stale.
    expect(a.reload.stale).to be(true)
    expect(a.consecutive_missing_count).to eq(1)

    # Cam B's tile FAILED → left completely untouched (no false retirement).
    expect(b.reload.stale).to be(false)
    expect(b.consecutive_missing_count).to eq(0)
  end

  it "resumes from a checkpointed cursor without re-fetching completed tiles (JSON-safe)" do
    fetched = []
    factory = lambda do |bbox|
      s = instance_double(
        CameraData::Sources::Base,
        source_name: "OpenStreetMap", source_kind: "community", source_url: nil, license: "ODbL-1.0"
      )
      allow(s).to receive(:supports_delta?).and_return(false)
      allow(s).to receive(:fetch) { fetched << bbox; bbox == tile_a ? [ cam_a ] : [ cam_b ] }
      s
    end

    # Execution 1: import tile A, then "interrupt" with the cursor checkpointed.
    first = described_class.new(tiles: [ tile_a, tile_b ], source_factory: factory)
    state = first.blank_state
    first.import_next(state)
    expect(state["i"]).to eq(1)
    expect(fetched).to eq([ tile_a ])

    # The cursor rides the continuation as JSON — simulate that round-trip.
    state = JSON.parse(state.to_json)

    # Execution 2 (resume): a fresh instance continues from the cursor.
    second = described_class.new(tiles: [ tile_a, tile_b ], source_factory: factory, cutoff: 1.minute.ago)
    second.import_next(state) until state["i"] >= second.size
    result = second.finalize(state)

    expect(fetched).to eq([ tile_a, tile_b ]) # tile A fetched once — not re-fetched on resume
    expect(result.status).to eq("success")
    expect(Camera.count).to eq(2)
  end

  it "finalizes a fully-checkpointed resume even when import_next never runs again" do
    # Simulate a continuation that imported the only tile, checkpointed the cursor,
    # then was interrupted before finalize — so @source_name is never set on resume.
    road_lookup = Class.new do
      def nearest_road(lng:, lat:)
        { osm_way_id: 999, geometry_ewkt: "SRID=4326;LINESTRING(#{lng} #{lat}, #{lng + 0.001} #{lat})", distance_m: 4.0 }
      end
    end.new

    first = described_class.new(tiles: [ tile_a ], source_factory: factory(tile_a => src([ cam_a ])))
    state = first.blank_state
    first.import_next(state)
    expect(state["i"]).to eq(first.size) # last tile imported + checkpointed

    # Cursor rides the continuation as JSON.
    state = JSON.parse(state.to_json)

    # Resume on a FRESH instance: finalize runs with state["i"] == size and no
    # import_next call, so source resolution can't rely on @source_name.
    second = described_class.new(
      tiles: [ tile_a ],
      source_factory: factory(tile_a => src([ cam_a ])),
      road_lookup: road_lookup,
      cutoff: 1.minute.ago
    )
    result = second.finalize(state)

    # data_source resolved → snap ran (camera got a monitored segment).
    cam = Camera.find_by!(external_ref: "osm:a")
    expect(cam.monitored_segments.count).to eq(1)
    expect(result.snapped_total).to eq(1)
    # per_source is keyed by the source name, not nil.
    expect(result.per_source.keys).to eq([ "OpenStreetMap" ])
    expect(result.per_source["OpenStreetMap"]).to include("tiles_ok" => 1)
  end

  it "skips snapping when no road lookup is configured" do
    result = described_class.new(
      tiles: [ tile_a ], source_factory: factory(tile_a => src([ cam_a ])), road_lookup: nil
    ).call
    expect(result.snapped_total).to eq(0)
  end

  describe "delta import" do
    let(:cam_c) { { external_ref: "osm:c", lat: 41.5, lng: -93.5, camera_type: "Flock", confidence: 0.5 } }

    # A source that supports delta fetch and returns a specific diff.
    def delta_src(since:, upserted:, deleted_refs:)
      s = instance_double(
        CameraData::Sources::Base,
        source_name: "OpenStreetMap", source_kind: "community",
        source_url: nil, license: "ODbL-1.0"
      )
      allow(s).to receive(:supports_delta?).with(since: since).and_return(true)
      allow(s).to receive(:fetch_delta).with(since: since).and_return(
        { upserted: upserted, deleted_refs: deleted_refs }
      )
      s
    end

    it "uses fetch_delta when the source supports it and last_imported_at is set" do
      # Seed the DataSource with a last_imported_at so delta_since is non-nil.
      ds = DataSource.create!(name: "OpenStreetMap", kind: "community",
                              license: "ODbL-1.0", last_imported_at: 1.day.ago)
      since = ds.last_imported_at

      result = described_class.new(
        tiles: [ tile_a ],
        source_factory: ->(bbox) { delta_src(since: since, upserted: [ cam_a ], deleted_refs: []) }
      ).call

      expect(result.status).to eq("success")
      expect(Camera.find_by(external_ref: "osm:a")).to be_present
    end

    it "bulk-touches unchanged cameras so the reconciler does not flag them as missing" do
      # First full run: import cam_a and cam_b.
      described_class.new(
        tiles: [ tile_a, tile_b ],
        source_factory: factory(tile_a => src([ cam_a ]), tile_b => src([ cam_b ]))
      ).call
      ds = DataSource.find_by!(name: "OpenStreetMap")
      since = ds.last_imported_at

      # Delta run: only cam_a changed (cam_b is unchanged, should not be flagged).
      described_class.new(
        tiles: [ tile_a ],
        source_factory: ->(bbox) { delta_src(since: since, upserted: [ cam_a ], deleted_refs: []) }
      ).call

      b = Camera.find_by!(external_ref: "osm:b")
      expect(b.consecutive_missing_count).to eq(0)
      expect(b.stale).to be(false)
    end

    it "retires explicitly deleted cameras via the reconciler" do
      # Full run: cam_a and cam_b exist.
      described_class.new(
        tiles: [ tile_a, tile_b ],
        source_factory: factory(tile_a => src([ cam_a ]), tile_b => src([ cam_b ]))
      ).call
      ds = DataSource.find_by!(name: "OpenStreetMap")
      since = ds.last_imported_at

      # Delta run: cam_b deleted in OSM (in deleted_refs), cam_a unchanged.
      described_class.new(
        tiles: [ tile_a ],
        source_factory: ->(bbox) { delta_src(since: since, upserted: [], deleted_refs: [ "osm:b" ]) }
      ).call

      b = Camera.find_by!(external_ref: "osm:b")
      expect(b.consecutive_missing_count).to be >= 1
      expect(b.stale).to be(true)
    end

    it "falls back to full fetch when last_imported_at is nil (first run)" do
      fetched_via_full = false
      full_src = instance_double(
        CameraData::Sources::Base,
        source_name: "OpenStreetMap", source_kind: "community",
        source_url: nil, license: "ODbL-1.0"
      )
      allow(full_src).to receive(:supports_delta?).and_return(false)
      allow(full_src).to receive(:fetch) { fetched_via_full = true; [ cam_a ] }

      described_class.new(tiles: [ tile_a ], source_factory: ->(_bbox) { full_src }).call

      expect(fetched_via_full).to be(true)
      expect(Camera.find_by(external_ref: "osm:a")).to be_present
    end
  end
end
