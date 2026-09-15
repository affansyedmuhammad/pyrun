require "test_helper"

class LogFilteringTest < ActiveSupport::TestCase
  test "submitted code, passwords, and tokens never reach the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      "run" => { "code" => "print(os.environ['AWS_SECRET'])" },
      "user" => { "password" => "correct horse", "password_confirmation" => "correct horse" },
      "token" => "abc", "email_address" => "x@windbornesystems.com"
    )
    assert_equal "[FILTERED]", filtered["run"]["code"]
    assert_equal "[FILTERED]", filtered["user"]["password"]
    assert_equal "[FILTERED]", filtered["user"]["password_confirmation"]
    assert_equal "[FILTERED]", filtered["token"]
    assert_equal "[FILTERED]", filtered["email_address"]
  end
end
