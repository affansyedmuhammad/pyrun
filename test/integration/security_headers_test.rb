require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "every page carries a strict content security policy with a per-request nonce" do
    get login_path
    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "no CSP header"
    assert_includes csp, "default-src 'self'"
    assert_includes csp, "frame-ancestors 'none'"
    assert_includes csp, "object-src 'none'"
    assert_includes csp, "base-uri 'self'"
    assert_includes csp, "form-action 'self'"
    assert_match(/script-src [^;]*'nonce-[A-Za-z0-9+\/=]+'/, csp)
    assert_no_match(/'unsafe-inline'/, csp.split("script-src").last.split(";").first)

    nonce = csp[/script-src [^;]*'nonce-([^']+)'/, 1]
    assert_select "meta[name=csp-nonce][content=?]", nonce
    assert_select "script[type=importmap][nonce=?]", nonce
  end

  test "the nonce stays the same across a session, so Turbo visits keep working" do
    sign_in_as users(:verified)
    get runs_path
    first = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]
    get new_run_path
    second = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]
    assert first.present?
    assert_equal first, second
  end

  test "the usual hardening headers are set" do
    get login_path
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "DENY", response.headers["X-Frame-Options"]
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]
    assert_equal "same-origin", response.headers["Cross-Origin-Opener-Policy"]
    assert_includes response.headers["Permissions-Policy"].to_s, "camera=()"
  end

  test "search engines are told to stay away" do
    get "/robots.txt"
    assert_response :success
    assert_includes response.body, "Disallow: /"
    get login_path
    assert_select "meta[name=robots][content=?]", "noindex, nofollow"
  end

  test "development-only pages are not mounted outside development" do
    sign_in_as users(:verified)
    [ "/rails/info/routes", "/rails/info/properties", "/rails/mailers" ].each do |path|
      get path
      assert_response :not_found, "#{path} should not exist in this environment"
    end
  end
end
