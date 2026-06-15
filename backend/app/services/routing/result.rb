module Routing
  # The outcome of planning a route: geometry + metrics + camera-avoidance
  # details. Returned by RoutePlanner#plan and serialized by RouteSerializer.
  Result = Struct.new(
    :geometry, :distance_m, :duration_s, :maneuvers,
    :cameras_avoided_count, :remaining_cameras, :is_fully_clean,
    :fastest_comparison, :coverage_warning,
    keyword_init: true
  )
end
