# Camera-data aggregation configuration (feature 003).
#
# CAMERA_REFRESH_MISSING_LIMIT — how many consecutive daily refreshes a camera
# may be absent from its source before it is auto-retired. Auto-retirement sets
# the RECOVERABLE `auto_retired` flag (Camera#mark_missing!), which excludes the
# camera from routing but is automatically revived if the source reports it again
# (Camera#seen_in_source!). This is distinct from verification_status="removed",
# the TERMINAL human-only removal path (Camera#remove!). Verified cameras are
# exempt from auto-retirement. Default 3 (per spec clarification); ENV-overridable
# for ops tuning.
#
# CAMERA_OSM_SOURCE — which mechanism supplies the OpenStreetMap ALPR substrate
# (ADR 0002). The DATA and license are identical either way (OpenStreetMap,
# ODbL); only the access path differs:
#   "pbf"      (default) read a prebuilt GeoJSON filtered from the OSM PBF
#              extract the geo stack already downloads
#              (infra/scripts/build-cameras.sh). One local file, no API calls.
#   "overpass" the live/self-hosted Overpass API, tiled over CONUS (the
#              pre-0002 path). Escape hatch — flip to this for near-live data or
#              a self-hosted Overpass (set OVERPASS_URL). See
#              docs/runbooks/geo-stack.md ("Camera substrate").
#
# CAMERA_OSM_GEOJSON_PATH — where the PBF-derived cameras GeoJSON lives (pbf
# mode). Defaults to storage/cameras.geojson; in production the daily build/
# delivery drops the file here (see the runbook).
module CameraData
  mattr_accessor :missing_limit, default: Integer(ENV.fetch("CAMERA_REFRESH_MISSING_LIMIT", 3))

  mattr_accessor :osm_source, default: ENV.fetch("CAMERA_OSM_SOURCE", "pbf")

  mattr_accessor :osm_extract_geojson_path,
                 default: ENV.fetch("CAMERA_OSM_GEOJSON_PATH", Rails.root.join("storage", "cameras.geojson").to_s)
end
