require "test_helper"

class SessionCookieTest < ActiveSupport::TestCase
  test "the cookie takes the __Host- prefix wherever it is served over https" do
    assert_equal "__Host-session_id", Authentication.session_cookie_name(secure: true)
    assert_equal "session_id", Authentication.session_cookie_name(secure: false)
  end

  test "the web session and the cable connection agree on the cookie name" do
    assert_equal Authentication::SESSION_COOKIE, ApplicationCable::Connection::SESSION_COOKIE
  end

  test "safe_return_path allows only a relative path, never a protocol-relative or backslash target" do
    assert_equal "/runs", Authentication.safe_return_path("/runs")
    assert_equal "/runs?status=failed", Authentication.safe_return_path("/runs?status=failed")
    assert_nil Authentication.safe_return_path("//evil.com")
    assert_nil Authentication.safe_return_path("/\\evil.com")     # browsers read backslash as slash
    assert_nil Authentication.safe_return_path("https://evil.com")
    assert_nil Authentication.safe_return_path(nil)
    assert_nil Authentication.safe_return_path("")
  end
end
