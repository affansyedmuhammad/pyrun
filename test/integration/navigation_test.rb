require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  test "signed-out pages have no sidebar, only the wordmark bar" do
    get login_path
    assert_select "aside", count: 0
    assert_select "header a[href=?]", root_path, text: "pyrun"
  end

  test "a signed-in member sees Runs in the sidebar with the current page marked, plus their address and sign out" do
    sign_in_as users(:verified)
    get runs_path
    assert_select "aside nav[aria-label=Main] a[href=?][aria-current=page]", runs_path, text: "Runs"
    assert_select "aside nav[aria-label=Main] a[href=?]", admin_runs_path, count: 0
    assert_select "aside nav[aria-label=Main] a[href=?]", admin_users_path, count: 0
    assert_select "aside", text: /verified@windbornesystems\.com/
    assert_select "aside form[action=?] button", logout_path, text: "Sign out"

    get new_run_path
    assert_select "aside nav a[href=?][aria-current=page]", runs_path, text: "Runs" # run pages belong to Runs

    get root_path
    assert_select "aside nav a[href=?][aria-current=page]", runs_path, text: "Runs" # the root is the runs page
  end

  test "an admin also sees All runs and Users, each marked only on its own pages" do
    with_config(admin_emails: [ users(:admin).email_address ]) do
      sign_in_as users(:admin)
      get admin_runs_path
      assert_select "aside nav a[href=?][aria-current=page]", admin_runs_path, text: "All runs"
      assert_select "aside nav a[href=?][aria-current=page]", runs_path, count: 0
      assert_select "aside nav a[href=?]", admin_users_path, text: "Users"

      get admin_users_path
      assert_select "aside nav a[href=?][aria-current=page]", admin_users_path, text: "Users"
      assert_select "aside nav a[href=?][aria-current=page]", admin_runs_path, count: 0
    end
  end

  test "an unverified user gets no navigation, just a way out" do
    sign_in_as users(:unverified)
    get pending_email_verification_path
    assert_select "aside nav a[href=?]", runs_path, count: 0
    assert_select "aside form[action=?] button", logout_path, text: "Sign out"
  end
end
