# Provenance for camera records. Supports the hybrid data pipeline:
# community datasets (the OpenStreetMap ALPR substrate, open-data exports) plus
# internal verification.
class DataSource < ApplicationRecord
  KINDS = %w[community internal].freeze

  has_many :cameras, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
end
