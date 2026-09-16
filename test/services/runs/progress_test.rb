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

    test "morphs only the output section on the run's page, never a full refresh" do
      replaced, refreshed = [], []
      @run.define_singleton_method(:broadcast_replace_later_to) { |*streamables, **opts| replaced << [ streamables, opts ] }
      @run.define_singleton_method(:broadcast_refresh_later_to) { |*streamables, **| refreshed << streamables }
      @run.define_singleton_method(:broadcast_refresh_later) { refreshed << [ @run ] }

      Progress.call(@run, stdout: "so far\n", stderr: "")

      assert_empty refreshed, "a refresh would morph the whole page and reset the clock and bar"
      assert_equal 1, replaced.size
      streamables, opts = replaced.first
      assert_equal [ @run ], streamables
      assert_equal "run-output", opts[:target]
      assert_equal({ method: :morph }, opts[:attributes])
      assert_equal "runs/output", opts[:partial]
    end

    test "does nothing once the run is no longer running" do
      @run.update!(status: "succeeded", finished_at: Time.current, exit_code: 0, stdout: "final\n")
      Progress.call(@run, stdout: "late\n", stderr: "")
      assert_equal "final\n", @run.reload.stdout
    end
  end
end
