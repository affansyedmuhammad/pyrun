require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery staple"

  test "signing in and out" do
    sign_in users(:verified)
    assert_selector "h1", text: "Runs"
    assert_selector "header", text: users(:verified).email_address

    click_button "Sign out"
    assert_text "You have been signed out"
    assert_selector "h1", text: "Sign in"
  end

  test "a wrong password gets the generic message and keeps the email typed" do
    visit login_path
    fill_in "Email", with: users(:verified).email_address
    fill_in "Password", with: "not it, not it"
    click_button "Sign in"

    assert_text "Incorrect email or password."
    assert_field "Email", with: users(:verified).email_address
  end

  test "the runs page sends visitors to sign in and brings them back" do
    visit runs_path
    assert_current_path login_path

    fill_in "Email", with: users(:verified).email_address
    fill_in "Password", with: PASSWORD
    click_button "Sign in"
    assert_current_path runs_path
  end

  test "an unverified person is held at the pending page and can send the link again" do
    sign_in users(:unverified)
    assert_selector "h1", text: "Check your inbox"

    visit runs_path
    assert_selector "h1", text: "Check your inbox"

    click_button "Send it again"
    assert_text "We sent a new link"
    assert_equal [ users(:unverified).email_address ], ActionMailer::Base.deliveries.last.to
  end

  private
    def sign_in(user)
      visit login_path
      fill_in "Email", with: user.email_address
      fill_in "Password", with: PASSWORD
      click_button "Sign in"
    end
end
