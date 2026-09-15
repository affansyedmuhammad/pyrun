require "test_helper"
require "rake"

class PyrunAdminTasksTest < ActiveSupport::TestCase
  setup do
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
  end

  test "pyrun:deactivate disables the account and ends its sessions" do
    user = users(:verified)
    assert_operator user.sessions.count, :>, 0
    with_env("EMAIL" => user.email_address.upcase) { Rake::Task["pyrun:deactivate"].invoke }
    user.reload
    assert user.disabled?
    assert_empty user.sessions
  end

  test "pyrun:deactivate refuses an unknown address" do
    error = assert_raises(SystemExit) do
      with_env("EMAIL" => "nobody@windbornesystems.com") { capture_io { Rake::Task["pyrun:deactivate"].invoke } }
    end
    assert_not error.success?
  end

  test "pyrun:reactivate re-enables the account" do
    user = users(:disabled)
    with_env("EMAIL" => user.email_address) { Rake::Task["pyrun:reactivate"].invoke }
    assert_not user.reload.disabled?
  end

  test "pyrun:revoke_sessions signs everyone out" do
    assert_operator Session.count, :>, 0
    capture_io { Rake::Task["pyrun:revoke_sessions"].invoke }
    assert_equal 0, Session.count
  end

  test "pyrun:stats prints queue depth and status counts" do
    output = capture_io { Rake::Task["pyrun:stats"].invoke }.first
    assert_match(/queued\s+1/, output)
    assert_match(/succeeded\s+2/, output)
    assert_match(/users\s+#{User.count}/, output)
  end

  private
    def with_env(pairs)
      previous = pairs.keys.to_h { |k| [ k, ENV[k] ] }
      pairs.each { |k, v| ENV[k] = v }
      yield
    ensure
      previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
end
