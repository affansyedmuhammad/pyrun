require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Pyrun
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

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
