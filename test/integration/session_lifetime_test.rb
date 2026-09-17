require "test_helper"

# A sign-in lasts eight hours from the moment it started, active or not. Enforced
# on the row (checked on every request) and in the signed cookie's own expiry.
class SessionLifetimeTest < ActionDispatch::IntegrationTest
  setup { @user = users(:verified) }

  test "a session older than eight hours is over, and its row is removed" do
    sign_in_as @user
    row = Session.order(:id).last
    row.update_column(:created_at, (Authentication::SESSION_LIFETIME + 1.minute).ago)

    get runs_path
    assert_redirected_to login_path
    assert_nil Session.find_by(id: row.id)
  end

  test "activity does not extend a session: eight hours is measured from sign-in" do
    sign_in_as @user

    travel 7.hours
    get runs_path
    assert_response :success

    travel 1.hour + 1.minute # nine hours since sign-in, one since the last request
    get runs_path
    assert_redirected_to login_path
  end

  test "the cookie itself stops working after eight hours" do
    sign_in_as @user
    travel Authentication::SESSION_LIFETIME + 1.minute
    get runs_path
    assert_redirected_to login_path
  end
end
