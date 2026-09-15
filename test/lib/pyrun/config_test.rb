require "test_helper"

module Pyrun
  class ConfigTest < ActiveSupport::TestCase
    test "defaults when nothing is set" do
      c = Config.from_env({})
      assert_equal [], c.allowed_emails
      assert_equal [ "windbornesystems.com" ], c.allowed_email_domains
      assert_equal [], c.admin_emails
      assert_equal true, c.require_email_verification
      assert_equal "localhost:3000", c.app_host
      assert_equal "pyrun", c.app_name
      assert_equal "pyrun-sandbox:latest", c.sandbox_image
      assert_equal "docker", c.sandbox_runner
      assert_nil c.sandbox_runtime
      assert_equal 120, c.sandbox_timeout_seconds
      assert_equal 256, c.sandbox_memory_mb
      assert_equal 1.0, c.sandbox_cpus
      assert_equal 64, c.sandbox_pids_limit
      assert_equal 1_000_000, c.sandbox_max_output_bytes
      assert_equal 2, c.sandbox_concurrency
      assert_equal 65_536, c.max_code_bytes
      assert_equal 5, c.max_active_runs_per_user
      assert_equal 200, c.max_queue_depth
      assert_equal false, c.runs_paused
      assert_equal 0, c.retention_days
      assert_equal 20, c.run_rate_limit_count
      assert_equal 1.minute, c.run_rate_limit_period
    end

    test "lists are split on commas, trimmed, lowercased, and blanks dropped" do
      c = Config.from_env(
        "ALLOWED_EMAILS" => " Me@Example.com ,, other@x.io ",
        "ALLOWED_EMAIL_DOMAINS" => "WindborneSystems.com, example.org",
        "ADMIN_EMAILS" => "Boss@WindborneSystems.com"
      )
      assert_equal [ "me@example.com", "other@x.io" ], c.allowed_emails
      assert_equal [ "windbornesystems.com", "example.org" ], c.allowed_email_domains
      assert_equal [ "boss@windbornesystems.com" ], c.admin_emails
    end

    test "booleans accept true, false, 1, 0, yes, no in any case" do
      assert_equal false, Config.from_env("REQUIRE_EMAIL_VERIFICATION" => "false").require_email_verification
      assert_equal false, Config.from_env("REQUIRE_EMAIL_VERIFICATION" => "0").require_email_verification
      assert_equal true, Config.from_env("RUNS_PAUSED" => "YES").runs_paused
      assert_equal true, Config.from_env("RUNS_PAUSED" => "1").runs_paused
      error = assert_raises(Config::Error) { Config.from_env("RUNS_PAUSED" => "maybe") }
      assert_match(/RUNS_PAUSED/, error.message)
    end

    test "integers must be integers and the error names the variable" do
      error = assert_raises(Config::Error) { Config.from_env("SANDBOX_TIMEOUT_SECONDS" => "two") }
      assert_match(/SANDBOX_TIMEOUT_SECONDS/, error.message)
      assert_raises(Config::Error) { Config.from_env("SANDBOX_MEMORY_MB" => "256mb") }
    end

    test "limits must be positive, retention may be zero" do
      assert_raises(Config::Error) { Config.from_env("SANDBOX_TIMEOUT_SECONDS" => "0") }
      assert_raises(Config::Error) { Config.from_env("SANDBOX_MEMORY_MB" => "-1") }
      assert_raises(Config::Error) { Config.from_env("MAX_CODE_BYTES" => "0") }
      assert_raises(Config::Error) { Config.from_env("RETENTION_DAYS" => "-1") }
      assert_equal 0, Config.from_env("RETENTION_DAYS" => "0").retention_days
    end

    test "cpus is a positive decimal" do
      assert_equal 0.5, Config.from_env("SANDBOX_CPUS" => "0.5").sandbox_cpus
      assert_raises(Config::Error) { Config.from_env("SANDBOX_CPUS" => "0") }
      assert_raises(Config::Error) { Config.from_env("SANDBOX_CPUS" => "one") }
    end

    test "rate limit is a count per period" do
      c = Config.from_env("RUN_RATE_LIMIT" => "5/15m")
      assert_equal 5, c.run_rate_limit_count
      assert_equal 15.minutes, c.run_rate_limit_period
      assert_equal 1.hour, Config.from_env("RUN_RATE_LIMIT" => "100/1h").run_rate_limit_period
      assert_equal 30.seconds, Config.from_env("RUN_RATE_LIMIT" => "3/30s").run_rate_limit_period
      assert_raises(Config::Error) { Config.from_env("RUN_RATE_LIMIT" => "lots") }
      assert_raises(Config::Error) { Config.from_env("RUN_RATE_LIMIT" => "0/1m") }
      assert_raises(Config::Error) { Config.from_env("RUN_RATE_LIMIT" => "5/1d") }
    end

    test "domains are domains and emails are emails" do
      assert_raises(Config::Error) { Config.from_env("ALLOWED_EMAIL_DOMAINS" => "me@windbornesystems.com") }
      assert_raises(Config::Error) { Config.from_env("ALLOWED_EMAIL_DOMAINS" => "wind borne.com") }
      assert_raises(Config::Error) { Config.from_env("ALLOWED_EMAILS" => "windbornesystems.com") }
      assert_raises(Config::Error) { Config.from_env("ADMIN_EMAILS" => "not-an-email") }
    end

    test "sandbox runner must be a known implementation" do
      assert_equal "fake", Config.from_env("SANDBOX_RUNNER" => "fake").sandbox_runner
      assert_raises(Config::Error) { Config.from_env("SANDBOX_RUNNER" => "podman") }
    end

    test "sandbox concurrency times memory must fit under the configured host memory" do
      assert_nothing_raised { Config.from_env("SANDBOX_CONCURRENCY" => "4", "SANDBOX_MEMORY_MB" => "256", "HOST_MEMORY_MB" => "2048") }
      error = assert_raises(Config::Error) { Config.from_env("SANDBOX_CONCURRENCY" => "8", "SANDBOX_MEMORY_MB" => "256", "HOST_MEMORY_MB" => "1024") }
      assert_match(/HOST_MEMORY_MB/, error.message)
    end

    test "mail_from defaults to the app host without its port" do
      assert_equal "pyrun@localhost", Config.from_env({}).mail_from
      assert_equal "pyrun@run.example.com", Config.from_env("APP_HOST" => "run.example.com").mail_from
      assert_equal "ops@x.io", Config.from_env("MAIL_FROM" => "ops@x.io").mail_from
    end

    test "smtp settings are optional strings" do
      c = Config.from_env("SMTP_ADDRESS" => "smtp.example.com", "SMTP_PORT" => "587", "SMTP_USERNAME" => "u", "SMTP_PASSWORD" => "p")
      assert_equal "smtp.example.com", c.smtp_address
      assert_equal 587, c.smtp_port
      assert_equal "u", c.smtp_username
      assert_equal "p", c.smtp_password
      assert_nil Config.from_env({}).smtp_address
    end

    test "with returns a changed copy and leaves the original alone" do
      original = Config.from_env({})
      changed = original.with(sandbox_timeout_seconds: 2, allowed_email_domains: [ "example.org" ])
      assert_equal 2, changed.sandbox_timeout_seconds
      assert_equal [ "example.org" ], changed.allowed_email_domains
      assert_equal 120, original.sandbox_timeout_seconds
      assert_raises(ArgumentError) { original.with(nonsense: 1) }
    end

    test "configs are frozen" do
      c = Config.from_env({})
      assert c.frozen?
      assert c.allowed_email_domains.frozen?
    end

    test "to_h lists every setting and redacts the smtp password" do
      h = Config.from_env("SMTP_PASSWORD" => "hunter2").to_h
      assert_equal "[REDACTED]", h[:smtp_password]
      assert_equal 120, h[:sandbox_timeout_seconds]
      assert_nil Config.from_env({}).to_h[:smtp_password]
    end

    test "the app exposes the config parsed at boot and tests can swap it" do
      assert_kind_of Config, Pyrun.config
      before = Pyrun.config
      with_config(sandbox_timeout_seconds: 7) do
        assert_equal 7, Pyrun.config.sandbox_timeout_seconds
      end
      assert_same before, Pyrun.config
    end
  end
end
