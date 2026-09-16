require "test_helper"

module Runs
  class StopTest < ActiveSupport::TestCase
    setup { @run = runs(:verified_queued) }

    test "a queued run stops at once, before any worker picks it up" do
      Stop.call(@run)
      @run.reload
      assert_equal "stopped", @run.status
      assert_not_nil @run.stop_requested_at
      assert_not_nil @run.finished_at
      assert_nil @run.duration_ms
      assert @run.finished?
    end

    test "a running run is asked to stop and stays running until the worker kills it" do
      @run.update!(status: "running", started_at: 2.seconds.ago)
      Stop.call(@run)
      @run.reload
      assert_equal "running", @run.status
      assert_not_nil @run.stop_requested_at
      assert_nil @run.finished_at
    end

    test "asking twice keeps the first request time" do
      @run.update!(status: "running", started_at: 2.seconds.ago, stop_requested_at: 5.seconds.ago)
      first = @run.stop_requested_at
      Stop.call(@run)
      assert_equal first, @run.reload.stop_requested_at
    end

    test "a finished run is left alone" do
      run = runs(:verified_succeeded)
      Stop.call(run)
      run.reload
      assert_equal "succeeded", run.status
      assert_nil run.stop_requested_at
    end
  end
end
