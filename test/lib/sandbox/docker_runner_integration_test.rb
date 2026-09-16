require "test_helper"

module Sandbox
  # Proves the isolation claims in docs/DESIGN.md §5 against a real Docker daemon
  # with real hostile programs. Skipped when Docker or the image is not available;
  # CI builds the image first with bin/sandbox-build.
  class DockerRunnerIntegrationTest < ActiveSupport::TestCase
    # These tests share one Docker daemon, and the reaper test removes every
    # labelled container, so they must never overlap. Rails runs test methods in
    # parallel worker processes; an exclusive file lock serializes them across
    # processes without depending on test-runner internals.
    LOCK_PATH = Rails.root.join("tmp/sandbox_integration.lock")

    setup do
      skip "Docker is not available" unless docker_available?
      skip "Sandbox image #{Pyrun.config.sandbox_image} is not built; run bin/sandbox-build" unless sandbox_image_built?
      @lock = File.open(LOCK_PATH, File::RDWR | File::CREAT, 0o644)
      @lock.flock(File::LOCK_EX)
      @runner = DockerRunner.new
    end

    teardown do
      @lock&.flock(File::LOCK_UN)
      @lock&.close
    end

    test "hello world succeeds with its output, exit code, timing, and image digest" do
      result = execute("print('hello from the sandbox')")
      assert_equal :succeeded, result.status
      assert_equal 0, result.exit_code
      assert_equal "hello from the sandbox\n", result.stdout
      assert_equal "", result.stderr
      assert_operator result.duration_ms, :>, 0
      assert_match(/\Asha256:[0-9a-f]{64}\z/, result.image_digest)
      assert_not result.stdout_truncated
      assert_not result.oom_killed
    end

    test "an uncaught exception fails with the traceback on stderr" do
      result = execute("raise RuntimeError('boom')")
      assert_equal :failed, result.status
      assert_equal 1, result.exit_code
      assert_includes result.stderr, "RuntimeError: boom"
    end

    test "numpy is available" do
      result = execute("import numpy as np\nprint(int((np.arange(10) ** 2).sum()))")
      assert_equal :succeeded, result.status, result.stderr
      assert_equal "285\n", result.stdout
    end

    test "an infinite loop is killed at the timeout and reported as timed out" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = execute("print('starting', flush=True)\nwhile True:\n    pass", timeout_seconds: 2)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_equal :timed_out, result.status, result.inspect
      assert_includes result.stdout, "starting", "output printed before the kill must survive"
      assert_operator elapsed, :<, 8, "the kill must not wait for the supervisor's grace period to expire twice"
    end

    test "a memory bomb is killed by the cgroup and reported as out of memory" do
      result = execute("chunks = []\nwhile True:\n    chunks.append(bytearray(8 * 1024 * 1024))", memory_mb: 64, timeout_seconds: 10)
      assert_equal :failed, result.status
      assert result.oom_killed, "expected the OOM flag; exit=#{result.exit_code} stderr=#{result.stderr}"
    end

    test "a fork bomb runs out of pids instead of taking the host" do
      code = <<~PY
        import os, sys
        try:
            while True:
                if os.fork() == 0:
                    continue
        except BlockingIOError:
            print("fork refused", flush=True)
            sys.exit(3)
      PY
      result = execute(code, pids_limit: 16, timeout_seconds: 10)
      assert_includes [ :failed, :timed_out ], result.status
      assert_includes result.stdout, "fork refused"
    end

    test "there is no network" do
      code = <<~PY
        import socket
        try:
            socket.create_connection(("1.1.1.1", 80), timeout=2)
            print("connected")
        except OSError as e:
            print("blocked:", type(e).__name__)
      PY
      result = execute(code)
      assert_equal :succeeded, result.status, result.stderr
      assert_match(/\Ablocked:/, result.stdout)
    end

    test "the filesystem is read-only except a small tmpfs" do
      code = <<~PY
        try:
            open("/etc/x", "w")
            print("root writable")
        except OSError as e:
            print("root read-only:", type(e).__name__)
        with open("/tmp/x", "w") as f:
            f.write("ok")
        print("tmp:", open("/tmp/x").read())
      PY
      result = execute(code)
      assert_equal :succeeded, result.status, result.stderr
      assert_includes result.stdout, "root read-only:"
      assert_includes result.stdout, "tmp: ok"
    end

    test "the sandbox has no capabilities, no interfaces, no docker socket, no shm, and no app environment" do
      code = <<~PY
        import os
        caps = [l.split()[1] for l in open("/proc/self/status") if l.startswith("CapEff")][0]
        print("caps", caps)
        print("uid", os.getuid())
        up = [i for i in os.listdir("/sys/class/net") if os.path.isdir(f"/sys/class/net/{i}") and open(f"/sys/class/net/{i}/operstate").read().strip() != "down"]
        print("ifaces", sorted(up))
        print("docker.sock", os.path.exists("/var/run/docker.sock"))
        print("shm", os.path.exists("/dev/shm"))
        print("env", sorted(k for k in os.environ if k.startswith(("RAILS", "SECRET", "DATABASE", "SMTP", "AWS", "DOCKER"))))
      PY
      result = execute(code)
      assert_equal :succeeded, result.status, result.stderr
      assert_includes result.stdout, "caps 0000000000000000"
      assert_includes result.stdout, "uid 65534"
      assert_includes result.stdout, "ifaces ['lo']"
      assert_includes result.stdout, "docker.sock False"
      assert_includes result.stdout, "shm False"
      assert_includes result.stdout, "env []"
    end

    test "runaway output is cut at the limit and the run is stopped" do
      result = execute("while True:\n    print('x' * 1000)", max_output_bytes: 20_000, timeout_seconds: 10)
      assert_equal :failed, result.status, result.inspect
      assert result.stdout_truncated
      assert_operator result.stdout.bytesize, :<=, 20_000
      assert_operator result.duration_ms, :<, 9_000, "the output cap must stop the run before the timeout"
    end

    test "output that exactly fills the cap is kept whole and not reported as cut" do
      result = execute("import sys\nsys.stdout.write('x' * 20_000)", max_output_bytes: 20_000)
      assert_equal :succeeded, result.status, result.inspect
      assert_equal 20_000, result.stdout.bytesize
      assert_not result.stdout_truncated
    end

    test "output is reported while the program is still running" do
      snapshots = []
      result = execute("import time\nfor i in range(3):\n    print(i, flush=True)\n    time.sleep(1.1)") { |stdout, _stderr| snapshots << stdout }
      assert_equal :succeeded, result.status, result.inspect
      assert_equal "0\n1\n2\n", result.stdout
      assert_operator snapshots.size, :>=, 2, "expected progress about once a second, got #{snapshots.inspect}"
      assert_operator snapshots.first.bytesize, :<, result.stdout.bytesize
      assert snapshots.each_cons(2).all? { |a, b| b.start_with?(a) }, "snapshots must only grow"
    end

    test "a running program is stopped when asked, well before its limit" do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      asked = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 > 1.5 }
      result = execute("import time\nwhile True: time.sleep(0.1)", timeout_seconds: 30, stop_when: asked)
      assert_equal :stopped, result.status, result.inspect
      assert_operator result.duration_ms, :<, 6_000
      assert_equal "stopped", result.metadata["killed_for"]
    end

    test "reading stdin hits EOF immediately" do
      result = execute("input()")
      assert_equal :failed, result.status
      assert_includes result.stderr, "EOFError"
    end

    test "arbitrary bytes on stdout do not break the runner" do
      result = execute("import sys\nsys.stdout.buffer.write(b'ok\\xff\\x00!\\n')")
      assert_equal :succeeded, result.status, result.stderr
      assert_includes result.stdout.b, "ok"
    end

    test "healthy? checks the daemon and the image" do
      assert @runner.healthy?
      with_config(sandbox_image: "pyrun-sandbox:does-not-exist") do
        assert_not DockerRunner.new.healthy?
      end
    end

    test "a missing image is a platform error, not a hang" do
      missing = Runtime::Definition.new(key: "x", label: "x", image: "pyrun-sandbox:does-not-exist", command: %w[python3 -])
      result = @runner.run("print(1)", runtime: missing, limits: limits)
      assert_equal :errored, result.status
      assert_match(/does-not-exist|No such image|Unable to find/i, result.stderr)
    end

    test "reap_orphans removes labelled containers nobody supervises" do
      name = "pyrun-orphan-#{SecureRandom.hex(4)}"
      system("docker", "run", "--detach", "--name", name, "--label", "app=pyrun", "--network", "none", Pyrun.config.sandbox_image, "sleep", "300", out: File::NULL) || flunk("could not start a decoy container")
      begin
        assert_equal 0, @runner.reap_orphans(older_than: 1.hour), "a fresh container must be left alone"
        assert_operator @runner.reap_orphans(older_than: 0.seconds), :>=, 1
        assert_not system("docker", "container", "inspect", name, out: File::NULL, err: File::NULL), "the orphan must be gone"
      ensure
        system("docker", "rm", "-f", name, out: File::NULL, err: File::NULL)
      end
    end

    test "no container is left behind after a run" do
      before = labelled_containers
      execute("print(1)")
      execute("while True: pass", timeout_seconds: 1)
      assert_equal before, labelled_containers
    end

    private
      def limits(**overrides)
        Limits.new(**{ timeout_seconds: 5, memory_mb: 64, cpus: 0.5, pids_limit: 16, max_output_bytes: 100_000 }.merge(overrides))
      end

      def execute(code, stop_when: nil, **overrides, &progress)
        @runner.run(code, runtime: Runtime.default, limits: limits(**overrides), stop_when: stop_when, &progress)
      end

      def labelled_containers
        `docker ps -aq --filter label=app=pyrun`.split.sort
      end
  end
end
