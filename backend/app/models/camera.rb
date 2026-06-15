# A known ALPR/Flock camera. Reference data sourced from the hybrid pipeline,
# never from end users. The unit of *avoidance* is its MonitoredSegment(s),
# not the point itself (see spec clarification: monitored-segment avoidance).
class Camera < ApplicationRecord
  include SpatialCoercion

  VERIFICATION_STATUSES = %w[unverified verified disputed removed].freeze

  coerce_spatial :location

  belongs_to :data_source
  has_many :monitored_segments, dependent: :destroy

  validates :location, presence: true
  # Every camera is attributable to a source record: (data_source, external_ref)
  # is the idempotency key, and external_ref is NOT NULL at the DB layer. A record
  # without one is malformed and the importer skips it rather than creating an
  # un-deduplicable anonymous row.
  validates :external_ref, presence: true
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :verification_status, inclusion: { in: VERIFICATION_STATUSES }
  validates :facing_direction,
            numericality: { greater_than_or_equal_to: 0, less_than: 360 },
            allow_nil: true
  validates :consecutive_missing_count, numericality: { greater_than_or_equal_to: 0 }

  # Cameras whose segments should be fed into routing exclusion. Removed (human)
  # and auto-retired (source stopped reporting) cameras are never avoided; disputed
  # ones only above a confidence floor.
  scope :active, -> { where.not(verification_status: "removed").where(auto_retired: false) }
  scope :routable, ->(min_confidence = 0.0) { active.where("confidence >= ?", min_confidence) }
  # Cameras present in a prior import but missing from their source's latest
  # refresh (still avoided until auto-retired).
  scope :stale, -> { where(stale: true) }

  def remove!
    update!(verification_status: "removed")
  end

  def verify!
    update!(verification_status: "verified", last_verified_at: Time.current)
  end

  # The camera's source reported it in the latest refresh: it is fresh again.
  # (The importer already stamped last_seen_in_source_at.) This is the recovery
  # path — it clears auto-retirement, so a camera that was transiently absent and
  # then reappears is avoided again. It never resurrects a human `remove!`.
  def seen_in_source!
    update!(consecutive_missing_count: 0, stale: false, auto_retired: false)
  end

  # The camera's source did NOT report it this refresh. Keep avoiding it while
  # flagged stale, and auto-retire after `limit` consecutive misses — unless it
  # is human-verified, which is exempt (FR-008/FR-009). Auto-retirement sets the
  # `auto_retired` flag (recoverable), NOT verification_status="removed" (terminal,
  # reserved for human removal).
  def mark_missing!(limit: CameraData.missing_limit)
    count = consecutive_missing_count + 1
    attrs = { consecutive_missing_count: count, stale: true }
    attrs[:auto_retired] = true if count >= limit && verification_status != "verified"
    update!(attrs)
  end
end
