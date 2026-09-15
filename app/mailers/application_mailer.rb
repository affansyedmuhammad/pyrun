class ApplicationMailer < ActionMailer::Base
  default from: -> { Pyrun.config.mail_from }
  layout "mailer"

  # Links in mail are built from configuration, never from a request's Host header.
  def default_url_options
    { host: Pyrun.config.app_host, protocol: Rails.env.production? ? "https" : "http" }
  end
end
