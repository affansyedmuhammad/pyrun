require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "Correct-Horse-Battery-9"
  FIXTURE_PASSWORD = "correct horse battery staple"

  test "the signup page renders with the domain restriction and a link to sign in" do
    get signup_path
    assert_response :success
    assert_select "h1", "Create your account"
    assert_select "p.auth-lede", count: 0
    assert_select "a[href=?]", login_path
  end

  test "the signup page lists every password rule for the live checklist" do
    get signup_path
    assert_select "[data-controller=password-rules] ul.rules" do
      assert_select "li[data-password-rules-target=rule]", User::PASSWORD_RULES.size + 1
      assert_select "li[data-min-length=?]", User::PASSWORD_MIN_LENGTH.to_s, text: /12 characters/
      assert_select "li[data-pattern]", User::PASSWORD_RULES.size
    end
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
    assert_select "form[action=?] button", email_verifications_path, text: "Send a new link"
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
    assert existing.reload.authenticate(FIXTURE_PASSWORD), "the existing password must survive"
  end

  test "a short password is rejected with the reason" do
    sign_up "new@windbornesystems.com", password: "short"
    assert_response :unprocessable_content
    assert_select ".field-error", /at least 12 characters/
    assert_nil User.find_by(email_address: "new@windbornesystems.com")
  end

  test "a password missing a rule is rejected with that rule named" do
    sign_up "new@windbornesystems.com", password: "correct horse battery staple"
    assert_response :unprocessable_content
    assert_select ".field-error", /uppercase letter/
  end

  test "when the form comes back with errors the typed password is kept" do
    sign_up "new@windbornesystems.com", password: "short"
    assert_select "input[name='user[password]'][value=?]", "short"
    assert_select "input[name='user[password_confirmation]'][value=?]", "short"

    sign_up "outsider@example.com", password: "Correct-Horse-Battery-9"
    assert_select "input[name='user[password]'][value=?]", "Correct-Horse-Battery-9"
  end

  test "password fields have a show/hide toggle" do
    get signup_path
    assert_select "[data-controller=password-visibility]", count: 2 do
      assert_select "input[type=password][data-password-visibility-target=input]"
      assert_select "button[type=button][aria-label='Show password'][aria-pressed=false] svg[aria-hidden=true]"
    end
  end

  test "a password that is the email address is rejected" do
    sign_up "new.person@windbornesystems.com", password: "new.person@windbornesystems.com"
    assert_response :unprocessable_content
    assert_select ".field-error", /be your email address/
  end

  test "the check-inbox page can be opened directly and offers to send the link again" do
    get check_inbox_path
    assert_response :success
    assert_select "h1", "Check your inbox"
    assert_select "form[action=?] button", email_verifications_path, text: "Send a new link"
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

  test "signup is globally rate limited across addresses and IPs" do
    with_config(signup_rate_limit: [ 1, 3600 ]) do
      sign_up "first.new@windbornesystems.com" # consumes the only slot
      assert_redirected_to check_inbox_path
      assert_no_enqueued_emails do
        assert_no_difference "User.count" do
          sign_up "second.new@windbornesystems.com"
        end
      end
      assert_response :too_many_requests
      assert_select ".flash-alert", /Too many sign-ups/
    end
  end

  private
    def sign_up(email, password: PASSWORD)
      post signup_path, params: { user: { email_address: email, password: password, password_confirmation: password } }
    end
end
