require "test_helper"

module Runs
  class CompleteTest < ActiveSupport::TestCase
    setup do
      @run = runs(:verified_queued)
      @run.update!(status: "running", started_at: 3.seconds.ago)
    end

    test "records a successful result" do
      Complete.call(@run, Sandbox::Result.new(status: :succeeded, exit_code: 0, stdout: "hi\n", stderr: "", duration_ms: 812, image_digest: "sha256:abc"))
      @run.reload
      assert @run.succeeded?
      assert_equal "hi\n", @run.stdout
      assert_equal 0, @run.exit_code
      assert_equal 812, @run.duration_ms
      assert_in_delta Time.current, @run.finished_at, 2.seconds
      assert_equal "sha256:abc", @run.runner_metadata["image_digest"]
    end

    test "records a failure with exit code, oom flag, and truncation" do
      Complete.call(@run, Sandbox::Result.new(status: :failed, exit_code: 137, stdout: "x" * 10, stdout_truncated: true, oom_killed: true, duration_ms: 50))
      @run.reload
      assert @run.failed?
      assert_equal 137, @run.exit_code
      assert @run.oom_killed?
      assert @run.stdout_truncated?
      assert_not @run.stderr_truncated?
    end

    test "records a timeout" do
      Complete.call(@run, Sandbox::Result.new(status: :timed_out, stdout: "partial", duration_ms: 120_000))
      assert @run.reload.timed_out?
      assert_equal "partial", @run.stdout
    end

    test "records a platform error with a message and no output" do
      Complete.errored(@run, "worker lost")
      @run.reload
      assert @run.errored?
      assert_equal "worker lost", @run.error_message
      assert_in_delta Time.current, @run.finished_at, 2.seconds
    end

    test "falls back to the timestamps for duration when the runner gives none" do
      Complete.call(@run, Sandbox::Result.new(status: :succeeded, exit_code: 0))
      assert_in_delta 3000, @run.reload.duration_ms, 1500
    end

    test "scrubs invalid UTF-8 and NUL bytes before storing output" do
      Complete.call(@run, Sandbox::Result.new(status: :succeeded, exit_code: 0, stdout: "ok\xFF\x00!".b, stderr: "\x00".b))
      @run.reload
      assert_equal "ok�!", @run.stdout
      assert_equal "", @run.stderr
      assert @run.stdout.valid_encoding?
    end
  end
end
