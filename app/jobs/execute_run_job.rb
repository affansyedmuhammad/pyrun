# Executes one run in a sandbox. At most once: user code is never re-executed
# automatically, so there are no retries, and a redelivered job for a run that is
# still marked running records a lost worker instead of running it again.
class ExecuteRunJob < ApplicationJob
  queue_as :sandbox

  # One run at a time per person, so a burst queues behind its owner's own runs.
  limits_concurrency to: 1, key: ->(run) { run.user_id }

  # The run was deleted before a worker got to it.
  discard_on ActiveJob::DeserializationError

  def perform(run)
    case run.status
    when "queued" then execute(run)
    when "running" then Runs::Complete.errored(run, "worker lost: the run was picked up again while still marked running")
    end
  end

  private
    def execute(run)
      run.update!(status: "running", started_at: Time.current)
      result = Sandbox.runner.run(run.code, runtime: run.runtime_definition, limits: run.limits)
      Runs::Complete.call(run, result)
    rescue => error
      Rails.error.report(error, handled: true, context: { run_id: run.id })
      Runs::Complete.errored(run, "#{error.class}: #{error.message}")
    end
end
