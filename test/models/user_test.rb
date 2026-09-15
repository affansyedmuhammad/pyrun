require "test_helper"

class UserTest < ActiveSupport::TestCase
  PASSWORD = "correct horse battery staple"

  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "requires a well-formed email address" do
    assert_not build_user(email_address: "nope").valid?
    assert_not build_user(email_address: "").valid?
    assert build_user(email_address: "fine@windbornesystems.com").valid?
  end

  test "email addresses are unique regardless of case" do
    dup = build_user(email_address: "VERIFIED@windbornesystems.com")
    assert_not dup.valid?
    assert_includes dup.errors[:email_address], "has already been taken"
  end

  test "password must be at least 12 characters" do
    user = build_user(password: "short pass", password_confirmation: "short pass")
    assert_not user.valid?
    assert_includes user.errors[:password], "must be at least 12 characters"
  end

  test "password must fit in bcrypt's 72 bytes" do
    long = "x" * 73
    user = build_user(password: long, password_confirmation: long)
    assert_not user.valid?
    assert_includes user.errors[:password], "must be at most 72 bytes"
  end

  test "password confirmation must match" do
    user = build_user(password: PASSWORD, password_confirmation: PASSWORD + "!")
    assert_not user.valid?
    assert_includes user.errors[:password_confirmation], "doesn't match the password"
  end

  test "password may not be the email address" do
    email = "someone.long@windbornesystems.com"
    user = build_user(email_address: email, password: email, password_confirmation: email)
    assert_not user.valid?
    assert_includes user.errors[:password], "can't be your email address"
  end

  test "a user with no password and no identity is invalid" do
    user = User.new(email_address: "nobody@windbornesystems.com")
    assert_not user.valid?
    assert_includes user.errors[:base], "needs a password or an external login"
  end

  test "a user with an identity and no password is valid" do
    user = User.new(email_address: "sso@windbornesystems.com")
    user.identities.build(provider: "google", uid: "g-42")
    assert user.valid?
  end

  test "verified? and verify!" do
    user = users(:unverified)
    assert_not user.verified?
    user.verify!
    assert user.verified?
    assert_in_delta Time.current, user.email_verified_at, 2.seconds
  end

  test "email verification token finds the user and dies once used" do
    user = users(:unverified)
    token = user.generate_token_for(:email_verification)
    assert_equal user, User.find_by_token_for(:email_verification, token)

    user.verify!
    assert_nil User.find_by_token_for(:email_verification, token)
  end

  test "email verification token expires after 24 hours" do
    user = users(:unverified)
    token = user.generate_token_for(:email_verification)
    travel 25.hours do
      assert_nil User.find_by_token_for(:email_verification, token)
    end
  end

  test "password reset token dies once the password changes" do
    user = users(:verified)
    token = user.generate_token_for(:password_reset)
    assert_equal user, User.find_by_token_for(:password_reset, token)

    user.update!(password: PASSWORD + "2", password_confirmation: PASSWORD + "2")
    assert_nil User.find_by_token_for(:password_reset, token)
  end

  test "password reset token expires after 15 minutes" do
    token = users(:verified).generate_token_for(:password_reset)
    travel 16.minutes do
      assert_nil User.find_by_token_for(:password_reset, token)
    end
  end

  test "authenticating a user with no password fails without raising" do
    assert_nil User.authenticate_by(email_address: users(:google_only).email_address, password: PASSWORD)
  end

  test "admin? and can_view_all_runs? follow the configured admin list" do
    with_config(admin_emails: [ "admin@windbornesystems.com" ]) do
      assert users(:admin).admin?
      assert users(:admin).can_view_all_runs?
      assert_not users(:verified).admin?
      assert_not users(:verified).can_view_all_runs?
    end
    assert_not users(:admin).admin?
  end

  test "disabled?" do
    assert users(:disabled).disabled?
    assert_not users(:verified).disabled?
  end

  test "has_password?" do
    assert users(:verified).has_password?
    assert_not users(:google_only).has_password?
  end

  private
    def build_user(**attrs)
      User.new({ email_address: "new.person@windbornesystems.com", password: PASSWORD, password_confirmation: PASSWORD }.merge(attrs))
    end
end
