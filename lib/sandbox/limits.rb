module Sandbox
  # The resource limits a run executes under. Stamped on the run at submission and
  # read back at execution, so a config change never alters a run in flight.
  Limits = Data.define(:timeout_seconds, :memory_mb, :cpus, :pids_limit, :max_output_bytes)
end
