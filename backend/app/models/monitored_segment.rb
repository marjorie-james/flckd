# A road segment monitored by a camera. The camera is snapped to its nearest
# road/intersection; osm_way_id matches the routing engine's OSM way IDs so the
# routing exclusion is exact.
class MonitoredSegment < ApplicationRecord
  include SpatialCoercion

  DIRECTIONS = %w[both forward backward].freeze

  coerce_spatial :geometry

  belongs_to :camera

  validates :osm_way_id, presence: true
  validates :geometry, presence: true
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :snap_distance_m, numericality: { greater_than_or_equal_to: 0 }

  # Segments eligible for routing exclusion (their camera is active/routable).
  scope :for_routing, ->(min_confidence = 0.0) {
    joins(:camera).merge(Camera.routable(min_confidence))
  }
end
