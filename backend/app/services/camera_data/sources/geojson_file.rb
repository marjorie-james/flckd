module CameraData
  module Sources
    # Imports cameras from a GeoJSON FeatureCollection of Point features on disk.
    #
    # This is the generic ingestion path for first-party-friendly exports:
    # municipal open-data portals, public-records / FOIA responses, and community
    # dataset exports (e.g. DeFlock). Because provenance and license vary per
    # file, they are supplied at construction time rather than hard-coded — every
    # imported camera stays attributable to its licensed origin.
    #
    # Expected shape:
    #   { "type": "FeatureCollection",
    #     "features": [
    #       { "type": "Feature",
    #         "geometry": { "type": "Point", "coordinates": [lng, lat] },
    #         "properties": { "id":, "brand":, "type":, "direction":, "confidence": } }
    #     ] }
    class GeojsonFile < Base
      attr_reader :source_name, :source_kind, :source_url, :license

      def initialize(path:, name:, kind: "community", url: nil, license: nil)
        @path = path
        @source_name = name
        @source_kind = kind
        @source_url = url
        @license = license
      end

      def fetch
        data = JSON.parse(File.read(@path))
        features = data.is_a?(Hash) ? Array(data["features"]) : []
        features.filter_map { |feature| normalize(feature) }
      end

      private

      def normalize(feature)
        geometry = feature["geometry"] || {}
        return nil unless geometry["type"] == "Point"

        lng, lat = geometry["coordinates"]
        return nil if lat.nil? || lng.nil?

        props = feature["properties"] || {}
        {
          external_ref: external_ref_for(feature, props),
          lat: lat,
          lng: lng,
          facing_direction: normalize_direction(props["direction"] || props["facing_direction"] || props["bearing"]),
          camera_type: normalize_camera_type(brand: props["brand"] || props["operator"], type: props["type"] || props["camera_type"]),
          confidence: confidence_for(props)
        }
      end

      # Prefer a stable id from the source; otherwise derive a deterministic ref
      # from coordinates so re-imports stay idempotent (no Random/timestamp).
      #
      # Caveat for id-less sources: if a feature's coordinates shift past 6 decimals
      # (~0.11 m) between exports, it gets a new ref (looks added) and the old ref
      # auto-retires — id-less GeoJSON simply cannot track a move as a move. We keep
      # 6 decimals deliberately (a coarser grid would merge genuinely-distinct nearby
      # cameras). The old ref's retirement is now recoverable (auto_retired, not a
      # terminal "removed"), so this churn no longer strands a permanent ghost row.
      def external_ref_for(feature, props)
        id = feature["id"] || props["id"] || props["external_ref"]
        return id.to_s if id.present?

        lng, lat = feature.dig("geometry", "coordinates")
        "geojson:#{format('%.6f', lat)},#{format('%.6f', lng)}"
      end

      def confidence_for(props)
        value = Float(props["confidence"], exception: false)
        return 0.5 if value.nil?

        value.clamp(0.0, 1.0)
      end
    end
  end
end
