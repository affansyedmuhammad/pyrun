require "test_helper"

class ExecuteRunJobTest < ActiveJob::TestCase
  setup { @run = runs(:verified_queued) }

  test "runs per person are limited by MAX_CONCURRENT_RUNS_PER_USER" do
    assert_equal 1, ExecuteRunJob.concurrency_limit
    with_config(max_concurrent_runs_per_user: 2, sandbox_concurrency: 2) { load Rails.root.join("app/jobs/execute_run_job.rb") }
    assert_equal 2, ExecuteRunJob.concurrency_limit
  ensure
    load Rails.root.join("app/jobs/execute_run_job.rb")
    assert_equal 1, ExecuteRunJob.concurrency_limit
  end

  test "is queued on the sandbox queue" do
    assert_equal "sandbox", ExecuteRunJob.new.queue_name
  end

  test "runs a queued run through the runner and records the result" do
    Sandbox::FakeRunner.respond_with(Sandbox::Result.new(status: :succeeded, exit_code: 0, stdout: "done\n", duration_ms: 42)) do
      ExecuteRunJob.perform_now(@run)
    end
    @run.reload
    assert @run.succeeded?
    assert_equal "done\n", @run.stdout
    assert_equal 42, @run.duration_ms
    assert @run.started_at.present?
    assert @run.finished_at.present?
  end

  test "hands the runner the run's own recorded limits and runtime, not the current config" do
    seen = nil
    with_config(sandbox_timeout_seconds: 999) do
      Sandbox::FakeRunner.respond_with(->(_code, runtime:, limits:) { seen = [ runtime.key, limits.timeout_seconds ]; Sandbox::Result.new(status: :succeeded, exit_code: 0) }) do
        ExecuteRunJob.perform_now(@run)
      end
    end
    assert_equal [ "python3.12", 120 ], seen
  end

  test "does nothing for a run that is already finished" do
    finished = runs(:verified_succeeded)
    Sandbox::FakeRunner.respond_with(->(*) { flunk "the runner must not be called" }) do
      ExecuteRunJob.perform_now(finished)
    end
    assert_equal "hello\n", finished.reload.stdout
  end

  test "a redelivered job for a run that is still marked running records a lost worker" do
    @run.update!(status: "running", started_at: 1.minute.ago)
    Sandbox::FakeRunner.respond_with(->(*) { flunk "user code must never be executed twice" }) do
      ExecuteRunJob.perform_now(@run)
    end
    @run.reload
    assert @run.errored?
    assert_match(/worker/i, @run.error_message)
  end

  test "a runner exception marks the run errored and does not raise" do
    Sandbox::FakeRunner.respond_with(->(*) { raise IOError, "docker daemon unreachable" }) do
      assert_nothing_raised { ExecuteRunJob.perform_now(@run) }
    end
    @run.reload
    assert @run.errored?
    assert_match(/docker daemon unreachable/, @run.error_message)
  end
end
