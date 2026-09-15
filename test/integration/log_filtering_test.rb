require "test_helper"

class LogFilteringTest < ActionDispatch::IntegrationTest
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

  test "a password reset token never appears in the request log, in path or query" do
    token = users(:verified).generate_token_for(:password_reset)
    log = capture_rails_log { get edit_password_path(token) }
    assert_response :success
    assert_no_match token, log, "the reset token leaked into the log"
    assert_match %r{Started GET "/passwords/\[FILTERED\]/edit"}, log
  end

  test "an email verification token never appears in the request log" do
    user = users(:unverified)
    token = user.generate_token_for(:email_verification)
    sign_in_as user
    log = capture_rails_log { get email_verification_path(token) }
    assert_no_match token, log
    assert_match %r{Started GET "/verify-email/\[FILTERED\]"}, log
  end

  test "non-token password routes are left readable in the log" do
    log = capture_rails_log { get new_password_path }
    assert_match %r{Started GET "/passwords/new"}, log
    assert_no_match(/\[FILTERED\]/, log)
  end

  private
    # Run a request with Rails.logger teed into a string, and return what was logged.
    def capture_rails_log
      io = StringIO.new
      previous, Rails.logger = Rails.logger, ActiveSupport::BroadcastLogger.new(ActiveSupport::Logger.new(io))
      yield
      io.string
    ensure
      Rails.logger = previous
    end
end
