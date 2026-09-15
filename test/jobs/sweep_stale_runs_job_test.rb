require "test_helper"

class SweepStaleRunsJobTest < ActiveJob::TestCase
  setup { @run = runs(:verified_queued) }

  test "a run marked running for longer than its own timeout plus grace is recorded as a lost worker" do
    @run.update!(status: "running", started_at: (@run.timeout_seconds + SweepStaleRunsJob::GRACE + 1).seconds.ago)
    assert_equal 1, SweepStaleRunsJob.perform_now
    @run.reload
    assert @run.errored?
    assert_match(/worker lost/i, @run.error_message)
    assert @run.finished_at.present?
  end

  test "a run still within its timeout is left alone" do
    @run.update!(status: "running", started_at: 10.seconds.ago)
    assert_equal 0, SweepStaleRunsJob.perform_now
    assert @run.reload.running?
  end

  test "the threshold is the run's own recorded timeout, not the current config" do
    @run.update!(status: "running", started_at: 30.seconds.ago, timeout_seconds: 5)
    with_config(sandbox_timeout_seconds: 3600) do
      assert_equal 1, SweepStaleRunsJob.perform_now
    end
    assert @run.reload.errored?
  end

  test "queued and finished runs are never touched" do
    old = runs(:verified_succeeded)
    SweepStaleRunsJob.perform_now
    assert @run.reload.queued?
    assert old.reload.succeeded?
  end
end
