require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "login_method defaults to password" do
    assert_equal "password", users(:verified).sessions.create!.login_method
  end

  test "login_method must be a known method" do
    session = users(:verified).sessions.build(login_method: "carrier pigeon")
    assert_not session.valid?
    assert_includes session.errors[:login_method], "is not included in the list"
    assert users(:verified).sessions.build(login_method: "google").valid?
  end
end
