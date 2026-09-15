# Who may have an account. Pure: reads config, does no I/O, and is cheap enough to
# run on every request. The source of the lists (env today) is hidden behind it.
class EmailPolicy
  FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  class << self
    def allowed?(email)
      normalized = email.to_s.strip.downcase
      return false unless normalized.match?(FORMAT)
      return true if allowed_emails.include?(normalized)

      # Exact match on the domain after the (only) @. Never a suffix check.
      allowed_domains.include?(normalized.split("@").last)
    end

    def allowed_domains = Pyrun.config.allowed_email_domains
    def allowed_emails = Pyrun.config.allowed_emails
  end
end
