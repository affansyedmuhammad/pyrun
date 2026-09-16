module Runs
  # Ends a run before its limit, at the owner's or an admin's request. A queued
  # run stops here and now; a running one is marked, and the worker, which
  # checks about once a second, kills its sandbox and records the stop.
  class Stop
    def self.call(run) = new(run).call

    def initialize(run)
      @run = run
    end

    def call
      return if @run.finished?
      @run.update!(stop_requested_at: Time.current) unless @run.stop_requested?
      Complete.stopped(@run) if @run.queued?
    end
  end
end
