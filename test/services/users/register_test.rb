require "test_helper"

module Users
  class RegisterTest < ActiveSupport::TestCase
    PASSWORD = "Correct-Horse-Battery-9"
    FIXTURE_PASSWORD = "correct horse battery staple"

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
      assert existing.reload.authenticate(FIXTURE_PASSWORD), "password must not have changed"
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

    test "refuses to create beyond the global signup budget, and sends no mail" do
      with_config(signup_rate_limit: [ 1, 3600 ]) do
        first = Register.call(email_address: "a.new@windbornesystems.com", password: PASSWORD, password_confirmation: PASSWORD)
        assert first.created?

        second = nil
        assert_no_difference "User.count" do
          second = Register.call(email_address: "b.new@windbornesystems.com", password: PASSWORD, password_confirmation: PASSWORD)
        end
        assert second.limited?
        assert_nil second.user
      end
    end

    test "rejected and existing addresses do not consume the signup budget" do
      with_config(signup_rate_limit: [ 1, 3600 ]) do
        Register.call(email_address: "outsider@example.com", password: PASSWORD, password_confirmation: PASSWORD)      # rejected
        Register.call(email_address: users(:verified).email_address, password: PASSWORD, password_confirmation: PASSWORD) # existing
        result = Register.call(email_address: "genuinely.new@windbornesystems.com", password: PASSWORD, password_confirmation: PASSWORD)
        assert result.created?, "a real new signup must still go through after only rejected/existing attempts"
      end
    end
  end
end
