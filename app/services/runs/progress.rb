module Runs
  # Writes what a running program has printed so far, so the run page can show
  # output before the run ends. Complete writes the final word; nothing here
  # touches status or timing.
  class Progress
    def self.call(run, stdout:, stderr:) = new(run).record(stdout: stdout, stderr: stderr)

    def initialize(run)
      @run = run
    end

    def record(stdout:, stderr:)
      return unless @run.running?
      @run.update!(stdout: Complete.clean(stdout), stderr: Complete.clean(stderr))
    end
  end
end
