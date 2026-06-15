# CORS for the SPA. Anonymity model: the API and SPA are same-origin in
# production, so cross-origin requests are NOT permitted by default. In dev the
# Vite dev server proxies /api to this app (same-origin from the browser's
# view), so no CORS allowance is needed there either.
#
# Set FRONTEND_ORIGIN only if you intentionally serve the SPA from a different
# origin; leaving it unset keeps the API closed to cross-origin callers.
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
