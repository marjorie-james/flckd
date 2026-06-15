module CameraData
  module Sources
    # Reads ALPR camera nodes from a GeoJSON file that was filtered out of the OSM
    # PBF extract the geo stack already downloads (ADR 0002) — the DEFAULT camera
    # substrate. Produced by `infra/scripts/build-cameras.sh`:
    #
    #   osmium tags-filter extract.osm.pbf n/man_made=surveillance -o surveillance.pbf
    #   osmium export surveillance.pbf -f geojson --add-unique-id=type_id -o cameras.geojson
    #
    # That emits Point features whose `properties` are the raw OSM tags and whose
    # `id` is the osmium type_id form ("n<nodeid>"). We narrow to ALPR/Flock with
    # the SAME predicate the Overpass QL uses (via OsmTagging) and re-derive the
    # canonical `osm:node/<id>` external_ref, so this source and Overpass are
    # interchangeable — same records, same provenance, same identity.
    #
    # This is the same OpenStreetMap origin + ODbL license as Sources::Overpass;
    # they differ only in mechanism (local extract vs. live API). Overpass remains
    # available as a config-flippable escape hatch (CAMERA_OSM_SOURCE=overpass).
    class OsmExtractFile < GeojsonFile
      include OsmTagging

      def initialize(path: CameraData.osm_extract_geojson_path)
        super(path: path, **OsmTagging::PROVENANCE)
      end

      private

      # Reuses GeojsonFile#fetch (file read + feature iteration); overrides the
      # mapping because the properties here are raw OSM tag keys
      # (surveillance:type, camera:direction, …), not the open-data property names
      # GeojsonFile assumes.
      def normalize(feature)
        geometry = feature["geometry"] || {}
        return nil unless geometry["type"] == "Point"

        lng, lat = geometry["coordinates"]
        return nil if lat.nil? || lng.nil?

        tags = feature["properties"] || {}
        return nil unless osm_alpr?(tags)

        osm_id = node_id(feature)
        return nil if osm_id.nil?

        osm_node_record(osm_id: osm_id, lat: lat, lng: lng, tags: tags)
      end

      # osmium `--add-unique-id=type_id` writes the OSM id as "n<nodeid>" (node),
      # exposed as the feature "id" or an "@id"/"id" property depending on the
      # exporter version. We only ingest nodes, so accept the node form and strip
      # the leading "n" to recover the bare OSM node id.
      def node_id(feature)
        raw = (feature["id"] || feature.dig("properties", "@id") || feature.dig("properties", "id")).to_s
        match = raw.match(/\An?(\d+)\z/)
        match && match[1]
      end
    end
  end
end
