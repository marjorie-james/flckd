module Api
  module V1
    class HealthController < BaseController
      # Liveness + readiness for the Kamal proxy / load-balancer healthcheck
      # (deploy.yml `proxy.healthcheck.path: /api/v1/health`).
      #
      # We gate ONLY on the database: it is the one hard dependency without which
      # no endpoint can serve. The geo services (routing/geocoder/tiles) are
      # deliberately NOT probed here — they fail soft (a routing request returns a
      # localized 503 on its own), and gating liveness on them would pull the whole
      # app out of rotation whenever a single geo accessory blips. Their health is
      # surfaced via telemetry + the RefreshRun audit instead.
      def show
        db_ok = database_ok?
        render json: {
          status: db_ok ? "ok" : "degraded",
          service: "flckd-api",
          version: "v1",
          checks: { database: db_ok ? "ok" : "error" }
        }, status: db_ok ? :ok : :service_unavailable
      end

      private

      def database_ok?
        ActiveRecord::Base.connection.execute("SELECT 1")
        true
      rescue StandardError
        false
      end
    end
  end
end
