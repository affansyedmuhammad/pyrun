require "test_helper"

module Sandbox
  class FakeRunnerTest < ActiveSupport::TestCase
    test "implements the runner interface" do
      runner = FakeRunner.new
      assert_kind_of Runner, runner
      assert_respond_to runner, :run
      assert_respond_to runner, :reap_orphans
      assert_respond_to runner, :healthy?
      assert runner.healthy?
      assert_equal 0, runner.reap_orphans(older_than: 5.minutes)
    end

    test "succeeds by default and says what it would have run" do
      result = FakeRunner.new.run("print('hi')", runtime: Runtime.default, limits: limits)
      assert_kind_of Result, result
      assert_equal :succeeded, result.status
      assert_equal 0, result.exit_code
      assert_includes result.stdout, "fake runner"
      assert_includes result.stdout, "print('hi')"
    end

    test "can be scripted with a fixed result for the duration of a block" do
      scripted = Result.new(status: :timed_out, stdout: "partial", duration_ms: 120_000)
      FakeRunner.respond_with(scripted) do
        assert_same scripted, FakeRunner.new.run("x", runtime: Runtime.default, limits: limits)
      end
      assert_equal :succeeded, FakeRunner.new.run("x", runtime: Runtime.default, limits: limits).status
    end

    test "can be scripted with a block that sees the code, runtime, and limits" do
      seen = nil
      FakeRunner.respond_with(->(code, runtime:, limits:) { seen = [ code, runtime.key, limits.timeout_seconds ]; Result.new(status: :failed, exit_code: 1) }) do
        result = FakeRunner.new.run("boom", runtime: Runtime.default, limits: limits)
        assert_equal :failed, result.status
      end
      assert_equal [ "boom", "python3.12", 7 ], seen
    end

    test "Sandbox.runner picks the implementation from config" do
      with_config(sandbox_runner: "fake") do
        assert_kind_of FakeRunner, Sandbox.runner
      end
    end

    private
      def limits
        Limits.new(timeout_seconds: 7, memory_mb: 64, cpus: 0.5, pids_limit: 16, max_output_bytes: 1000)
      end
  end
end
