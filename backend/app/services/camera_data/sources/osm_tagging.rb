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

      private

      # True for an OSM surveillance node that is ALPR/ANPR/Flock-flavored — the
      # exact set the Overpass QL selects: man_made=surveillance AND one of
      # surveillance:type=ALPR, camera:type~alpr|anpr, brand|operator~flock.
      def osm_alpr?(tags)
        return false unless tags["man_made"] == "surveillance"

        "#{tags['surveillance:type']}".casecmp?("ALPR") ||
          "#{tags['camera:type']}".downcase.match?(/alpr|anpr/) ||
          "#{tags['brand']} #{tags['operator']}".downcase.include?("flock")
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
