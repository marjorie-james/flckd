# An INGESTED camera-data region within the configured country: where camera
# data is actually present, carrying its own freshness. Drives honest present /
# absent / not-yet-gathered signalling (FR-008) — `covers?`/`containing` answer
# "is there camera data here?", not "is this inside our country".
#
# Map framing is NOT derived from these rows; the whole-country extent comes from
# Geocoding::CountryRegistry (see CoverageController#bounds), so a sparse data
# footprint never shrinks the map (FR-007). Freshness is set per region as each
# is refreshed (DataRefreshJob), never globally.
class CoverageArea < ApplicationRecord
  include SpatialCoercion

  coerce_spatial :region

  validates :name, presence: true
  validates :region, presence: true

  # Data-regions that spatially contain the given lon/lat point (camera-data
  # presence at the point).
  scope :containing, ->(lon, lat) {
    point = "SRID=4326;POINT(#{lon.to_f} #{lat.to_f})"
    where("ST_Contains(region, ST_GeomFromEWKT(?))", point)
  }

  def self.covers?(lon, lat)
    containing(lon, lat).exists?
  end
end
