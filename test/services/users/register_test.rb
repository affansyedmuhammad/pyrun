require "test_helper"

module Users
  class RegisterTest < ActiveSupport::TestCase
    PASSWORD = "correct horse battery staple"

    test "creates an unverified user when the address is allowed" do
      result = nil
      assert_difference "User.count", 1 do
        result = Register.call(email_address: "New.Person@WindborneSystems.com", password: PASSWORD, password_confirmation: PASSWORD)
      end
      assert result.created?
      assert_equal "new.person@windbornesystems.com", result.user.email_address
      assert result.user.persisted?
      assert_not result.user.verified?
      assert result.user.authenticate(PASSWORD)
    end

    test "rejects an address outside the allowlist without creating anything" do
      result = nil
      assert_no_difference "User.count" do
        result = Register.call(email_address: "outsider@example.com", password: PASSWORD, password_confirmation: PASSWORD)
      end
      assert result.rejected?
      assert_nil result.user
      assert_match(/windbornesystems\.com/, result.error)
    end

    test "reports an existing account and changes nothing" do
      existing = users(:verified)
      result = nil
      assert_no_difference "User.count" do
        result = Register.call(email_address: existing.email_address.upcase, password: PASSWORD + "x", password_confirmation: PASSWORD + "x")
      end
      assert result.existing?
      assert_equal existing, result.user
      assert existing.reload.authenticate(PASSWORD), "password must not have changed"
    end

    test "returns validation errors for a bad password and creates nothing" do
      result = nil
      assert_no_difference "User.count" do
        result = Register.call(email_address: "new.person@windbornesystems.com", password: "short", password_confirmation: "short")
      end
      assert result.invalid?
      assert result.user.errors[:password].any?
      assert_not result.user.persisted?
    end

    test "the allowlist is checked before anything else" do
      result = Register.call(email_address: "outsider@example.com", password: "short", password_confirmation: "nope")
      assert result.rejected?
    end
  end
end
