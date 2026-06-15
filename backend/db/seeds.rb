# Development seed data for the Camera-Avoiding Route Planner.
# Seeds only the launch-region coverage area. Camera data is intentionally NOT
# seeded here — load it explicitly with `bin/rails camera_data:import`
# (SOURCE=pbf for the real OSM substrate, SOURCE=fixture for the demo set);
# setup.sh prompts for this after the build.

# Coverage area for the launch region (Iowa). A coarse bounding polygon is
# enough for the coverage check in dev; production uses precise boundaries.
# To add more states, add CoverageArea rows (see infra/README.md).
iowa_bbox = "SRID=4326;MULTIPOLYGON(((-96.7 40.3, -90.0 40.3, -90.0 43.6, -96.7 43.6, -96.7 40.3)))"
CoverageArea.find_or_create_by!(name: "Iowa") do |area|
  area.region = iowa_bbox
  area.data_freshness_at = Time.current
end
puts "Seeded the Iowa coverage area. (Cameras: run camera_data:import — SOURCE=pbf or fixture.)"
