require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # PostGIS spatial columns can't be represented in the Ruby schema.rb dumper,
    # so use the SQL schema format (db/structure.sql) for dump/load and tests.
    config.active_record.schema_format = :sql

    # The app ships UI/error translations only for these locales (config/locales/
    # {en,es}.yml). Restrict the available set so it is the authoritative catalog:
    # rails-i18n otherwise registers ~100 locales as "available", which would let
    # locale negotiation pick a language we don't translate (rendering raw
    # fallbacks) and would make GET /api/v1/meta/locales list every rails-i18n
    # locale. Keep this in sync with the frontend SUPPORTED_LOCALES (research D8).
    config.i18n.available_locales = %i[en es]
    config.i18n.default_locale = :en
  end
end
