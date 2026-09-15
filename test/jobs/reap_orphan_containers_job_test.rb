require "test_helper"

class ReapOrphanContainersJobTest < ActiveJob::TestCase
  test "asks the runner to remove sandboxes older than any legitimate run could be" do
    with_config(sandbox_timeout_seconds: 120) do
      ReapOrphanContainersJob.perform_now
    end
    expected = 120.seconds + Sandbox::DockerRunner::GRACE_SECONDS.seconds + ReapOrphanContainersJob::MARGIN
    assert_equal expected, Sandbox::FakeRunner.last_reap_older_than
  end

  test "returns how many were removed" do
    assert_equal 0, ReapOrphanContainersJob.perform_now
  end
end
