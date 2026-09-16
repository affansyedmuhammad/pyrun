module Sandbox
  # The interface every runner implements. The job, the reaper, and the tests are
  # written against this, so a gVisor, Firecracker, or remote runner is a drop-in.
  class Runner
    # Executes +code+ under +runtime+ (Sandbox::Runtime::Definition) with +limits+
    # (Sandbox::Limits) and returns a Sandbox::Result. If a block is given it is
    # called with (stdout_so_far, stderr_so_far) about once a second while the
    # program runs, so callers can show output before the run ends. +stop_when+,
    # if given, is called on the same cadence; once it returns true the program
    # is killed and the result's status is :stopped. Must never raise for
    # anything the user's code does; raising means the platform failed.
    def run(code, runtime:, limits:, stop_when: nil, &on_progress)
      raise NotImplementedError
    end

    # Removes sandboxes older than +older_than+ that no supervisor owns any more.
    # Returns how many were removed.
    def reap_orphans(older_than:)
      raise NotImplementedError
    end

    def healthy?
      raise NotImplementedError
    end
  end
end
