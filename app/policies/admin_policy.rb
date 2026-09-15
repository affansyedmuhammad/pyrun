# Who is a superuser. Deployment config, not a column, so no request can grant it.
class AdminPolicy
  def self.admin?(email)
    normalized = email.to_s.strip.downcase
    normalized.present? && Pyrun.config.admin_emails.include?(normalized)
  end
end
