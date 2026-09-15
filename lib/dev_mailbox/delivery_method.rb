module DevMailbox
  # Action Mailer delivery method: writes the raw message to the mailbox folder.
  # The file name sorts by time, so the inbox lists newest first without parsing.
  class DeliveryMethod
    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(mail)
      DevMailbox.location.mkpath
      id = "#{Time.now.utc.strftime('%Y%m%dT%H%M%S%3N')}-#{SecureRandom.hex(3)}"
      DevMailbox.location.join("#{id}.eml").write(mail.to_s)
    end
  end
end
