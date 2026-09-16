module Sandbox
  # Runs nothing. Used by the test suite and by SANDBOX_RUNNER=fake for developing
  # without Docker. Tests script it with FakeRunner.respond_with.
  class FakeRunner < Runner
    class << self
      attr_accessor :scripted, :scripted_progress, :last_reap_older_than

      # For the duration of the block, every run returns +result+, or the return
      # value of +result+ when it is callable with (code, runtime:, limits:) and
      # the caller's progress block. +progress+ is a list of [stdout, stderr]
      # snapshots reported before the result, as a real runner would.
      def respond_with(result, progress: [])
        previous, self.scripted = scripted, result
        previous_progress, self.scripted_progress = scripted_progress, progress
        yield
      ensure
        self.scripted = previous
        self.scripted_progress = previous_progress
      end
    end

    def run(code, runtime:, limits:, &on_progress)
      script = self.class.scripted
      return script.call(code, runtime: runtime, limits: limits, &on_progress) if script.respond_to?(:call)
      Array(self.class.scripted_progress).each { |stdout, stderr| on_progress&.call(stdout, stderr) }
      return script if script

      Result.new(status: :succeeded, exit_code: 0, duration_ms: 1, stdout: <<~OUT)
        This is the fake runner (SANDBOX_RUNNER=fake). Nothing was executed.
        It would have run #{code.bytesize} bytes of #{runtime.label} with a #{limits.timeout_seconds} second timeout:

        #{code}
      OUT
    end

    def reap_orphans(older_than:)
      self.class.last_reap_older_than = older_than
      0
    end

    def healthy? = true
  end
end
