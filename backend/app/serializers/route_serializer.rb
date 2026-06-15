# Shapes a Routing::Result into the API Route contract (contracts/openapi.yaml).
class RouteSerializer < ApplicationSerializer
  def as_json(*)
    {
      geometry: @object.geometry,
      distance_m: @object.distance_m,
      duration_s: @object.duration_s,
      maneuvers: @object.maneuvers,
      cameras_avoided_count: @object.cameras_avoided_count,
      remaining_cameras: @object.remaining_cameras,
      is_fully_clean: @object.is_fully_clean,
      fastest_comparison: @object.fastest_comparison,
      coverage_warning: @object.coverage_warning
    }
  end
end
