require "application_system_test_case"

class PasswordResetTest < ApplicationSystemTestCase
  NEW_PASSWORD = "A-brand-new-passphrase-7"

  test "resetting a forgotten password from the sign-in page" do
    user = users(:verified)

    visit login_path
    click_link "Forgot your password?"
    assert_selector "h1", text: "Reset your password"
    fill_in "Email", with: user.email_address
    click_button "Send reset link"
    assert_text "If an account exists for that email"

    visit path_from_mail(ActionMailer::Base.deliveries.last, "/passwords/")
    assert_selector "h1", text: "Choose a new password"
    fill_in "New password", with: NEW_PASSWORD
    fill_in "Confirm password", with: NEW_PASSWORD
    click_button "Update password"
    assert_text "Password updated"

    fill_in "Email", with: user.email_address
    fill_in "Password", with: NEW_PASSWORD
    click_button "Sign in"
    assert_selector "h1", text: "Runs"
  end
end
