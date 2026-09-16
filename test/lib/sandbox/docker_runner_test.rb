require "test_helper"

module Sandbox
  # Pure parts of the Docker runner: no daemon needed.
  class DockerRunnerTest < ActiveSupport::TestCase
    setup do
      @runner = DockerRunner.new
      @runtime = Runtime.find("python3.12")
      @limits = Limits.new(timeout_seconds: 7, memory_mb: 128, cpus: 0.5, pids_limit: 32, max_output_bytes: 1000)
    end

    test "Sandbox.runner is the Docker runner by default" do
      with_config(sandbox_runner: "docker") do
        assert_kind_of DockerRunner, Sandbox.runner
      end
    end

    test "the docker run argv carries every isolation flag from the run's own limits" do
      argv = @runner.command(name: "pyrun-abc", runtime: @runtime, limits: @limits)

      assert_equal %w[docker run], argv.first(2)
      %w[
        --name=pyrun-abc --label=app=pyrun --interactive --init
        --network=none --read-only --tmpfs=/tmp:rw,noexec,nosuid,size=64m
        --memory=128m --memory-swap=128m --cpus=0.5 --pids-limit=32
        --ulimit=nofile=256:256 --ulimit=core=0 --ipc=none
        --cap-drop=ALL --security-opt=no-new-privileges --user=65534:65534
      ].each { |flag| assert_includes argv, flag }

      image_index = argv.index(@runtime.image)
      assert image_index, "the image must be in the argv"
      assert_equal %w[timeout -s KILL 7 python3 -I -u -], argv[(image_index + 1)..]
    end

    test "the code never travels in the argv and no shell is involved" do
      argv = @runner.command(name: "pyrun-abc", runtime: @runtime, limits: @limits)
      assert_not_includes argv, "sh"
      assert_not_includes argv, "-c"
      assert argv.all? { |arg| arg.is_a?(String) }
    end

    test "an alternative OCI runtime such as gVisor is a config flag" do
      with_config(sandbox_runtime: "runsc") do
        assert_includes @runner.command(name: "x", runtime: @runtime, limits: @limits), "--runtime=runsc"
      end
      assert_not @runner.command(name: "x", runtime: @runtime, limits: @limits).any? { |a| a.start_with?("--runtime=") }
    end

    test "the docker client gets a minimal environment, never the app's secrets" do
      ENV["PYRUN_TEST_SECRET"] = "hunter2"
      env = @runner.client_env
      assert_not_includes env.keys, "PYRUN_TEST_SECRET"
      assert_includes env.keys, "PATH"
      assert_includes env.keys, "HOME"
    ensure
      ENV.delete("PYRUN_TEST_SECRET")
    end

    test "a run killed because someone asked for it to stop is stopped, whatever the exit code" do
      assert_equal :stopped, DockerRunner.status_for(exit_code: 137, oom_killed: false, killed_for: :stopped)
      assert_equal :stopped, DockerRunner.status_for(exit_code: 0, oom_killed: false, killed_for: :stopped)
    end

    test "outcomes are classified from the exit code, the OOM flag, and why we killed it" do
      assert_equal :succeeded, DockerRunner.status_for(exit_code: 0, oom_killed: false, killed_for: nil)
      assert_equal :failed, DockerRunner.status_for(exit_code: 1, oom_killed: false, killed_for: nil)
      assert_equal :failed, DockerRunner.status_for(exit_code: 137, oom_killed: true, killed_for: nil)
      assert_equal :failed, DockerRunner.status_for(exit_code: 137, oom_killed: false, killed_for: :output)
      assert_equal :timed_out, DockerRunner.status_for(exit_code: 137, oom_killed: false, killed_for: :timeout)
      assert_equal :timed_out, DockerRunner.status_for(exit_code: 124, oom_killed: false, killed_for: :timeout)
      assert_equal :errored, DockerRunner.status_for(exit_code: nil, oom_killed: false, killed_for: nil)
    end
  end
end
