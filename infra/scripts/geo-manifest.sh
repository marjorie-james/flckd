#!/usr/bin/env bash
#
# Generate / verify a versioned manifest for the self-hosted geo artifacts
# (routing graph + vector tiles, built from a public OSM extract). The manifest
# records provenance (region, source extract, build time) and a sha256 + size for
# each artifact, so a deploy can pull a specific, pinned, integrity-checked build
# (ADR 0001 — OSM substrate automation).
#
# Usage:
#   infra/scripts/geo-manifest.sh generate   # writes infra/build/manifest.{json,sha256}
#   infra/scripts/geo-manifest.sh verify     # checks artifacts against manifest.sha256
#
# Env: REGION (label), REGION_URL (source extract), BUILD_DIR (output dir).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)" # infra/
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
MANIFEST_JSON="${BUILD_DIR}/manifest.json"
MANIFEST_SUMS="${BUILD_DIR}/manifest.sha256"

# Servable artifacts, relative to infra/ (the intermediate valhalla_tiles/ dir is
# captured in valhalla_tiles.tar, so it isn't listed).
ARTIFACTS=(
  "data/extract.osm.pbf"
  "routing/data/valhalla.json"
  "routing/data/valhalla_tiles.tar"
  "tiles/data/tiles.pmtiles"
)

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

generate() {
  local region source_url generated_at last i rel path bytes sum comma
  region="${REGION:-iowa}"
  source_url="${REGION_URL:-https://download.geofabrik.de/north-america/us/iowa-latest.osm.pbf}"
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "${BUILD_DIR}"
  : > "${MANIFEST_SUMS}"

  {
    echo "{"
    echo "  \"region\": \"${region}\","
    echo "  \"source_url\": \"${source_url}\","
    echo "  \"generated_at\": \"${generated_at}\","
    echo "  \"artifacts\": ["
    last=$(( ${#ARTIFACTS[@]} - 1 ))
    for i in "${!ARTIFACTS[@]}"; do
      rel="${ARTIFACTS[$i]}"
      path="${ROOT}/${rel}"
      [ -f "${path}" ] || { echo "error: missing artifact ${rel} (run build-geo.sh first)" >&2; exit 1; }
      bytes="$(wc -c < "${path}" | tr -d ' ')"
      sum="$(sha256_of "${path}")"
      comma=","; [ "${i}" -eq "${last}" ] && comma=""
      echo "    { \"file\": \"${rel}\", \"bytes\": ${bytes}, \"sha256\": \"${sum}\" }${comma}"
      echo "${sum}  ${rel}" >> "${MANIFEST_SUMS}"
    done
    echo "  ]"
    echo "}"
  } > "${MANIFEST_JSON}"

  echo "Wrote ${MANIFEST_JSON} and ${MANIFEST_SUMS}"
  cat "${MANIFEST_JSON}"
}

verify() {
  local sums="${1:-${MANIFEST_SUMS}}"
  [ -f "${sums}" ] || { echo "error: ${sums} not found (generate first)" >&2; exit 1; }
  # Checksums are recorded relative to infra/, so verify from there.
  cd "${ROOT}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "${sums}"
  else
    shasum -a 256 -c "${sums}"
  fi
  echo "All geo artifacts match the manifest."
}

case "${1:-generate}" in
  generate) generate ;;
  verify)   verify "${2:-}" ;;
  *) echo "usage: $0 {generate|verify}" >&2; exit 1 ;;
esac
