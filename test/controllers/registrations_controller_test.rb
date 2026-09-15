require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  test "the signup page renders with the domain restriction and a link to sign in" do
    get signup_path
    assert_response :success
    assert_select "h1", "Create your account"
    assert_select "p", /windbornesystems\.com/
    assert_select "a[href=?]", login_path
  end

  test "signing up with an allowed address creates an unverified user, starts a session, and mails a verification link" do
    assert_difference "User.count", 1 do
      sign_up "New.Person@WindborneSystems.com"
    end
    user = User.find_by!(email_address: "new.person@windbornesystems.com")
    assert_not user.verified?
    assert_redirected_to check_inbox_path
    follow_redirect!
    assert_select "h1", "Check your inbox"
    assert_select "p", /new\.person@windbornesystems\.com/
    assert cookies[:session_id].present?
    assert_equal [ "password" ], user.sessions.pluck(:login_method)
    assert_enqueued_email_with UserMailer, :email_verification, args: [ user ]
  end

  test "signing up with the personal allowed address works" do
    with_config(allowed_emails: [ "me@example.com" ]) do
      assert_difference "User.count", 1 do
        sign_up "me@example.com"
      end
    end
    assert_redirected_to check_inbox_path
  end

  test "signing up outside the allowlist creates nothing and names the allowed domain" do
    assert_no_difference "User.count" do
      sign_up "outsider@example.com"
    end
    assert_response :unprocessable_content
    assert_select ".field-error", /limited to windbornesystems\.com/
    assert_nil cookies[:session_id].presence
    assert_enqueued_emails 0
  end

  test "lookalike domains are rejected" do
    sign_up "a@windbornesystems.com.evil.example"
    assert_response :unprocessable_content
    sign_up "a@mail.windbornesystems.com"
    assert_response :unprocessable_content
  end

  test "signing up with a registered address shows the same page, changes nothing, and mails the owner" do
    existing = users(:verified)
    assert_no_difference "User.count" do
      sign_up existing.email_address, password: "an entirely different one"
    end
    assert_redirected_to check_inbox_path
    follow_redirect!
    assert_select "h1", "Check your inbox"
    assert_select "p", /verified@windbornesystems\.com/
    assert_nil cookies[:session_id].presence
    assert_enqueued_email_with UserMailer, :existing_account, args: [ existing ]
    assert existing.reload.authenticate(PASSWORD), "the existing password must survive"
  end

  test "a short password is rejected with the reason" do
    sign_up "new@windbornesystems.com", password: "short"
    assert_response :unprocessable_content
    assert_select ".field-error", /at least 12 characters/
    assert_nil User.find_by(email_address: "new@windbornesystems.com")
  end

  test "a password that is the email address is rejected" do
    sign_up "new.person@windbornesystems.com", password: "new.person@windbornesystems.com"
    assert_response :unprocessable_content
    assert_select ".field-error", /be your email address/
  end

  test "the check-inbox page can be opened directly without revealing anything" do
    get check_inbox_path
    assert_response :success
    assert_select "h1", "Check your inbox"
  end

  test "signed-in users are sent home from the signup page" do
    sign_in_as users(:verified)
    get signup_path
    assert_redirected_to root_path
  end

  test "signup is rate limited per address" do
    11.times { |i| sign_up "outsider#{i}@example.com" }
    assert_response :too_many_requests
  end

  private
    def sign_up(email, password: PASSWORD)
      post signup_path, params: { user: { email_address: email, password: password, password_confirmation: password } }
    end
end
