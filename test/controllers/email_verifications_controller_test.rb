require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup { @user = users(:unverified) }

  test "the pending page says where the mail went and offers to send it again" do
    sign_in_as @user
    get pending_email_verification_path
    assert_response :success
    assert_select "h1", "Check your inbox"
    assert_select "p", /unverified@windbornesystems\.com/
    assert_select "form[action=?]", email_verifications_path
  end

  test "verified users are sent home from the pending page" do
    sign_in_as users(:verified)
    get pending_email_verification_path
    assert_redirected_to root_path
  end

  test "unverified users are held at the pending page everywhere else" do
    sign_in_as @user
    get runs_path
    assert_redirected_to pending_email_verification_path
  end

  test "unverified users can still sign out" do
    sign_in_as @user
    delete logout_path
    assert_redirected_to login_path
  end

  test "the link verifies the signed-in owner and goes home" do
    sign_in_as @user
    get email_verification_path(@user.generate_token_for(:email_verification))
    assert_redirected_to root_path
    assert @user.reload.verified?
  end

  test "the link when signed out asks for a login and completes afterwards" do
    path = email_verification_path(@user.generate_token_for(:email_verification))
    get path
    assert_redirected_to login_path

    post login_path, params: { email_address: @user.email_address, password: PASSWORD }
    assert_redirected_to path
    follow_redirect!
    assert_redirected_to root_path
    assert @user.reload.verified?
  end

  test "the link opened by a different account changes nothing" do
    sign_in_as users(:verified)
    get email_verification_path(@user.generate_token_for(:email_verification))
    assert_response :success
    assert_select "h1", "This link belongs to a different account"
    assert_not @user.reload.verified?
  end

  test "an expired link explains and offers a resend" do
    token = @user.generate_token_for(:email_verification)
    sign_in_as @user
    travel 25.hours do
      get email_verification_path(token)
      assert_redirected_to pending_email_verification_path
      follow_redirect!
      assert_select ".flash", /expired/
    end
    assert_not @user.reload.verified?
  end

  test "resend mails a fresh link" do
    sign_in_as @user
    post email_verifications_path
    assert_redirected_to pending_email_verification_path
    assert_enqueued_email_with UserMailer, :email_verification, args: [ @user ]
  end

  test "resend is rate limited" do
    sign_in_as @user
    4.times { post email_verifications_path }
    assert_response :too_many_requests
  end

  test "with verification switched off, unverified users are not held" do
    sign_in_as @user
    with_config(require_email_verification: false) do
      get runs_path
      assert_response :success
    end
  end
end
