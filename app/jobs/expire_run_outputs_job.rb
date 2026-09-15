# Retention. When RETENTION_DAYS is set, output of runs that finished before the
# window is deleted; the code and the run's record stay. Off by default.
class ExpireRunOutputsJob < ApplicationJob
  def perform
    days = Pyrun.config.retention_days
    return 0 if days.zero?

    expired = 0
    Run.where(status: Run::TERMINAL_STATUSES, outputs_expired_at: nil).where(finished_at: ..days.days.ago).find_each do |run|
      run.update!(stdout: nil, stderr: nil, outputs_expired_at: Time.current)
      expired += 1
    end
    Rails.logger.info "runs.outputs_expired count=#{expired}" if expired.positive?
    expired
  end
end
