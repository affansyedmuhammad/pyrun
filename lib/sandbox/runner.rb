module Sandbox
  # The interface every runner implements. The job, the reaper, and the tests are
  # written against this, so a gVisor, Firecracker, or remote runner is a drop-in.
  class Runner
    # Executes +code+ under +runtime+ (Sandbox::Runtime::Definition) with +limits+
    # (Sandbox::Limits) and returns a Sandbox::Result. Must never raise for
    # anything the user's code does; raising means the platform failed.
    def run(code, runtime:, limits:)
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
