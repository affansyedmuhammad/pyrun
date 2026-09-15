# Belt and braces for the supervisor's own cleanup: removes sandboxes older than
# any legitimate run could be. Knows nothing about Docker; the runner does.
class ReapOrphanContainersJob < ApplicationJob
  MARGIN = 5.minutes

  def perform
    older_than = Pyrun.config.sandbox_timeout_seconds.seconds + Sandbox::DockerRunner::GRACE_SECONDS.seconds + MARGIN
    removed = Sandbox.runner.reap_orphans(older_than: older_than)
    Rails.logger.warn "sandbox.reaped count=#{removed}" if removed.positive?
    removed
  end
end
