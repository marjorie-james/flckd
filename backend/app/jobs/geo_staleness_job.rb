# Periodic check that the self-hosted geo substrate (routing graph / tiles /
# geocoder index, all built from an OSM extract) hasn't gone stale. Scheduled
# weekly via config/recurring.yml; alerts through Telemetry. Reference data only.
class GeoStalenessJob < ApplicationJob
  queue_as :default

  def perform
    Geo::SubstrateFreshness.new.check
  end
end
