require_relative "boot"

require "rails/all"
require_relative "../lib/pyrun/config"
require_relative "../lib/pyrun/request_size_limit"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Pyrun
  # The one place environment variables are read. Defined before the environment
  # files load so they, queue.yml, and initializers can all use it.
  class << self
    attr_writer :config

    def config
      @config ||= Config.from_env(ENV)
    end
  end

  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # lib/pyrun holds boot-time code (the config reader) that initializers need before
    # the reloadable autoloader exists, so it is required explicitly, not autoloaded.
    config.autoload_lib(ignore: %w[assets tasks pyrun])

    # Every form field is rendered by one builder, so labels, hints, errors, and
    # accessibility attributes are decided in one place.
    config.action_view.default_form_builder = "PyrunFormBuilder"

    # Mail has its own queue so a backlog of runs never delays a verification link.
    config.action_mailer.deliver_later_queue_name = :mailers

    # Refuse oversized request bodies before anything else looks at them.
    config.middleware.insert 0, Pyrun::RequestSizeLimit

    # Hardening headers on every response. The CSP lives in its own initializer.
    config.action_dispatch.default_headers = {
      "X-Frame-Options" => "DENY",
      "X-Content-Type-Options" => "nosniff",
      "X-XSS-Protection" => "0",
      "Referrer-Policy" => "strict-origin-when-cross-origin",
      "Cross-Origin-Opener-Policy" => "same-origin",
      "X-Permitted-Cross-Domain-Policies" => "none",
      # Rails' permissions_policy DSL still writes the legacy Feature-Policy header.
      "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), payment=(), usb=(), gyroscope=()"
    }

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
