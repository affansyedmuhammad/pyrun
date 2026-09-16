# Parse and validate every setting at boot so a bad value fails the deploy, not a
# request. Pyrun.config itself is defined in config/application.rb; see docs/DESIGN.md §9.
Pyrun.config

# Refuse to boot production with an unsafe configuration (findings 5 and 10):
# sandbox capacity must be validated against a declared host size, and the email
# verification gate must be on. Skipped during image-build asset precompilation,
# which loads the production environment with a dummy secret and no runtime host
# values (Rails sets SECRET_KEY_BASE_DUMMY); the guard runs at real boot instead.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank? && (errors = Pyrun.config.production_safety_errors).any?
  raise Pyrun::Config::Error, "Unsafe production configuration:\n- #{errors.join("\n- ")}"
end
