require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  test "the login page renders with links to sign up and to reset a password" do
    get login_path
    assert_response :success
    assert_select "h1", "Sign in"
    assert_select "a[href=?]", signup_path
    assert_select "a[href=?]", new_password_path
  end

  test "signing in starts a password session and goes home" do
    user = users(:verified)
    assert_difference "user.sessions.count", 1 do
      post login_path, params: { email_address: user.email_address, password: PASSWORD }
    end
    assert_redirected_to root_path
    assert cookies[:session_id].present?
    assert_equal "password", user.sessions.order(:id).last.login_method
  end

  test "signing in returns to the page that asked for it, query string included" do
    get runs_path(status: "failed")
    assert_redirected_to login_path
    post login_path, params: { email_address: users(:verified).email_address, password: PASSWORD }
    assert_redirected_to "/runs?status=failed"
  end

  test "wrong password and unknown address get the same answer" do
    post login_path, params: { email_address: users(:verified).email_address, password: "wrong wrong wrong" }
    assert_response :unprocessable_content
    assert_select ".flash", "Try another email address or password."

    post login_path, params: { email_address: "nobody@windbornesystems.com", password: "wrong wrong wrong" }
    assert_response :unprocessable_content
    assert_select ".flash", "Try another email address or password."
    assert_nil cookies[:session_id].presence
  end

  test "the typed email survives a failed attempt" do
    post login_path, params: { email_address: "typed@windbornesystems.com", password: "wrong wrong wrong" }
    assert_select "input[name=email_address][value=?]", "typed@windbornesystems.com"
  end

  test "a disabled user cannot sign in" do
    post login_path, params: { email_address: users(:disabled).email_address, password: PASSWORD }
    assert_response :unprocessable_content
    assert_nil cookies[:session_id].presence
  end

  test "an unverified user signs in and is held at the pending page" do
    post login_path, params: { email_address: users(:unverified).email_address, password: PASSWORD }
    assert_redirected_to root_path
    follow_redirect!
    assert_redirected_to pending_email_verification_path
  end

  test "signing out deletes the session row and the old cookie no longer works" do
    sign_in_as users(:verified)
    session_id = Current.session.id
    old_cookie = cookies[:session_id]

    delete logout_path
    assert_redirected_to login_path
    assert_not Session.exists?(session_id)

    cookies[:session_id] = old_cookie
    get runs_path
    assert_redirected_to login_path
  end

  test "signed-in users are sent home from the login page" do
    sign_in_as users(:verified)
    get login_path
    assert_redirected_to root_path
  end

  test "sign-in is rate limited per address" do
    11.times { post login_path, params: { email_address: "x@windbornesystems.com", password: "nope nope nope" } }
    assert_response :too_many_requests
  end

  test "sign-in is rate limited per email across many addresses" do
    31.times do |i|
      post login_path, params: { email_address: "target@windbornesystems.com", password: "nope nope nope" },
                       headers: { "REMOTE_ADDR" => "10.1.#{i / 200}.#{i % 200 + 1}" }
    end
    assert_response :too_many_requests
  end

  test "a session stops working the moment its address leaves the allowlist" do
    sign_in_as users(:verified)
    session_id = Current.session.id
    with_config(allowed_email_domains: [ "elsewhere.example" ]) do
      get runs_path
      assert_redirected_to login_path
    end
    assert_not Session.exists?(session_id)
  end

  test "a session stops working once the user is disabled" do
    user = users(:verified)
    sign_in_as user
    user.update!(disabled_at: Time.current)
    get runs_path
    assert_redirected_to login_path
  end
end
