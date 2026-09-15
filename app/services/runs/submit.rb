module Runs
  # The one place a run is created. Enforces the caps, stamps the run with the
  # runtime and limits in force right now, saves it, and enqueues execution.
  # A JSON API or a CLI would call this and inherit every rule.
  class Submit
    Result = Data.define(:status, :run, :error) do
      %i[created invalid rejected].each do |name|
        define_method(:"#{name}?") { status == name }
      end
    end

    def self.call(**) = new(**).call

    def initialize(user:, code:, runtime: Sandbox::Runtime.default.key)
      @user = user
      @code = code
      @runtime = runtime.to_s
    end

    def call
      if (reason = refusal)
        return Result.new(:rejected, nil, reason)
      end

      run = build
      if run.save
        ExecuteRunJob.perform_later(run)
        Rails.logger.info "run.submitted run=#{run.id} user=#{@user.id} bytes=#{run.code.bytesize}"
        Result.new(:created, run, nil)
      else
        Result.new(:invalid, run, nil)
      end
    end

    private
      def refusal
        config = Pyrun.config
        if config.runs_paused
          I18n.t("runs.submit.paused")
        elsif @user.runs.active.count >= config.max_active_runs_per_user
          I18n.t("runs.submit.too_many_active", count: config.max_active_runs_per_user)
        elsif Run.queued.count >= config.max_queue_depth
          I18n.t("runs.submit.queue_full")
        end
      end

      def build
        config = Pyrun.config
        image = Sandbox::Runtime.keys.include?(@runtime) ? Sandbox::Runtime.find(@runtime).image : nil
        @user.runs.build(
          code: @code,
          runtime: @runtime,
          sandbox_image: image,
          timeout_seconds: config.sandbox_timeout_seconds,
          memory_mb: config.sandbox_memory_mb,
          cpus: config.sandbox_cpus,
          pids_limit: config.sandbox_pids_limit,
          max_output_bytes: config.sandbox_max_output_bytes,
          queued_at: Time.current
        )
      end
  end
end
