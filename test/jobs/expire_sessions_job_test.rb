require "test_helper"

class ExpireSessionsJobTest < ActiveJob::TestCase
  test "sessions older than the lifetime are deleted; younger ones stay" do
    user = users(:verified)
    old = user.sessions.create!(login_method: "password")
    old.update_column(:created_at, (Authentication::SESSION_LIFETIME + 1.minute).ago)
    young = user.sessions.create!(login_method: "password")
    young.update_column(:created_at, 1.hour.ago)

    assert_equal 1, ExpireSessionsJob.perform_now
    assert_nil Session.find_by(id: old.id)
    assert Session.exists?(young.id)
  end
end
