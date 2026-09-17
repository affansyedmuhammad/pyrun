# A session ends eight hours after sign-in (Authentication). The row is also
# removed by the next request that finds it too old, but a person who simply
# closes the browser leaves one behind; this clears those so the admin's session
# counts stay honest. Solid Queue schedules it hourly (config/recurring.yml).
class ExpireSessionsJob < ApplicationJob
  def perform
    expired = Session.where(created_at: ...Authentication::SESSION_LIFETIME.ago).delete_all
    Rails.logger.info "sessions.expired count=#{expired}" if expired.positive?
    expired
  end
end
