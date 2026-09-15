module Sandbox
  # Runs nothing. Used by the test suite and by SANDBOX_RUNNER=fake for developing
  # without Docker. Tests script it with FakeRunner.respond_with.
  class FakeRunner < Runner
    class << self
      attr_accessor :scripted

      # For the duration of the block, every run returns +result+, or the return
      # value of +result+ when it is callable with (code, runtime:, limits:).
      def respond_with(result)
        previous, self.scripted = scripted, result
        yield
      ensure
        self.scripted = previous
      end
    end

    def run(code, runtime:, limits:)
      script = self.class.scripted
      return script.call(code, runtime: runtime, limits: limits) if script.respond_to?(:call)
      return script if script

      Result.new(status: :succeeded, exit_code: 0, duration_ms: 1, stdout: <<~OUT)
        This is the fake runner (SANDBOX_RUNNER=fake). Nothing was executed.
        It would have run #{code.bytesize} bytes of #{runtime.label} with a #{limits.timeout_seconds} second timeout:

        #{code}
      OUT
    end

    def reap_orphans(older_than:) = 0
    def healthy? = true
  end
end
