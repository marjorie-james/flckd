module CameraData
  module Sources
    # Shared OpenStreetMap ALPR tagging + provenance, mixed into BOTH OSM access
    # mechanisms: the live/self-hosted Overpass API source and the PBF-extract
    # file source (ADR 0002). Keeping the tag→record mapping in ONE place
    # guarantees the two mechanisms emit byte-identical records for the same OSM
    # node — same external_ref, same fields — so switching between them (the
    # ADR 0002 escape hatch) is seamless and never forks a camera's identity.
    module OsmTagging
      # Provenance is the DATA ORIGIN — OpenStreetMap — not the access mechanism
      # (Overpass API vs. local PBF extract). Both sources declare this same
      # identity so a mechanism switch keeps one `DataSource` row and stable
      # `osm:node/<id>` external_refs (no transient duplicate cameras).
      PROVENANCE = {
        name: "OpenStreetMap",
        kind: "community",
        url: "https://www.openstreetmap.org/",
        license: "ODbL-1.0"
      }.freeze

      # ALPR selectors, kept in ONE place so the live Overpass QL (server-side
      # filter) and the PBF-file predicate (osm_alpr?) select the SAME nodes
      # (ADR 0002 lockstep). Exposed as Overpass-QL regex strings; the Ruby
      # predicate compiles them case-insensitively below.
      #
      # These are broadened from the original (surveillance:type=ALPR exact,
      # brand|operator~flock) to capture the tagging variants DeFlock contributors
      # and municipal mappers actually use — DeFlock publishes INTO OSM (it has no
      # separate API), so widening the net here is how we ingest more of its data:
      #   * surveillance:type / camera:type ~ alpr|anpr  (ANPR in surveillance:type
      #     was previously missed; only camera:type=ANPR matched)
      #   * brand | operator | MANUFACTURER ~ a vendor token (manufacturer=Flock
      #     with no brand/operator was previously missed)
      #
      # The vendor list is deliberately narrow to ALPR-SPECIFIC product/brand
      # tokens (Flock, Vigilant, ELSAG, AutoVu, Rekor, Neology). Generic CCTV
      # makers (Motorola, Genetec, Leonardo) are excluded on purpose so we never
      # dilute the avoidance layer with non-ALPR surveillance cameras.
      ALPR_TYPE_PATTERN = "alpr|anpr".freeze
      ALPR_VENDOR_PATTERN = "flock|vigilant|elsag|autovu|rekor|neology".freeze
      ALPR_TYPE_RE = /#{ALPR_TYPE_PATTERN}/i
      ALPR_VENDOR_RE = /#{ALPR_VENDOR_PATTERN}/i

      private

      # True for an OSM surveillance node that is ALPR/ANPR-flavored. Selects the
      # SAME set as the Overpass QL (via the shared ALPR_* patterns above).
      def osm_alpr?(tags)
        return false unless tags["man_made"] == "surveillance"

        "#{tags['surveillance:type']}".match?(ALPR_TYPE_RE) ||
          "#{tags['camera:type']}".match?(ALPR_TYPE_RE) ||
          "#{tags['brand']} #{tags['operator']} #{tags['manufacturer']}".match?(ALPR_VENDOR_RE)
      end

      # Maps an OSM node (id + coords + tags) to the Importer record shape. Calls
      # the shared `normalize_*` helpers on Base, so direction/type coercion is
      # identical to every other source.
      def osm_node_record(osm_id:, lat:, lng:, tags:)
        {
          external_ref: "osm:node/#{osm_id}",
          lat: lat,
          lng: lng,
          facing_direction: normalize_direction(tags["camera:direction"] || tags["direction"]),
          camera_type: normalize_camera_type(
            brand: tags["brand"] || tags["operator"] || tags["manufacturer"],
            type: tags["surveillance:type"] || tags["camera:type"]
          ),
          # Community OSM data is unverified by default; the verification layer
          # raises confidence over time.
          confidence: 0.5
        }
      end
    end
  end
end
