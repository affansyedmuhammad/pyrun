require "test_helper"

class SessionCookieTest < ActiveSupport::TestCase
  test "the cookie takes the __Host- prefix wherever it is served over https" do
    assert_equal "__Host-session_id", Authentication.session_cookie_name(secure: true)
    assert_equal "session_id", Authentication.session_cookie_name(secure: false)
  end

  test "the web session and the cable connection agree on the cookie name" do
    assert_equal Authentication::SESSION_COOKIE, ApplicationCable::Connection::SESSION_COOKIE
  end
end
