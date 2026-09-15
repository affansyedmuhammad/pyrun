require "test_helper"

class ExpireRunOutputsJobTest < ActiveJob::TestCase
  setup do
    @old = runs(:verified_succeeded)
    @old.update!(finished_at: 10.days.ago)
  end

  test "does nothing while retention is off" do
    with_config(retention_days: 0) do
      assert_equal 0, ExpireRunOutputsJob.perform_now
    end
    assert_equal "hello\n", @old.reload.stdout
  end

  test "clears stdout and stderr of runs that finished before the retention window and marks them" do
    with_config(retention_days: 7) do
      assert_equal 1, ExpireRunOutputsJob.perform_now
    end
    @old.reload
    assert_nil @old.stdout
    assert_nil @old.stderr
    assert @old.outputs_expired_at.present?
    assert_equal "print('hello')", @old.code, "the code is kept; only output expires"
  end

  test "recent and unfinished runs are untouched, and expired runs are not expired twice" do
    recent = runs(:verified_failed)
    with_config(retention_days: 7) do
      ExpireRunOutputsJob.perform_now
      assert_equal 0, ExpireRunOutputsJob.perform_now
    end
    assert_equal "", recent.reload.stdout
    assert recent.stderr.present?
    assert runs(:verified_queued).reload.outputs_expired_at.nil?
  end
end
