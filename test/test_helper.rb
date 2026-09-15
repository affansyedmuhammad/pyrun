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
