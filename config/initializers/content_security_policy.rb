# Strict by default: only this origin, no inline script or style except with the
# per-request nonce (importmap and Turbo's progress bar use it), no framing, no
# plugins, forms only post here. Nothing external is loaded on purpose.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.font_src        :self, :data
    policy.img_src         :self, :data
    policy.object_src      :none
    policy.script_src      :self
    policy.style_src       :self
    policy.connect_src     :self
    policy.frame_ancestors :none
    policy.form_action     :self
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
