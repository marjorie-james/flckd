# Browser requests to the API must remain same-origin. In production, a
# separately hosted SPA must proxy /api through its own origin (or otherwise
# preserve the same-origin browser contract); it must not configure direct
# cross-origin API access. In dev, the Vite dev server proxies /api to this app.
#
# FRONTEND_ORIGIN is an explicit CORS exception for approved non-SPA callers,
# not a way to host the SPA's API requests cross-origin. Leave it unset for the
# normal same-origin deployment model.
if ENV["FRONTEND_ORIGIN"].present?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins ENV["FRONTEND_ORIGIN"]
      resource "/api/*",
               headers: :any,
               credentials: false, # no cookies — the API is stateless/anonymous
               methods: %i[get post options head]
    end
  end
end
