module Users
  # The one place a User is created. Signup calls it today; an OAuth callback would
  # call it later. The allowlist check lives here so no entry point can skip it.
  class Register
    Result = Data.define(:status, :user, :error) do
      %i[created existing rejected invalid].each do |name|
        define_method(:"#{name}?") { status == name }
      end
    end

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

      create
    end

    private
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
