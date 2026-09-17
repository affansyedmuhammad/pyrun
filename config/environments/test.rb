# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  # Rate limiting counts in the cache, so tests need a real (per-process) store.
  config.cache_store = :memory_store

  # Jobs are captured, and performed only when a test says so.
  config.active_job.queue_adapter = :test

  # Fixtures for encrypted columns are written in the clear and encrypted on load.
  config.active_record.encryption.encrypt_fixtures = true

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # System tests open a websocket from 127.0.0.1:<random port> for Turbo refreshes.
  config.action_cable.disable_request_forgery_protection = true

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Tests never need the real credentials. Fixed, throwaway keys let any checkout
  # (a fresh clone, or a Dependabot pull request, which gets no repository
  # secrets) run the encrypted-column tests without RAILS_MASTER_KEY.
  config.active_record.encryption.primary_key = "pyrun-test-primary-key"
  config.active_record.encryption.deterministic_key = "pyrun-test-deterministic-key"
  config.active_record.encryption.key_derivation_salt = "pyrun-test-key-derivation-salt"
end
