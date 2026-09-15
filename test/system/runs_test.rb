require "application_system_test_case"

class RunsTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery staple"

  test "submitting a script shows it queued, then updates in place when the worker finishes" do
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = false
    sign_in users(:verified)

    click_link "New run"
    assert_selector "h1", text: "New run"
    fill_in "Code", with: "print('hello from the sandbox')"
    click_button "Run"

    assert_selector "h1", text: "Queued"
    page.execute_script("window.__stayed = true")

    run = Run.order(:id).last
    Sandbox::FakeRunner.respond_with(Sandbox::Result.new(status: :succeeded, exit_code: 0, stdout: "hello from the sandbox\n", duration_ms: 812)) do
      ExecuteRunJob.perform_now(run)
    end

    assert_selector "h1", text: "Succeeded"
    assert_selector "pre", text: "hello from the sandbox"
    assert page.evaluate_script("window.__stayed"), "the page must update in place, not reload"
  end

  test "the editor indents with Tab and submits with Cmd+Enter" do
    sign_in users(:verified)
    visit new_run_path
    editor = find_field("Code")
    editor.send_keys("if True:", :enter, :tab, "print(1)")
    assert_equal "if True:\n  print(1)", editor.value

    editor.send_keys([ :meta, :enter ])
    assert_selector "h1", text: "Queued"
  end

  test "past runs are listed and can be opened, and a run can be run again" do
    sign_in users(:verified)
    assert_selector "tbody tr", count: 3

    click_link "raise RuntimeError('boom')"
    assert_selector "h1", text: "Failed"
    assert_text "RuntimeError: boom"

    click_link "Run again"
    assert_selector "h1", text: "New run"
    assert_field "Code", with: "raise RuntimeError('boom')"
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
    def sign_in(user)
      visit login_path
      fill_in "Email", with: user.email_address
      fill_in "Password", with: PASSWORD
      click_button "Sign in"
      assert_selector "h1", text: "Runs"
    end
end
