require "test_helper"

class RunsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:verified) }

  test "the runs page asks anonymous visitors to sign in" do
    get runs_path
    assert_redirected_to login_path
  end

  test "the root path is the runs page" do
    sign_in_as @user
    get root_path
    assert_select "h1", "Runs"
  end

  test "a user with no runs sees an empty state with a way to start" do
    sign_in_as users(:unverified).tap(&:verify!)
    get runs_path
    assert_response :success
    assert_select "p", /No runs yet/
    assert_select "a[href=?]", new_run_path
  end

  test "the index lists only my runs, newest first, with status and first line" do
    sign_in_as @user
    get runs_path
    assert_response :success
    rows = css_select("tbody tr")
    assert_equal 3, rows.size
    assert_match(/import time/, rows[0].text)
    assert_match(/Queued/, rows[0].text)
    assert_match(/raise RuntimeError/, rows[1].text)
    assert_match(/Failed/, rows[1].text)
    assert_match(/print\('hello'\)/, rows[2].text)
    assert_match(/Succeeded/, rows[2].text)
    assert_no_match(/print\(2 \+ 2\)/, response.body, "another user's run must not appear")
  end

  test "the index can be filtered by status and ignores unknown statuses" do
    sign_in_as @user
    get runs_path(status: "failed")
    assert_equal 1, css_select("tbody tr").size
    assert_select "tbody tr", /raise RuntimeError/

    get runs_path(status: "nonsense")
    assert_equal 3, css_select("tbody tr").size
  end

  test "the index paginates" do
    sign_in_as @user
    30.times { |i| @user.runs.create!(code: "print(#{i})", runtime: "python3.12", timeout_seconds: 1, memory_mb: 1, cpus: 1, pids_limit: 1, max_output_bytes: 1, queued_at: Time.current) }
    get runs_path
    assert_equal 25, css_select("tbody tr").size
    assert_select "a[href=?]", runs_path(page: 2)

    get runs_path(page: 2)
    assert_equal 8, css_select("tbody tr").size
  end

  test "the new run page states the limits from config" do
    sign_in_as @user
    with_config(sandbox_timeout_seconds: 300, sandbox_memory_mb: 512, sandbox_cpus: 2.0, sandbox_max_output_bytes: 2_000_000) do
      get new_run_path
    end
    assert_response :success
    assert_select "h1", "New run"
    assert_select "p", /5 minutes/
    assert_select "p", /512 MB/
    assert_select "p", /2 CPUs/
    assert_select "p", /2 MB of output/
    assert_select "textarea[name=?]", "run[code]"
  end

  test "the new run page can be prefilled to run something again" do
    sign_in_as @user
    get new_run_path(code: "print('again')")
    assert_select "textarea", /print\('again'\)/
  end

  test "submitting code creates a queued run stamped with the current limits and goes to it" do
    sign_in_as @user
    assert_difference "Run.count", 1 do
      post runs_path, params: { run: { code: "print('new')" } }
    end
    run = Run.order(:id).last
    assert_redirected_to run_path(run)
    assert run.queued?
    assert_equal @user, run.user
    assert_equal Pyrun.config.sandbox_timeout_seconds, run.timeout_seconds
    assert_enqueued_with job: ExecuteRunJob, args: [ run ]
  end

  test "blank code re-renders the form with the reason" do
    sign_in_as @user
    assert_no_difference "Run.count" do
      post runs_path, params: { run: { code: "   " } }
    end
    assert_response :unprocessable_content
    assert_select ".field-error", /be blank/
  end

  test "a refused submission explains why and keeps the code" do
    sign_in_as @user
    with_config(runs_paused: true) do
      post runs_path, params: { run: { code: "print(1)" } }
    end
    assert_response :unprocessable_content
    assert_select ".flash-alert", /paused/
    assert_select "textarea", /print\(1\)/
  end

  test "submissions are rate limited per user" do
    sign_in_as @user
    with_config(run_rate_limit: [ 2, 60 ], max_active_runs_per_user: 10) do
      3.times { post runs_path, params: { run: { code: "print(1)" } } }
    end
    assert_response :too_many_requests
  end

  test "the show page renders the code, output, and details of my run" do
    sign_in_as @user
    run = runs(:verified_failed)
    get run_path(run)
    assert_response :success
    assert_select "h1", /Failed/
    assert_select "pre", /raise RuntimeError/
    assert_select "pre", /RuntimeError: boom/
    assert_select "dd", "1" # exit code
    assert_select "dd", /640 ms/
    assert_select "a[href=?]", new_run_path(code: run.code)
  end

  test "output is escaped, never rendered as markup" do
    sign_in_as @user
    run = @user.runs.create!(code: "print('<b>x</b>')", stdout: "<b>bold</b><script>alert(1)</script>", status: "succeeded", exit_code: 0,
                             runtime: "python3.12", timeout_seconds: 1, memory_mb: 1, cpus: 1, pids_limit: 1, max_output_bytes: 1, queued_at: Time.current)
    get run_path(run)
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_not_includes response.body, "<script>alert(1)</script>"
  end

  test "a run whose output expired says so instead of pretending nothing was printed" do
    sign_in_as @user
    run = runs(:verified_succeeded)
    run.update!(stdout: nil, stderr: nil, outputs_expired_at: 1.day.ago)
    get run_path(run)
    assert_select "p", /Output expired/
    assert_select "p", { text: /Nothing was printed/, count: 0 }
  end

  test "a queued run says it is waiting, counts the wait, and subscribes to updates" do
    sign_in_as @user
    run = runs(:verified_queued)
    get run_path(run)
    assert_select "h1", /Queued/
    assert_select "turbo-cable-stream-source"
    assert_select "[data-controller=elapsed][data-elapsed-mode-value=queued]" do
      assert_select "[data-elapsed-target=time]", /\A\d+:\d\d\z/
      assert_select ".progress-bar-indeterminate"
    end
  end

  test "a running run shows a live clock against its own limit" do
    sign_in_as @user
    run = runs(:verified_queued)
    run.update!(status: "running", started_at: 65.seconds.ago)
    get run_path(run)
    assert_select "h1", /Running/
    assert_select "[data-controller=elapsed][data-elapsed-mode-value=running][data-elapsed-limit-value=?]", run.timeout_seconds.to_s do
      assert_select "[data-elapsed-target=time]", /\A1:0[5-7]\z/
      assert_select "[role=progressbar][aria-valuemax=?]", run.timeout_seconds.to_s
      assert_select "[data-elapsed-target=bar]"
    end
    assert_select "span", /limit 2:00/
  end

  test "a finished run has no clock" do
    sign_in_as @user
    get run_path(runs(:verified_succeeded))
    assert_select "[data-controller=elapsed]", count: 0
  end

  test "another user's run is not found" do
    sign_in_as @user
    get run_path(runs(:admin_succeeded))
    assert_response :not_found
  end

  test "an admin can open anyone's run" do
    with_config(admin_emails: [ users(:admin).email_address ]) do
      sign_in_as users(:admin)
      get run_path(runs(:verified_failed))
      assert_response :success
    end
  end
end
