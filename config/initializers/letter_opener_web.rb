# Development only. letter_opener_web's inbox shows each mail in a same-origin
# iframe and uses inline script and style, which the app's strict CSP and
# X-Frame-Options: DENY forbid. Relax both for the engine's controllers alone;
# every other response keeps the strict policy from content_security_policy.rb.
if Rails.env.development?
  Rails.application.config.to_prepare do
    LetterOpenerWeb::ApplicationController.class_eval do
      content_security_policy do |policy|
        policy.script_src      :self, :unsafe_inline
        policy.style_src       :self, :unsafe_inline
        policy.frame_ancestors :self
      end

      after_action { response.headers["X-Frame-Options"] = "SAMEORIGIN" }
    end
  end
end
