module CameraData
  # Imports camera records from open/community datasets (the OpenStreetMap ALPR
  # substrate, open-data exports) into the local Camera table, recording
  # provenance. Idempotent on
  # (data_source, external_ref). After import, SegmentSnapper snaps each camera
  # to the road it monitors.
  #
  # `records` is an array of hashes:
  #   { external_ref:, lat:, lng:, facing_direction:, camera_type:, confidence: }
  class Importer
    # Per-import outcome counts. `total` is the number of cameras successfully
    # persisted (added + updated); `skipped` counts malformed/invalid records.
    Stats = Struct.new(:added, :updated, :skipped, keyword_init: true) do
      def total = added + updated
    end

    # Builds an Importer from a CameraData::Sources::Base, carrying its declared
    # provenance (name/kind/url/license) onto every imported camera. Refuses a
    # source with no license — only permissively-licensed sources are ingested
    # and the license is recorded for attribution (FR-005).
    def self.for_source(source)
      if source.license.blank?
        raise ArgumentError, "source '#{source.source_name}' has no license — refusing to import (FR-005)"
      end

      new(
        source_name: source.source_name,
        source_kind: source.source_kind,
        source_url: source.source_url,
        source_license: source.license
      )
    end

    # Direct construction is for LOCAL/FIXTURE data only (e.g. the seed/fixture
    # rake task), where there is no external source to attribute. Every real
    # external source MUST go through `.for_source`, which enforces the license
    # requirement (FR-005). Keep it that way — do not point external imports here.
    def initialize(source_name:, source_kind: "community", source_url: nil, source_license: nil)
      @source = DataSource.find_or_create_by!(name: source_name) do |s|
        s.kind = source_kind
        s.url = source_url
        s.license = source_license
      end
      # Keep provenance current on re-import (e.g. a license/url was added later)
      # without clobbering existing values with nils.
      changed = { url: source_url, license: source_license }.compact.select { |k, v| @source[k] != v }
      @source.update!(changed) if changed.any?
    end

    # Rows are processed in batches so a nationwide import (tens of thousands of
    # cameras) never holds one giant transaction open or loads every existing row
    # into memory at once.
    BATCH_SIZE = 1_000
    private_constant :BATCH_SIZE

    def import(records)
      added = updated = skipped = 0
      now = Time.current

      Array(records).each_slice(BATCH_SIZE) do |slice|
        counts = import_slice(slice, now)
        added += counts[:added]
        updated += counts[:updated]
        skipped += counts[:skipped]
      end

      @source.update!(last_imported_at: now)
      Stats.new(added: added, updated: updated, skipped: skipped)
    end

    private

    # Fast path: one batched existence lookup + one transaction for the whole
    # slice (eliminates the per-record find_by and per-row commit). Validations
    # already filter the known-bad records; if a write still hits an unexpected
    # DB error, the slice rolls back and we replay it record-by-record so a
    # single bad row is skipped instead of dropping the whole slice.
    def import_slice(slice, now)
      tally_slice(slice, now, isolate: false)
    rescue ActiveRecord::StatementInvalid
      tally_slice(slice, now, isolate: true)
    end

    def tally_slice(slice, now, isolate:)
      counts = { added: 0, updated: 0, skipped: 0 }
      existing_by_ref = preload_existing(slice)
      tally = ->(rec) { counts[upsert(rec, existing_by_ref, now, isolate: isolate)] += 1 }

      if isolate
        slice.each(&tally)
      else
        Camera.transaction { slice.each(&tally) }
      end
      counts
    end

    def preload_existing(records)
      refs = records.filter_map { |r| r[:external_ref].presence }.uniq
      return {} if refs.empty?

      Camera.where(data_source: @source, external_ref: refs).index_by(&:external_ref)
    end

    # Returns :added, :updated, or :skipped (malformed/invalid record).
    # `existing_by_ref` is mutated so a duplicate ref within the same batch
    # updates the row just inserted rather than colliding on the unique index.
    # In `isolate` mode each write is its own transaction so a DB-level failure
    # skips only that record (used for the record-by-record replay above).
    def upsert(rec, existing_by_ref, now, isolate:)
      ref = rec[:external_ref]
      existing = ref.present? ? existing_by_ref[ref] : nil
      camera = existing || Camera.new(data_source: @source, external_ref: ref)
      previous_location = existing&.location # before assign_attributes overwrites it
      camera.assign_attributes(
        location: point(rec[:lng], rec[:lat]),
        facing_direction: rec[:facing_direction],
        camera_type: rec[:camera_type],
        confidence: rec[:confidence] || 0.5
      )
      camera.first_seen_at ||= now
      # Mark that the source reported this camera in this import (FR-008/FR-009);
      # the stale reconciler uses this timestamp to tell seen from missing.
      camera.last_seen_in_source_at = now

      # Validate before writing so a malformed record is skipped without issuing
      # SQL that would abort the surrounding transaction.
      return :skipped unless camera.valid?

      if isolate
        begin
          Camera.transaction { camera.save! }
        rescue ActiveRecord::StatementInvalid
          return :skipped
        end
      else
        camera.save! # may raise; import_slice catches it and replays in isolation
      end

      existing_by_ref[ref] = camera if existing.nil? && ref.present?

      # A relocated camera keeps a MonitoredSegment snapped to its OLD road, so
      # avoidance would exclude the wrong segment. Drop it; the snap pass then
      # re-snaps to the new location. New cameras have no segment to drop.
      camera.monitored_segments.delete_all if existing && moved?(previous_location, camera.location)

      existing ? :updated : :added
    end

    # Below this the snap is unchanged, so re-snapping would be wasted work (and
    # would thrash on sub-meter coordinate jitter between source exports).
    MOVE_EPSILON_DEG = 1e-5 # ~1.1 m
    private_constant :MOVE_EPSILON_DEG

    def moved?(previous, current)
      return false if previous.nil? || current.nil?

      (previous.x - current.x).abs > MOVE_EPSILON_DEG ||
        (previous.y - current.y).abs > MOVE_EPSILON_DEG
    end

    def point(lng, lat)
      return nil if lng.nil? || lat.nil?

      RGeo::Geographic.spherical_factory(srid: 4326).point(lng, lat)
    rescue StandardError
      # Fall back to the cartesian factory used by the column type.
      RGeo::Cartesian.factory(srid: 4326).point(lng, lat)
    end
  end
end
