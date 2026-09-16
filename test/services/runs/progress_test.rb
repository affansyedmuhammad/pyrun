require "test_helper"

module Runs
  class ProgressTest < ActiveSupport::TestCase
    setup do
      @run = runs(:verified_queued)
      @run.update!(status: "running", started_at: 3.seconds.ago)
    end

    test "records the output so far on a running run without finishing it" do
      Progress.call(@run, stdout: "line 1\nlin\xFF".b, stderr: "\x00warn".b)
      @run.reload
      assert_equal "line 1\nlin\uFFFD", @run.stdout
      assert_equal "warn", @run.stderr
      assert_equal "running", @run.status
      assert_nil @run.finished_at
      assert_nil @run.exit_code
    end

    test "does nothing once the run is no longer running" do
      @run.update!(status: "succeeded", finished_at: Time.current, exit_code: 0, stdout: "final\n")
      Progress.call(@run, stdout: "late\n", stderr: "")
      assert_equal "final\n", @run.reload.stdout
    end
  end
end
