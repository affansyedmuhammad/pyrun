require "open3"
require "securerandom"
require "time"

module Sandbox
  # One throwaway container per run, supervised from the worker. Every isolation
  # flag is applied at `docker run` time from the run's own recorded limits, the
  # code arrives on stdin, and the container is killed by name at the deadline.
  # See docs/DESIGN.md §5.4 and §5.5.
  class DockerRunner < Runner
    LABEL = "app=pyrun"
    NAME_PREFIX = "pyrun-"
    GRACE_SECONDS = 5 # how long past the in-container timeout the supervisor waits before killing
    READ_CHUNK = 16 * 1024
    TIMEOUT_EXIT_CODES = [ 124, 137 ].freeze

    # The docker client needs a PATH and its own config; it never sees the app's
    # secrets. This is pass-through to a subprocess, not app configuration.
    CLIENT_ENV_KEYS = %w[PATH HOME DOCKER_HOST DOCKER_CONFIG DOCKER_CONTEXT DOCKER_CERT_PATH DOCKER_TLS_VERIFY].freeze

    Supervision = Struct.new(:stdout, :stderr, :stdout_truncated, :stderr_truncated, :duration_ms, :killed_for, :client_exit, keyword_init: true)

    def self.status_for(exit_code:, oom_killed:, killed_for:)
      return :errored if exit_code.nil?
      return :failed if oom_killed || killed_for == :output
      return :timed_out if killed_for == :timeout
      exit_code.zero? ? :succeeded : :failed
    end

    def run(code, runtime:, limits:)
      name = "#{NAME_PREFIX}#{SecureRandom.hex(6)}"
      supervision = supervise(command(name: name, runtime: runtime, limits: limits), code, name: name, limits: limits)
      inspection = inspect_container(name)

      killed_for = supervision.killed_for
      if killed_for.nil? && !inspection[:oom_killed] && TIMEOUT_EXIT_CODES.include?(inspection[:exit_code]) &&
         supervision.duration_ms >= (limits.timeout_seconds * 1000) - 500
        killed_for = :timeout # the in-container `timeout` fired before the supervisor's deadline
      end

      Result.new(
        status: self.class.status_for(exit_code: inspection[:exit_code], oom_killed: inspection[:oom_killed] == true, killed_for: killed_for),
        exit_code: inspection[:exit_code],
        stdout: supervision.stdout,
        stderr: supervision.stderr,
        stdout_truncated: supervision.stdout_truncated,
        stderr_truncated: supervision.stderr_truncated,
        duration_ms: supervision.duration_ms,
        oom_killed: inspection[:oom_killed] == true,
        image_digest: inspection[:image_digest],
        metadata: { "container" => name, "client_exit" => supervision.client_exit, "killed_for" => killed_for&.to_s }.compact
      )
    ensure
      remove_container(name) if name
    end

    def command(name:, runtime:, limits:)
      argv = [
        "docker", "run",
        "--name=#{name}", "--label=#{LABEL}", "--interactive", "--init", "--pull=never",
        "--network=none",                                  # no exfiltration, no SSRF, no pip
        "--read-only",                                     # immutable rootfs
        "--tmpfs=/tmp:rw,noexec,nosuid,size=64m",          # the only writable path
        "--memory=#{limits.memory_mb}m", "--memory-swap=#{limits.memory_mb}m",
        "--cpus=#{limits.cpus}",
        "--pids-limit=#{limits.pids_limit}",
        "--ulimit=nofile=256:256", "--ulimit=core=0",
        "--ipc=none",                                      # no /dev/shm to fill
        "--cap-drop=ALL", "--security-opt=no-new-privileges",
        "--user=65534:65534"                               # nobody
      ]
      argv << "--runtime=#{Pyrun.config.sandbox_runtime}" if Pyrun.config.sandbox_runtime
      argv << runtime.image
      argv + [ "timeout", "-s", "KILL", limits.timeout_seconds.to_s ] + runtime.command
    end

    def reap_orphans(older_than:)
      listing, status = Open3.capture2(client_env, "docker", "ps", "--all", "--filter", "label=#{LABEL}",
                                       "--format", "{{.ID}}\t{{.CreatedAt}}", unsetenv_others: true)
      return 0 unless status.success?

      cutoff = Time.now - older_than
      ids = listing.each_line.filter_map do |line|
        id, created = line.chomp.split("\t", 2)
        id if created && Time.parse(created) <= cutoff
      end
      ids.each { |id| docker_quietly("rm", "--force", id) }
      ids.size
    end

    def healthy?
      docker_quietly("info") && docker_quietly("image", "inspect", Runtime.default.image)
    end

    def client_env
      ENV.slice(*CLIENT_ENV_KEYS)
    end

    private
      def supervise(argv, code, name:, limits:)
        started = monotonic
        killed_for = nil
        buffers = {}
        truncated = {}

        client_exit = Open3.popen3(client_env, *argv, unsetenv_others: true) do |stdin, stdout, stderr, waiter|
          begin
            stdin.binmode
            stdin.write(code)
          rescue Errno::EPIPE
            # the container refused stdin (it never started); the exit code says why
          ensure
            stdin.close
          end

          readers = [ stdout, stderr ].map do |io|
            buffers[io] = +"".b
            truncated[io] = false
            Thread.new do
              loop do
                chunk = io.readpartial(READ_CHUNK)
                room = limits.max_output_bytes - buffers[io].bytesize
                if chunk.bytesize > room
                  buffers[io] << chunk.byteslice(0, room)
                  truncated[io] = true
                  killed_for ||= :output
                  kill(name)
                  io.read # drain so the client can exit; nothing more is kept
                  break
                end
                buffers[io] << chunk
              end
            rescue EOFError, IOError
              # stream closed
            end
          end

          unless waiter.join(limits.timeout_seconds + GRACE_SECONDS)
            killed_for ||= :timeout
            kill(name)
            waiter.join(GRACE_SECONDS) || (Process.kill("KILL", waiter.pid) rescue nil)
          end
          readers.each { |thread| thread.join(GRACE_SECONDS) }
          waiter.value.exitstatus
        end

        Supervision.new(
          stdout: buffers.values[0].to_s, stderr: buffers.values[1].to_s,
          stdout_truncated: truncated.values[0] == true, stderr_truncated: truncated.values[1] == true,
          duration_ms: ((monotonic - started) * 1000).round, killed_for: killed_for, client_exit: client_exit
        )
      end

      def inspect_container(name)
        out, status = Open3.capture2(client_env, "docker", "container", "inspect",
                                     "--format", "{{.State.ExitCode}} {{.State.OOMKilled}} {{.Image}}", name,
                                     unsetenv_others: true, err: File::NULL)
        return {} unless status.success?

        exit_code, oom, image = out.split
        { exit_code: exit_code.to_i, oom_killed: oom == "true", image_digest: image }
      end

      # By container name: killing the docker client would not stop the container.
      def kill(name)
        docker_quietly("kill", "--signal=KILL", name)
      end

      def remove_container(name)
        docker_quietly("rm", "--force", name)
      end

      def docker_quietly(*args)
        system(client_env, "docker", *args, unsetenv_others: true, out: File::NULL, err: File::NULL)
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
  end
end
