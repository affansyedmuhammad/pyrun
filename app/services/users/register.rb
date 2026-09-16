module Users
  # The one place a User is created. Signup calls it today; an OAuth callback would
  # call it later. The allowlist check lives here so no entry point can skip it.
  class Register
    Result = Data.define(:status, :user, :error) do
      %i[created existing rejected invalid limited].each do |name|
        define_method(:"#{name}?") { status == name }
      end
    end

    GLOBAL_SIGNUP_KEY = "signups:global"

    def self.call(**) = new(**).call

    def initialize(email_address:, password:, password_confirmation:)
      @email_address = email_address.to_s.strip.downcase
      @password = password
      @password_confirmation = password_confirmation
    end

    def call
      return rejected unless EmailPolicy.allowed?(@email_address)

      existing = User.find_by(email_address: @email_address)
      return Result.new(:existing, existing, nil) if existing

      # Only genuine new-account attempts (allowed domain, not already registered)
      # consume the global budget, so a flood of rejected or existing addresses
      # can never lock out real sign-ups. See the security section of docs/IMPLEMENTATION.md.
      return limited unless within_global_signup_budget?

      create
    end

    private
      def within_global_signup_budget?
        config = Pyrun.config
        count = Rails.cache.increment(GLOBAL_SIGNUP_KEY, 1, expires_in: config.signup_rate_limit_period)
        count.nil? || count <= config.signup_rate_limit_count
      end

      def limited
        Rails.logger.warn "auth.signup_rate_limited email=#{@email_address.inspect}"
        Result.new(:limited, nil, I18n.t("registrations.rate_limited"))
      end

      def create
        user = User.new(email_address: @email_address, password: @password, password_confirmation: @password_confirmation)
        user.save ? Result.new(:created, user, nil) : Result.new(:invalid, user, nil)
      rescue ActiveRecord::RecordNotUnique
        Result.new(:existing, User.find_by!(email_address: @email_address), nil)
      end

      def rejected
        Result.new(:rejected, nil, I18n.t("registrations.domain_restricted", domains: EmailPolicy.allowed_domains.to_sentence))
      end
  end
end
