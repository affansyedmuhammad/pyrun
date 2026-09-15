require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  test "requires a provider and a uid" do
    identity = users(:verified).identities.build
    assert_not identity.valid?
    assert_includes identity.errors[:provider], "can't be blank"
    assert_includes identity.errors[:uid], "can't be blank"
  end

  test "uid is unique per provider" do
    dup = users(:verified).identities.build(provider: "google", uid: "google-uid-1")
    assert_not dup.valid?
    assert_includes dup.errors[:uid], "has already been taken"

    other_provider = users(:verified).identities.build(provider: "okta", uid: "google-uid-1")
    assert other_provider.valid?
  end

  test "the last identity of a passwordless user cannot be removed" do
    identity = identities(:google_only_google)
    assert_not identity.destroy
    assert_includes identity.errors[:base], "is the only way this account can sign in"
    assert Identity.exists?(identity.id)
  end

  test "an identity can be removed when the user has a password" do
    identity = users(:verified).identities.create!(provider: "google", uid: "g-9")
    assert identity.destroy
    assert_not Identity.exists?(identity.id)
  end
end
