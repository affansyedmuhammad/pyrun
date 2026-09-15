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

  test "the editor highlights Python, indents after a colon, indents with Tab, and submits with Cmd+Enter" do
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = false
    sign_in users(:verified)
    visit new_run_path
    assert_selector ".cm-editor .cm-gutter", text: "1"

    fill_in_code "import os"
    assert_selector ".cm-content .tok-keyword", text: "import"

    editor = find(".cm-content")
    editor.send_keys([ :meta, "a" ], :backspace)
    editor.send_keys("if True:", :enter, "pass")
    assert_equal "if True:\n    pass", find("textarea[name='run[code]']", visible: :all).value

    editor.send_keys([ :meta, "a" ], :backspace)
    editor.send_keys("x = 1", :enter, :tab, "y = 'z'")
    assert_equal "x = 1\n    y = 'z'", find("textarea[name='run[code]']", visible: :all).value
    assert_selector ".cm-content .tok-string", text: "'z'"

    editor.send_keys([ :meta, :enter ])
    assert_selector "h1", text: "Queued"
    assert_selector "pre", text: "x = 1\n    y = 'z'"
  end

  test "past runs are listed and can be opened, and a run can be run again" do
    sign_in users(:verified)
    assert_selector "tbody tr", count: 3

    click_link "raise RuntimeError('boom')"
    assert_selector "h1", text: "Failed"
    assert_text "RuntimeError: boom"

    click_link "Run again"
    assert_selector "h1", text: "New run"
    assert_selector ".cm-content", text: "raise RuntimeError('boom')"
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
    end
  end

  private
    # The textarea is hidden behind the CodeMirror editor; type where a person would.
    def fill_in_code(text)
      editor = find(".cm-content")
      editor.click
      editor.send_keys([ :meta, "a" ], :backspace)
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
