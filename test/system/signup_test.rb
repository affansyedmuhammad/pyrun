require "application_system_test_case"

class SignupTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery staple"

  test "a new person signs up, verifies by email, and lands on their runs" do
    visit signup_path
    fill_in "Email", with: "new.person@windbornesystems.com"
    fill_in "Password", with: PASSWORD
    fill_in "Confirm password", with: PASSWORD
    click_button "Create account"

    assert_text "Check your inbox"
    assert_text "new.person@windbornesystems.com"

    visit path_from_mail(ActionMailer::Base.deliveries.last, "/verify-email/")
    assert_text "Email verified"
    assert_text "No runs yet"
    assert_selector "header", text: "new.person@windbornesystems.com"
  end

  test "an address outside the company is refused inline" do
    visit signup_path
    fill_in "Email", with: "someone@example.com"
    fill_in "Password", with: PASSWORD
    fill_in "Confirm password", with: PASSWORD
    click_button "Create account"

    assert_text "Sign-ups are limited to windbornesystems.com addresses."
    assert_field "Email", with: "someone@example.com"
  end

  test "a weak password is explained before anything is created" do
    visit signup_path
    fill_in "Email", with: "new.person@windbornesystems.com"
    fill_in "Password", with: "short"
    fill_in "Confirm password", with: "short"
    click_button "Create account"

    assert_text "minimum is 12 characters"
    assert_nil User.find_by(email_address: "new.person@windbornesystems.com")
  end
end
