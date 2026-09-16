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
      # No model callbacks: a refresh would morph the whole page and reset the
      # clock and bar. Only the output section is morphed, over the run's stream.
      @run.update_columns(stdout: Complete.clean(stdout), stderr: Complete.clean(stderr))
      @run.broadcast_replace_later_to(@run, target: "run-output", partial: "runs/output", locals: { run: @run }, attributes: { method: :morph })
    end
  end
end
