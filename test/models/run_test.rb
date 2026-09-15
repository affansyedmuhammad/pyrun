require "test_helper"

class RunTest < ActiveSupport::TestCase
  test "requires code" do
    run = build_run(code: "")
    assert_not run.valid?
    assert_includes run.errors[:code], "can't be blank"
  end

  test "code may not exceed the configured size" do
    with_config(max_code_bytes: 10) do
      run = build_run(code: "print('this is too long')")
      assert_not run.valid?
      assert_includes run.errors[:code], "is too long (maximum is 10 bytes)"
    end
  end

  test "code may not contain NUL bytes" do
    run = build_run(code: "print('a')\0")
    assert_not run.valid?
    assert_includes run.errors[:code], "can't contain NUL bytes"
  end

  test "status defaults to queued and only known statuses are allowed" do
    assert_equal "queued", Run.new.status
    run = build_run
    assert_nothing_raised { run.status = "exploded" }
    assert_not run.valid?
    assert_includes run.errors[:status], "is not included in the list"
  end

  test "active runs are queued or running" do
    assert_equal [ runs(:verified_queued) ], Run.active.to_a
  end

  test "recent orders newest first" do
    assert_equal [ runs(:verified_queued), runs(:verified_failed), runs(:verified_succeeded) ], users(:verified).runs.recent.to_a
  end

  test "finished? is true for every terminal status" do
    assert runs(:verified_succeeded).finished?
    assert runs(:verified_failed).finished?
    assert_not runs(:verified_queued).finished?
    assert_not build_run(status: "running").finished?
  end

  test "limits exposes the recorded limits as a struct" do
    limits = runs(:verified_succeeded).limits
    assert_kind_of Sandbox::Limits, limits
    assert_equal 120, limits.timeout_seconds
    assert_equal 256, limits.memory_mb
    assert_equal 1.0, limits.cpus
    assert_equal 64, limits.pids_limit
    assert_equal 1_000_000, limits.max_output_bytes
  end

  test "runtime_definition looks up the registry entry" do
    definition = runs(:verified_succeeded).runtime_definition
    assert_equal "python3.12", definition.key
    assert_equal %w[python3 -I -u -], definition.command
  end

  test "first_line is the first non-blank line of code, trimmed" do
    assert_equal "print('hello')", runs(:verified_succeeded).first_line
    assert_equal "import time", runs(:verified_queued).first_line
    assert_equal "x = 1", build_run(code: "\n\n   x = 1  \nprint(x)").first_line
  end

  test "code, stdout, and stderr are encrypted at rest" do
    run = runs(:verified_succeeded)
    raw = Run.connection.select_one("SELECT code, stdout, stderr FROM runs WHERE id = #{run.id}")
    assert_equal "print('hello')", run.code
    assert_not_includes raw["code"], "hello"
    assert_not_includes raw["stdout"], "hello"
  end

  test "a run is destroyed with its user" do
    user = users(:verified)
    assert_difference "Run.count", -user.runs.count do
      user.destroy!
    end
  end

  private
    def build_run(**attrs)
      users(:verified).runs.build({
        code: "print('x')", runtime: "python3.12", timeout_seconds: 120, memory_mb: 256, cpus: 1.0,
        pids_limit: 64, max_output_bytes: 1_000_000, queued_at: Time.current
      }.merge(attrs))
    end
end
