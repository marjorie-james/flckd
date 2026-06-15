# A region where camera data exists and avoidance is meaningful (US launch: US).
# Used to decide whether to advertise avoidance for a point and to surface
# freshness/coverage warnings (FR-018).
class CoverageArea < ApplicationRecord
  include SpatialCoercion

  coerce_spatial :region

  validates :name, presence: true
  validates :region, presence: true

  # Coverage areas that spatially contain the given lon/lat point.
  scope :containing, ->(lon, lat) {
    point = "SRID=4326;POINT(#{lon.to_f} #{lat.to_f})"
    where("ST_Contains(region, ST_GeomFromEWKT(?))", point)
  }

  def self.covers?(lon, lat)
    containing(lon, lat).exists?
  end

  # Bounding box enclosing every coverage region, as [[west, south], [east, north]]
  # (lng/lat corners). Returns nil when no coverage exists. Lets the client frame
  # the map on whatever region this deployment covers, with no hardcoded state —
  # ST_Extent aggregates all rows into one box, NULL (→ nil) for an empty table.
  def self.bounds
    west, south, east, north = pick(Arel.sql(
      "ST_XMin(ST_Extent(region)), ST_YMin(ST_Extent(region)), " \
      "ST_XMax(ST_Extent(region)), ST_YMax(ST_Extent(region))"
    ))
    return nil if west.nil?

    [ [ west, south ], [ east, north ] ]
  end
end
