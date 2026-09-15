# A run that is still "running" long after its own timeout has lost its worker
# (the process died mid-run). Record that so the page stops saying "Running".
# Solid Queue schedules this every minute (config/recurring.yml).
class SweepStaleRunsJob < ApplicationJob
  GRACE = Sandbox::DockerRunner::GRACE_SECONDS + 10 # seconds past the run's timeout before it counts as lost

  def perform
    swept = 0
    Run.running.where.not(started_at: nil).find_each do |run|
      next if run.started_at > (run.timeout_seconds + GRACE).seconds.ago
      Runs::Complete.errored(run, "worker lost: no result arrived within the run's timeout")
      swept += 1
    end
    Rails.logger.warn "runs.swept count=#{swept}" if swept.positive?
    swept
  end
end
