Rails.application.routes.draw do
  # Health check (used by load balancers and the deterministic test harness).
  get "up" => "rails/health#show", as: :rails_health_check
  get "api/v1/health" => "api/v1/health#show"

  namespace :api do
    namespace :v1 do
      # Core US1 flow: plan a camera-avoiding route. POST keeps coordinates
      # out of URLs/logs (anonymity, FR-011).
      resources :routes, only: [ :create ]

      # Geocoding for origin/destination entry & disambiguation (FR-001/016).
      get  "geocode/search",  to: "geocoding#search"
      post "geocode/reverse", to: "geocoding#reverse"

      # Camera-data coverage for a point (FR-018).
      get "coverage", to: "coverage#show"
      # Bounding box of the covered region(s), so the client can frame the map on
      # the coverage area generically (no hardcoded launch state).
      get "coverage/bounds", to: "coverage#bounds"

      # Known cameras within a viewport (US4 display).
      resources :cameras, only: [ :index ]

      # Supported interface languages (drives the language switcher, FR-013).
      get "meta/locales", to: "locales#index"
    end
  end
end
