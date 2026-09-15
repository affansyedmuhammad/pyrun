require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"
  NEW_PASSWORD = "a brand new passphrase"

  setup { @user = users(:verified) }

  test "the request page renders" do
    get new_password_path
    assert_response :success
    assert_select "h1", "Reset your password"
  end

  test "requesting a reset for a known address mails a link and shows the uniform message" do
    post passwords_path, params: { email_address: @user.email_address.upcase }
    assert_redirected_to login_path
    assert_enqueued_email_with UserMailer, :password_reset, args: [ @user ]
    follow_redirect!
    assert_select ".flash", /If that address has an account/
  end

  test "requesting a reset for an unknown address shows the same message and sends nothing" do
    post passwords_path, params: { email_address: "nobody@windbornesystems.com" }
    assert_redirected_to login_path
    assert_enqueued_emails 0
    follow_redirect!
    assert_select ".flash", /If that address has an account/
  end

  test "a disabled user gets no reset mail" do
    post passwords_path, params: { email_address: users(:disabled).email_address }
    assert_enqueued_emails 0
  end

  test "the edit page renders for a valid token" do
    get edit_password_path(@user.generate_token_for(:password_reset))
    assert_response :success
    assert_select "h1", "Choose a new password"
  end

  test "an invalid token goes back to the request page with an explanation" do
    get edit_password_path("nope")
    assert_redirected_to new_password_path
    follow_redirect!
    assert_select ".flash", /invalid or has expired/
  end

  test "an expired token is refused" do
    token = @user.generate_token_for(:password_reset)
    travel 16.minutes do
      get edit_password_path(token)
      assert_redirected_to new_password_path
    end
  end

  test "updating sets the password, ends every session, and sends the user to sign in" do
    other_session = @user.sessions.create!
    token = @user.generate_token_for(:password_reset)
    patch password_path(token), params: { user: { password: NEW_PASSWORD, password_confirmation: NEW_PASSWORD } }
    assert_redirected_to login_path
    assert @user.reload.authenticate(NEW_PASSWORD)
    assert_not Session.exists?(other_session.id)
    assert_empty @user.sessions
  end

  test "completing a reset proves the address, so an unverified user becomes verified" do
    user = users(:unverified)
    patch password_path(user.generate_token_for(:password_reset)), params: { user: { password: NEW_PASSWORD, password_confirmation: NEW_PASSWORD } }
    assert user.reload.verified?
  end

  test "a passwordless account can add a password through a reset" do
    user = users(:google_only)
    patch password_path(user.generate_token_for(:password_reset)), params: { user: { password: NEW_PASSWORD, password_confirmation: NEW_PASSWORD } }
    assert user.reload.authenticate(NEW_PASSWORD)
  end

  test "a weak password re-renders the form with the reason" do
    token = @user.generate_token_for(:password_reset)
    patch password_path(token), params: { user: { password: "short", password_confirmation: "short" } }
    assert_response :unprocessable_content
    assert_select ".field-error", /at least 12 characters/
    assert @user.reload.authenticate(PASSWORD)
  end

  test "a reset link is dead once used" do
    token = @user.generate_token_for(:password_reset)
    patch password_path(token), params: { user: { password: NEW_PASSWORD, password_confirmation: NEW_PASSWORD } }
    patch password_path(token), params: { user: { password: NEW_PASSWORD + "2", password_confirmation: NEW_PASSWORD + "2" } }
    assert_redirected_to new_password_path
    assert @user.reload.authenticate(NEW_PASSWORD)
  end

  test "reset requests are rate limited per address" do
    11.times { |i| post passwords_path, params: { email_address: "p#{i}@windbornesystems.com" } }
    assert_response :too_many_requests
  end

  test "reset requests are rate limited per email" do
    6.times do |i|
      post passwords_path, params: { email_address: "p@windbornesystems.com" }, headers: { "REMOTE_ADDR" => "10.2.0.#{i + 1}" }
    end
    assert_response :too_many_requests
  end
end
