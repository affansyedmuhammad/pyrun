require "test_helper"

module Runs
  class SubmitTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup { @user = users(:unverified) } # has no runs in the fixtures

    test "creates a queued run stamped with the current runtime, image, and limits, and enqueues the job" do
      result = nil
      with_config(sandbox_timeout_seconds: 7, sandbox_memory_mb: 128, sandbox_cpus: 0.5, sandbox_pids_limit: 32, sandbox_max_output_bytes: 2048, sandbox_image: "pyrun-sandbox:v9") do
        assert_difference "Run.count", 1 do
          result = Submit.call(user: @user, code: "print(1)")
        end
      end
      assert result.created?
      run = result.run
      assert run.queued?
      assert_equal "python3.12", run.runtime
      assert_equal "pyrun-sandbox:v9", run.sandbox_image
      assert_equal 7, run.timeout_seconds
      assert_equal 128, run.memory_mb
      assert_equal 0.5, run.cpus
      assert_equal 32, run.pids_limit
      assert_equal 2048, run.max_output_bytes
      assert_in_delta Time.current, run.queued_at, 2.seconds
      assert_enqueued_with(job: ExecuteRunJob, args: [ run ], queue: "sandbox")
    end

    test "blank code is invalid and nothing is enqueued" do
      result = nil
      assert_no_difference "Run.count" do
        result = Submit.call(user: @user, code: "   ")
      end
      assert result.invalid?
      assert result.run.errors[:code].any?
      assert_no_enqueued_jobs
    end

    test "oversized code is invalid" do
      with_config(max_code_bytes: 5) do
        assert Submit.call(user: @user, code: "print('too long')").invalid?
      end
    end

    test "an unknown runtime is invalid" do
      result = Submit.call(user: @user, code: "print(1)", runtime: "cobol")
      assert result.invalid?
      assert result.run.errors[:runtime].any?
    end

    test "refuses every submission while runs are paused" do
      with_config(runs_paused: true) do
        result = Submit.call(user: @user, code: "print(1)")
        assert result.rejected?
        assert_match(/paused/i, result.error)
        assert_no_enqueued_jobs
      end
    end

    test "refuses when the user already has the maximum number of active runs" do
      with_config(max_active_runs_per_user: 1) do
        result = Submit.call(user: users(:verified), code: "print(1)") # verified has one queued run
        assert result.rejected?
        assert_match(/1 run/, result.error)
      end
    end

    test "refuses when the global queue is full" do
      with_config(max_queue_depth: 1) do
        result = Submit.call(user: @user, code: "print(1)") # one queued run exists in the fixtures
        assert result.rejected?
        assert_match(/busy/i, result.error)
      end
    end
  end
end
