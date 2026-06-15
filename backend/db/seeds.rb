# Development seed data for the Camera-Avoiding Route Planner.
# Seeds only the configured country's camera DATA-REGION. Camera data itself is
# intentionally NOT seeded here — load it explicitly with `bin/rails
# camera_data:import` (SOURCE=pbf for the real OSM substrate, SOURCE=fixture for
# the demo set); setup.sh / build-geo.sh import it after the build.
#
# The data-region is the configured country's extent (Geocoding::CountryRegistry,
# default US) — a coarse bounding polygon, enough for the dev coverage check.
# The MAP-FRAMING extent is derived from the same registry at request time
# (CoverageController#bounds), so it is not seeded here. To model honest
# present/absent coverage in dev, replace this with narrower data-regions.

country = Geocoding::CountryRegistry.resolve
west, south, east, north = country.bbox
# A closed bbox ring (lng/lat), counter-clockwise — coarse but sufficient for the
# dev containment check.
region = "SRID=4326;MULTIPOLYGON(((" \
  "#{west} #{south}, #{east} #{south}, #{east} #{north}, #{west} #{north}, #{west} #{south}" \
  ")))"

CoverageArea.find_or_create_by!(name: country.name) do |area|
  area.region = region
  area.data_freshness_at = Time.current
end

puts "Seeded the #{country.name} camera data-region (#{country.code}). " \
     "(Cameras: run camera_data:import — SOURCE=pbf or fixture.)"
