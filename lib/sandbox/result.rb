module Sandbox
  # What a runner reports back. +status+ is one of :succeeded, :failed,
  # :timed_out, or :errored; everything else is optional.
  Result = Data.define(:status, :exit_code, :stdout, :stderr, :stdout_truncated, :stderr_truncated,
                       :duration_ms, :oom_killed, :image_digest, :metadata) do
    def initialize(status:, exit_code: nil, stdout: "", stderr: "", stdout_truncated: false, stderr_truncated: false,
                   duration_ms: nil, oom_killed: false, image_digest: nil, metadata: {})
      super
    end
  end
end
