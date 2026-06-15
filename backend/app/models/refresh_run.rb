# Audit record of a single camera-data refresh (feature 003). Reference-data
# only — never user data (no coordinates, IPs, origins, destinations, routes).
#
# `per_source` maps a DataSource name to its outcome for the run:
#   { "added" =>, "updated" =>, "skipped" =>, "retired" =>, "status" =>, "error_class" => }
# `totals` aggregates the integer counts across sources.
class RefreshRun < ApplicationRecord
  TRIGGERS = %w[scheduled manual].freeze
  STATUSES = %w[running success partial failed].freeze

  validates :trigger, inclusion: { in: TRIGGERS }
  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }
  # In-progress run(s). The job resumes the existing one after an interruption
  # rather than starting a second (FR-014).
  scope :running, -> { where(status: "running") }

  # True while a run is in progress — used to prevent overlapping refreshes.
  def self.running?
    running.exists?
  end
end
