require "application_system_test_case"

class RunsTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery staple"

  test "submitting a script shows it queued, then updates in place when the worker finishes" do
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = false
    sign_in users(:verified)

    click_link "New run"
    assert_selector "h1", text: "New run"
    fill_in_code "print('hello from the sandbox')"
    click_button "Run"

    assert_selector "h1", text: "Queued"
    assert_selector "button[disabled]", text: "Run again"
    assert_no_link "Run again"
    page.execute_script("window.__stayed = true")

    # The worker finishing is a broadcast, which Turbo sends through a debounced
    # job; from here on jobs perform as soon as they are enqueued.
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = true
    run = Run.order(:id).last
    Sandbox::FakeRunner.respond_with(Sandbox::Result.new(status: :succeeded, exit_code: 0, stdout: "hello from the sandbox\n", duration_ms: 812)) do
      ExecuteRunJob.perform_now(run)
    end

    assert_selector "h1", text: "Succeeded"
    assert_selector "pre", text: "hello from the sandbox"
    assert_link "Run again"
    assert_no_selector "button[disabled]", text: "Run again"
    assert page.evaluate_script("window.__stayed"), "the page must update in place, not reload"
  end

  test "the runs list updates in place when one of my runs finishes" do
    run = runs(:verified_queued)
    sign_in users(:verified)
    assert_selector "h1", text: "Runs"
    assert_selector "tbody tr", text: /Queued\s+import time/
    page.execute_script("window.__stayed = true")

    run.update!(status: "succeeded", exit_code: 0, started_at: 2.seconds.ago, finished_at: Time.current, duration_ms: 640)

    assert_selector "tbody tr", text: /Succeeded\s+import time/
    assert_no_selector "tbody tr", text: /Queued\s+import time/
    assert page.evaluate_script("window.__stayed"), "the list must update in place, not reload"
  end

  test "output appears on the run page while it is still running and the box follows the newest line" do
    run = runs(:verified_queued)
    run.update!(status: "running", started_at: 30.seconds.ago)
    sign_in users(:verified)
    visit run_path(run)
    assert_selector "h1", text: "Running"
    assert_no_selector "pre#output"
    assert_selector "[data-elapsed-target=time]", text: /0:3\d/
    assert_eventually_js "parseFloat(document.querySelector('[data-elapsed-target=bar]').style.width) > 20", "the bar should show ~25% before output arrives"
    page.execute_script("window.__stayed = true")

    Runs::Progress.call(run, stdout: "line 1\n", stderr: "")
    assert_selector "pre#output", text: "line 1"
    assert_selector "h1", text: "Running"
    # Output arriving must not touch the clock or the bar (a full-page morph reset both).
    width = page.evaluate_script("parseFloat(document.querySelector('[data-elapsed-target=bar]').style.width) || 0")
    assert_operator width, :>, 20, "the bar reset to #{width}% when output arrived"
    assert_selector "[data-elapsed-target=time]", text: /0:3\d/

    Runs::Progress.call(run, stdout: (1..200).map { |i| "line #{i}" }.join("\n") + "\n", stderr: "")
    assert_selector "pre#output", text: "line 200"
    assert_eventually_js "(() => { const p = document.querySelector('pre#output'); return p.scrollTop + p.clientHeight >= p.scrollHeight - 4 })()", "the output box must follow the newest line"
    assert page.evaluate_script("window.__stayed"), "the page must update in place, not reload"

    Runs::Complete.call(run, Sandbox::Result.new(status: :succeeded, exit_code: 0, stdout: "done\n", stderr: "", duration_ms: 10))
    assert_selector "h1", text: "Succeeded"
  end

  test "a running run can be stopped before its limit" do
    run = runs(:verified_queued)
    run.update!(status: "running", started_at: 4.seconds.ago)
    sign_in users(:verified)
    visit run_path(run)
    assert_selector "h1", text: "Running"

    click_button "Stop"
    assert_selector "button[disabled]", text: "Stopping…"
    assert_not_nil run.reload.stop_requested_at

    # The worker notices within a second and kills the sandbox.
    Runs::Complete.call(run, Sandbox::Result.new(status: :stopped, exit_code: 137, duration_ms: 4800, metadata: { "killed_for" => "stopped" }))
    assert_selector "h1", text: "Stopped"
    assert_text "Stopped before it finished"
    assert_link "Run again"
    assert_no_button "Stop"
  end

  test "a running run shows the elapsed time ticking up and a bar filling toward the limit" do
    run = runs(:verified_queued)
    run.update!(status: "running", started_at: 3.seconds.ago)
    sign_in users(:verified)
    visit run_path(run)

    assert_selector "[data-elapsed-target=time]", text: /\A0:0[3-5]\z/
    assert_selector "[data-elapsed-target=time]", text: /\A0:0[6-9]\z/, wait: 6
    width = page.evaluate_script("document.querySelector('[data-elapsed-target=bar]').style.width")
    assert_match(/\A\d+(\.\d+)?%\z/, width)
    assert_operator width.to_f, :>, 0
  end

  test "the editor is styled after a Turbo navigation, not only after a full load" do
    sign_in users(:verified)
    click_link "New run" # a Turbo visit: the document keeps the CSP of the page it was loaded with
    assert_selector ".cm-editor .cm-gutter", text: "1"
    display = page.evaluate_script("getComputedStyle(document.querySelector('.cm-editor')).display")
    assert_equal "flex", display, "CodeMirror's base styles were rejected by the CSP after the visit"

    visit runs_path
    click_link "New run"
    assert_selector ".cm-editor .cm-gutter", text: "1"
    assert_equal "flex", page.evaluate_script("getComputedStyle(document.querySelector('.cm-editor')).display")
  end

  test "the editor survives repeated failed submissions" do
    sign_in users(:verified)
    click_link "New run"
    assert_selector ".cm-editor"
    page.execute_script("window.__submits = 0; document.addEventListener('turbo:submit-end', () => window.__submits++)")

    3.times do |i|
      click_button "Run"
      assert_submission_rendered(i + 1)
      assert_selector ".field-error", text: /blank/
      assert_selector ".cm-editor .cm-gutter", text: "1"
      assert_equal 1, page.evaluate_script("document.querySelectorAll('.cm-editor').length")
      assert page.evaluate_script("document.querySelector(\"textarea[name='run[code]']\").hidden"), "the textarea must stay behind the editor"
    end

    fill_in_code "print('after errors')"
    click_button "Run"
    assert_selector "pre", text: "print('after errors')"
  end

  test "the editor highlights Python, indents after a colon, indents with Tab, and submits with Cmd or Ctrl+Enter" do
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = false
    sign_in users(:verified)
    visit new_run_path
    assert_selector ".cm-editor .cm-gutter", text: "1"

    fill_in_code "import os"
    assert_selector ".cm-content .tok-keyword", text: "import"

    editor = find(".cm-content")
    editor.send_keys([ modifier_key, "a" ], :backspace)
    editor.send_keys("if True:", :enter, "pass")
    assert_equal "if True:\n    pass", find("textarea[name='run[code]']", visible: :all).value

    editor.send_keys([ modifier_key, "a" ], :backspace)
    editor.send_keys("x = 1", :enter, :tab, "y = 'z'")
    assert_equal "x = 1\n    y = 'z'", find("textarea[name='run[code]']", visible: :all).value
    assert_selector ".cm-content .tok-string", text: "'z'"

    editor.send_keys([ modifier_key, :enter ])
    assert_selector "h1", text: "Queued"
    assert_selector "pre", text: "x = 1\n    y = 'z'"
  end

  test "past runs are listed and can be opened, and a run can be run again" do
    sign_in users(:verified)
    assert_selector "tbody tr", count: 3

    click_link "raise RuntimeError('boom')"
    assert_selector "h1", text: "Failed"
    assert_text "RuntimeError: boom"

    click_link "Back to runs"
    assert_selector "h1", text: "Runs"
    assert_current_path runs_path
    assert_selector "tbody tr", count: 3

    visit run_path(runs(:verified_failed))

    click_link "Run again"
    assert_selector "h1", text: "New run"
    assert_selector ".cm-content", text: "raise RuntimeError('boom')"
  end

  test "arrow keys and the pager step through my runs" do
    sign_in users(:verified)
    visit run_path(runs(:verified_failed))
    assert_selector "h1", text: "Failed"

    find("body").send_keys(:right)
    assert_selector "h1", text: "Succeeded"
    assert_current_path run_path(runs(:verified_succeeded))

    find("body").send_keys(:right)
    assert_selector "h1", text: "Succeeded", wait: 1 # nothing older: stays put
    assert_current_path run_path(runs(:verified_succeeded))

    find("body").send_keys(:left)
    assert_selector "h1", text: "Failed"
    assert_no_selector "html[data-turbo-preview]" # Turbo shows a cached preview first; wait for the fresh page
    click_link "Newer"
    assert_selector "h1", text: "Queued"
    assert_current_path run_path(runs(:verified_queued))
  end

  test "an admin can browse everyone's runs" do
    with_config(admin_emails: [ users(:admin).email_address ]) do
      sign_in users(:admin)
      click_link "All runs"
      assert_selector "h1", text: "All runs"
      assert_selector "tbody tr", count: Run.count
      assert_text "verified@windbornesystems.com"

      fill_in "Owner", with: "verified@"
      click_button "Filter"
      assert_selector "tbody tr", count: 3

      click_link "raise RuntimeError('boom')"
      assert_selector "h1", text: "Failed"
      assert_text "verified@windbornesystems.com"
      click_link "Back to all runs"
      assert_selector "h1", text: "All runs"
      assert_current_path admin_runs_path
    end
  end

  private
    # Each Turbo form submission ends with turbo:submit-end; wait for the nth one so
    # assertions never run against the previous render.
    def assert_submission_rendered(count)
      deadline = Time.now + Capybara.default_max_wait_time
      sleep 0.05 until page.evaluate_script("window.__submits") >= count || Time.now > deadline
      assert_operator page.evaluate_script("window.__submits"), :>=, count, "submission #{count} never finished"
    end

    # The textarea is hidden behind the CodeMirror editor; type where a person would.
    def assert_eventually_js(expression, message)
      page.document.synchronize(3) { page.evaluate_script(expression) or raise Capybara::ElementNotFound, message }
    end

    # The editor uses Cmd on macOS and Ctrl elsewhere; Chromium runs on the same
    # OS as the tests, so pick the key the browser will honour.
    def modifier_key
      RUBY_PLATFORM.include?("darwin") ? :meta : :control
    end

    def fill_in_code(text)
      editor = find(".cm-content")
      editor.click
      editor.send_keys([ modifier_key, "a" ], :backspace)
      editor.send_keys(text)
    end

    def sign_in(user)
      visit login_path
      fill_in "Email", with: user.email_address
      fill_in "Password", with: PASSWORD
      click_button "Sign in"
      assert_selector "h1", text: "Runs"
    end
end
