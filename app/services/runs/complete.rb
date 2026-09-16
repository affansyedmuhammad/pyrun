module Runs
  # Writes a runner's result, or a platform error, onto a run. The only place a
  # run reaches a terminal status.
  class Complete
    def self.call(run, result) = new(run).record(result)
    def self.errored(run, message) = new(run).error(message)
    def self.stopped(run) = new(run).stop

    def initialize(run)
      @run = run
    end

    def record(result)
      finished_at = Time.current
      @run.update!(
        status: result.status.to_s,
        exit_code: result.exit_code,
        stdout: clean(result.stdout),
        stderr: clean(result.stderr),
        stdout_truncated: result.stdout_truncated,
        stderr_truncated: result.stderr_truncated,
        oom_killed: result.oom_killed,
        finished_at: finished_at,
        duration_ms: result.duration_ms || measured_duration(finished_at),
        runner_metadata: (result.metadata || {}).merge("image_digest" => result.image_digest).compact
      )
      Rails.logger.info "run.finished run=#{@run.id} status=#{@run.status} exit=#{@run.exit_code} ms=#{@run.duration_ms}"
    end

    # A person ended the run early, before or during execution.
    def stop
      finished_at = Time.current
      @run.update!(status: "stopped", finished_at: finished_at, duration_ms: measured_duration(finished_at))
      Rails.logger.info "run.stopped run=#{@run.id} ms=#{@run.duration_ms.inspect}"
    end

    def error(message)
      finished_at = Time.current
      @run.update!(status: "errored", error_message: message.to_s.truncate(255), finished_at: finished_at, duration_ms: measured_duration(finished_at))
      Rails.logger.error "run.errored run=#{@run.id} message=#{message.to_s.inspect}"
    end

    # Python can print arbitrary bytes. Postgres refuses NUL in text and nothing
    # downstream should have to think about invalid UTF-8. Progress uses it too.
    def self.clean(text)
      text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("�").delete("\0")
    end

    private
      def clean(text) = self.class.clean(text)

      def measured_duration(finished_at)
        ((finished_at - @run.started_at) * 1000).round if @run.started_at
      end
  end
end
