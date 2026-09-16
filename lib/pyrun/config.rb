module Pyrun
  # Every environment variable the app reads, parsed and validated exactly once at boot.
  # Nothing else in the app touches ENV. See docs/DESIGN.md §9 and §15.
  class Config
    Error = Class.new(StandardError)

    RUNNERS = %w[docker fake].freeze
    PERIOD_UNITS = { "s" => 1, "m" => 60, "h" => 3600 }.freeze

    # name => [env var, parser, default]
    SETTINGS = {
      allowed_emails:             [ "ALLOWED_EMAILS",             :email_list,  [] ],
      allowed_email_domains:      [ "ALLOWED_EMAIL_DOMAINS",      :domain_list, [ "windbornesystems.com" ] ],
      admin_emails:               [ "ADMIN_EMAILS",               :email_list,  [] ],
      require_email_verification: [ "REQUIRE_EMAIL_VERIFICATION", :boolean,     true ],
      app_host:                   [ "APP_HOST",                   :string,      "localhost:3000" ],
      app_name:                   [ "APP_NAME",                   :string,      "pyrun" ],
      mail_from:                  [ "MAIL_FROM",                  :string,      nil ],
      smtp_address:               [ "SMTP_ADDRESS",               :string,      nil ],
      smtp_port:                  [ "SMTP_PORT",                  :positive_int, nil ],
      smtp_username:              [ "SMTP_USERNAME",              :string,      nil ],
      smtp_password:              [ "SMTP_PASSWORD",              :string,      nil ],
      sandbox_image:              [ "SANDBOX_IMAGE",              :string,      "pyrun-sandbox:latest" ],
      sandbox_runner:             [ "SANDBOX_RUNNER",             :runner,      "docker" ],
      sandbox_runtime:            [ "SANDBOX_RUNTIME",            :string,      nil ],
      sandbox_timeout_seconds:    [ "SANDBOX_TIMEOUT_SECONDS",    :positive_int, 120 ],
      sandbox_memory_mb:          [ "SANDBOX_MEMORY_MB",          :positive_int, 256 ],
      sandbox_cpus:               [ "SANDBOX_CPUS",               :positive_decimal, 1.0 ],
      sandbox_pids_limit:         [ "SANDBOX_PIDS_LIMIT",         :positive_int, 64 ],
      sandbox_max_output_bytes:   [ "SANDBOX_MAX_OUTPUT_BYTES",   :positive_int, 1_000_000 ],
      sandbox_concurrency:        [ "SANDBOX_CONCURRENCY",        :positive_int, 2 ],
      host_memory_mb:             [ "HOST_MEMORY_MB",             :positive_int, nil ],
      host_cpus:                  [ "HOST_CPUS",                  :positive_decimal, nil ],
      max_code_bytes:             [ "MAX_CODE_BYTES",             :positive_int, 65_536 ],
      max_active_runs_per_user:   [ "MAX_ACTIVE_RUNS_PER_USER",   :positive_int, 5 ],
      max_queue_depth:            [ "MAX_QUEUE_DEPTH",            :positive_int, 200 ],
      runs_paused:                [ "RUNS_PAUSED",                :boolean,     false ],
      solid_queue_in_puma:        [ "SOLID_QUEUE_IN_PUMA",        :boolean,     false ],
      retention_days:             [ "RETENTION_DAYS",             :non_negative_int, 0 ],
      run_rate_limit:             [ "RUN_RATE_LIMIT",             :rate_limit,  [ 20, 60 ] ],
      request_rate_limit:         [ "REQUEST_RATE_LIMIT",         :rate_limit,  [ 300, 60 ] ],
      signup_rate_limit:          [ "SIGNUP_RATE_LIMIT",          :rate_limit,  [ 30, 3600 ] ]
    }.freeze

    REDACTED = %i[smtp_password].freeze

    SETTINGS.each_key { |name| attr_reader name }

    def self.from_env(env = ENV)
      values = SETTINGS.to_h do |name, (var, parser, default)|
        raw = env[var]
        value = raw.nil? || raw.strip.empty? ? default : Parsers.public_send(parser, raw.strip, var)
        [ name, value ]
      end
      new(**values)
    end

    def initialize(**values)
      unknown = values.keys - SETTINGS.keys
      raise ArgumentError, "unknown config keys: #{unknown.join(', ')}" if unknown.any?

      SETTINGS.each_key { |name| instance_variable_set(:"@#{name}", deep_freeze(values.fetch(name))) }
      @mail_from ||= "pyrun@#{@app_host.split(":").first}"
      validate!
      freeze
    end

    def with(**changes)
      self.class.new(**attributes.merge(changes))
    end

    def to_h
      attributes.merge(REDACTED.to_h { |k| [ k, attributes[k].nil? ? nil : "[REDACTED]" ] })
    end

    def run_rate_limit_count = run_rate_limit[0]
    def run_rate_limit_period = run_rate_limit[1].seconds
    def signup_rate_limit_count = signup_rate_limit[0]
    def signup_rate_limit_period = signup_rate_limit[1].seconds

    # Settings that must be present or safe in production; the boot initializer
    # refuses to start if any hold. See docs/SECURITY-REVIEW.md findings 5 and 10.
    def production_safety_errors
      errors = []
      errors << "HOST_MEMORY_MB and HOST_CPUS must be set so sandbox capacity is validated against the host" unless host_memory_mb && host_cpus
      errors << "REQUIRE_EMAIL_VERIFICATION must not be false in production" unless require_email_verification
      errors << "SOLID_QUEUE_IN_PUMA must not be enabled with the docker runner: the web process has no Docker access, so sandbox jobs belong in a separate job role (bin/jobs)" if solid_queue_in_puma && sandbox_runner == "docker"
      errors
    end
    def request_rate_limit_count = request_rate_limit[0]
    def request_rate_limit_period = request_rate_limit[1].seconds

    private

    def attributes
      SETTINGS.keys.to_h { |name| [ name, public_send(name) ] }
    end

    def validate!
      if host_memory_mb && sandbox_concurrency * sandbox_memory_mb > host_memory_mb
        raise Error, "SANDBOX_CONCURRENCY × SANDBOX_MEMORY_MB (#{sandbox_concurrency * sandbox_memory_mb} MB) exceeds HOST_MEMORY_MB (#{host_memory_mb} MB)"
      end
      if host_cpus && sandbox_concurrency * sandbox_cpus > host_cpus
        raise Error, "SANDBOX_CONCURRENCY × SANDBOX_CPUS (#{sandbox_concurrency * sandbox_cpus}) exceeds HOST_CPUS (#{host_cpus})"
      end
    end

    def deep_freeze(value)
      value.is_a?(Array) ? value.map(&:freeze).freeze : value.freeze
    end

    module Parsers
      module_function

      def string(raw, _var) = raw

      def boolean(raw, var)
        case raw.downcase
        when "true", "1", "yes" then true
        when "false", "0", "no" then false
        else raise Error, "#{var} must be true or false, got #{raw.inspect}"
        end
      end

      def positive_int(raw, var)
        int = integer(raw, var)
        raise Error, "#{var} must be greater than zero, got #{raw}" unless int.positive?
        int
      end

      def non_negative_int(raw, var)
        int = integer(raw, var)
        raise Error, "#{var} must not be negative, got #{raw}" if int.negative?
        int
      end

      def positive_decimal(raw, var)
        raise Error, "#{var} must be a number, got #{raw.inspect}" unless raw.match?(/\A\d+(\.\d+)?\z/)
        value = raw.to_f
        raise Error, "#{var} must be greater than zero, got #{raw}" unless value.positive?
        value
      end

      def runner(raw, var)
        value = raw.downcase
        raise Error, "#{var} must be one of #{RUNNERS.join(', ')}, got #{raw.inspect}" unless RUNNERS.include?(value)
        value
      end

      def email_list(raw, var)
        list(raw).each do |email|
          raise Error, "#{var} contains #{email.inspect}, which is not an email address" unless email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
        end
      end

      def domain_list(raw, var)
        list(raw).each do |domain|
          raise Error, "#{var} contains #{domain.inspect}, which is not a domain" unless domain.match?(/\A[a-z0-9.-]+\z/)
        end
      end

      def rate_limit(raw, var)
        match = raw.match(/\A(\d+)\/(\d+)([smh])\z/)
        raise Error, "#{var} must look like 20/1m (count per seconds, minutes, or hours), got #{raw.inspect}" unless match
        count, amount, unit = match[1].to_i, match[2].to_i, match[3]
        raise Error, "#{var} count and period must be greater than zero, got #{raw}" unless count.positive? && amount.positive?
        [ count, amount * PERIOD_UNITS.fetch(unit) ]
      end

      def integer(raw, var)
        raise Error, "#{var} must be an integer, got #{raw.inspect}" unless raw.match?(/\A-?\d+\z/)
        raw.to_i
      end

      def list(raw)
        raw.split(",").map { |item| item.strip.downcase }.reject(&:empty?)
      end
    end
  end
end
