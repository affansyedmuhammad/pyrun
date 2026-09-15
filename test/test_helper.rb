ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Rate-limit counters live in the cache; start every test with a clean slate.
    setup { Rails.cache.clear }

    # Sandbox integration tests need a Docker daemon and the built sandbox image.
    def docker_available?
      @@docker_available ||= system("docker", "info", out: File::NULL, err: File::NULL)
    end

    def sandbox_image_built?
      @@sandbox_image_built ||= system("docker", "image", "inspect", Pyrun.config.sandbox_image, out: File::NULL, err: File::NULL)
    end

    # Swap the app config for the duration of a block. Config is immutable, so this is
    # the only way tests change limits, allowlists, or admin membership.
    def with_config(**changes)
      previous = Pyrun.config
      Pyrun.config = previous.with(**changes)
      yield
    ensure
      Pyrun.config = previous
    end
  end
end

# No test ever talks to Docker unless it opts in; the fake runner is scriptable.
Pyrun.config = Pyrun.config.with(sandbox_runner: "fake")
