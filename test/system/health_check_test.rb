require "application_system_test_case"

class HealthCheckTest < ApplicationSystemTestCase
  test "the health check is reachable without signing in" do
    visit "/up"
    assert_includes page.html, "green"
  end
end
