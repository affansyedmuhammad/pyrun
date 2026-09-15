# Session plumbing shared by every controller. Every login method (password today,
# Google later) ends in start_new_session_for; nothing here knows how a session began.
module Authentication
  extend ActiveSupport::Concern

  SESSION_LIFETIME = 14.days

  # __Host- forces Secure, no Domain, and Path=/, so no subdomain can plant the
  # cookie. Browsers refuse the prefix over plain http, hence the switch.
  def self.session_cookie_name(secure:)
    secure ? "__Host-session_id" : "session_id"
  end

  SESSION_COOKIE = session_cookie_name(secure: Rails.env.production?)

  included do
    before_action :require_authentication
    before_action :require_verified_email
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :require_verified_email, **options
    end

    def allow_unverified_access(**options)
      skip_before_action :require_verified_email, **options
    end
  end

  private
    def authenticated?
      resume_session.present?
    end

    def require_authentication
      resume_session || request_authentication
    end

    # Nothing past the "check your inbox" page works until the address is proven.
    def require_verified_email
      return unless Pyrun.config.require_email_verification
      return if Current.user.nil? || Current.user.verified?
      redirect_to pending_email_verification_path
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      return unless (id = cookies.signed[SESSION_COOKIE])
      session = Session.includes(:user).find_by(id: id)
      return unless session

      # Re-checked on every request, so disabling a user or tightening the
      # allowlist takes effect immediately, not at the next login.
      if session.user.disabled? || !EmailPolicy.allowed?(session.user.email_address)
        session.destroy
        cookies.delete(SESSION_COOKIE)
        return
      end

      session
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.fullpath if request.get? || request.head?
      redirect_to login_path
    end

    def after_authentication_url
      safe_return_path(session.delete(:return_to_after_authenticating)) || root_url
    end

    # Only a relative path on this app is ever used as a return target.
    def safe_return_path(target)
      target = target.to_s
      target if target.start_with?("/") && !target.start_with?("//")
    end

    def start_new_session_for(user, method: "password")
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip, login_method: method).tap do |session|
        user.update_column(:last_signed_in_at, Time.current)
        Current.session = session
        cookies.signed[SESSION_COOKIE] = { value: session.id, httponly: true, secure: Rails.env.production?, same_site: :lax, expires: SESSION_LIFETIME.from_now }
        Rails.logger.info "auth.login user=#{user.id} method=#{method} ip=#{request.remote_ip}"
      end
    end

    def terminate_session
      Current.session&.destroy
      Current.session = nil
      cookies.delete(SESSION_COOKIE)
    end
end
