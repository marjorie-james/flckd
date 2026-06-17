namespace :camera_data do
  desc "Import camera data from a source (SOURCE=fixture|pbf|overpass|geojson|aggregate)"
  task import: :environment do
    source = ENV.fetch("SOURCE", "fixture")
    road_lookup = CameraData::ValhallaRoadLookup.new

    case source
    when "pbf"
      # Default OpenStreetMap substrate (ADR 0002): ALPR nodes filtered from the
      # local OSM extract into a GeoJSON by infra/scripts/build-cameras.sh — no
      # Overpass API, no rate limit. Reads CAMERA_OSM_GEOJSON_PATH.
      report CameraData::AggregateImport.new(
        sources: [ CameraData::Sources::OsmExtractFile.new ], road_lookup: road_lookup
      ).call

    when "fixture"
      path = Rails.root.join("db", "fixtures", "cameras.json")
      records = JSON.parse(File.read(path), symbolize_names: true)
      stats = CameraData::Importer.new(source_name: "fixture", source_kind: "community").import(records)
      puts "Imported #{stats.total} fixture cameras (#{stats.added} new, #{stats.updated} updated)."

      # Snap newly-imported cameras to monitored road segments via the routing
      # graph (Valhalla /locate). Idempotent (skips already-snapped cameras);
      # best-effort if the routing service is unavailable.
      refs = records.map { |r| r[:external_ref] }
      unsnapped = Camera.where(external_ref: refs).left_joins(:monitored_segments)
                        .where(monitored_segments: { id: nil }).distinct
      snapped = CameraData::SegmentSnapper.new(road_lookup: road_lookup).snap_all(unsnapped)
      puts "Snapped #{snapped.size} camera(s) to monitored road segments."

    when "overpass"
      # OSM ALPR/Flock nodes. BBOX="south,west,north,east"; defaults to US tiles.
      report CameraData::AggregateImport.new(sources: [ overpass_source ], road_lookup: road_lookup).call

    when "geojson"
      # Generic open-data / FOIA / community export.
      # GEOJSON_PATH=... NAME="City Open Data" [URL=...] [LICENSE=...] [KIND=community|internal]
      report CameraData::AggregateImport.new(sources: [ geojson_source ], road_lookup: road_lookup).call

    when "aggregate"
      # Run the live OpenStreetMap source (US-wide; DeFlock feeds this same OSM
      # substrate) plus an optional open-data file into the source-of-truth table.
      sources = [ overpass_source ]
      sources << geojson_source if ENV["GEOJSON_PATH"].present?
      report CameraData::AggregateImport.new(sources: sources, road_lookup: road_lookup).call

    else
      abort "Unknown SOURCE=#{source}. Supported: fixture, pbf, overpass, geojson, aggregate."
    end
  end

  desc "Backfill missing monitored segments (e.g. opposing carriageways) for already-snapped cameras"
  task backfill_segments: :environment do
    road_lookup = CameraData::ValhallaRoadLookup.new
    cameras = Camera.all
    before = MonitoredSegment.count
    # Idempotent per (camera, osm_way_id): only the carriageways a camera is
    # missing get added, so this is safe to re-run.
    added = CameraData::SegmentSnapper.new(road_lookup: road_lookup).snap_all(cameras)
    puts "Added #{added.size} monitored segment(s) across #{cameras.count} camera(s) " \
         "(#{before} → #{MonitoredSegment.count})."
  end

  namespace :refresh do
    desc "Show recent refresh runs (per-source counts). Append -- --json for machine output (FR-013)"
    task status: :environment do
      status = CameraData::RefreshStatus.new
      if ARGV.include?("--json")
        require "json"
        puts JSON.pretty_generate(status.as_json)
      else
        puts status.to_text
      end
    end
  end

  desc "Run a full aggregate refresh now (all live sources, US-wide) — operator-triggered (FR-018)"
  task refresh: :environment do
    run = DataRefreshJob.new.perform("aggregate", trigger: "manual")
    if run == :skipped
      puts "Refresh skipped — another run is already in progress."
    else
      puts "Refresh (#{run.trigger}) #{run.status} in #{run.duration_ms}ms."
      run.per_source.each do |name, o|
        puts CameraData::RefreshStatus.format_source(name, o)
      end
    end
  end
end

def overpass_source
  if ENV["BBOX"].present?
    CameraData::Sources::Overpass.new(bbox: parse_bbox(ENV["BBOX"]))
  else
    CameraData::Sources::Overpass.new(tiles: CameraData::Sources::UsTiles.cells)
  end
end

def geojson_source
  CameraData::Sources::GeojsonFile.new(
    path: ENV.fetch("GEOJSON_PATH"),
    name: ENV.fetch("NAME"),
    kind: ENV.fetch("KIND", "community"),
    url: ENV["URL"],
    license: ENV["LICENSE"]
  )
end

def parse_bbox(raw)
  abort 'BBOX="south,west,north,east" is required' if raw.blank?
  south, west, north, east = raw.split(",").map { |v| Float(v) }
  { south:, west:, north:, east: }
rescue ArgumentError
  abort 'BBOX must be four comma-separated numbers: "south,west,north,east"'
end

def report(result)
  result.per_source.each do |name, o|
    puts CameraData::RefreshStatus.format_source(name, o, counts: %w[added updated skipped])
  end
  t = result.totals
  puts "Status: #{result.status}  added=#{t['added']} updated=#{t['updated']} skipped=#{t['skipped']}  snapped=#{result.snapped_total}"
  puts "Cameras in database now: #{Camera.count}."

  # Fail loudly when no source succeeded. AggregateImport isolates a per-source
  # failure (e.g. the public Overpass API rate-limiting/timing out) and returns
  # without raising, preserving last-good data — but a non-success run must NOT
  # exit 0, or callers like the setup script report a false "Real cameras
  # imported" while only the demo fixtures remain.
  unless result.status == "success"
    abort "Camera import did not succeed (status: #{result.status}). The source may be " \
          "rate-limited or unreachable — the public Overpass API throttles aggressively. " \
          "Wait a minute and retry the same command."
  end
end
