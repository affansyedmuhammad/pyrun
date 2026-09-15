require "application_system_test_case"

class SignupTest < ApplicationSystemTestCase
  PASSWORD = "Correct-Horse-Battery-9"

  test "a new person signs up, verifies by email, and lands on their runs" do
    visit signup_path
    fill_in "Email", with: "new.person@windbornesystems.com"
    fill_in "Password", with: PASSWORD
    fill_in "Confirm password", with: PASSWORD
    click_button "Create account"

    assert_text "Check your inbox"
    assert_text "new.person@windbornesystems.com"

    click_button "Send it again"
    assert_text "We sent a new link to new.person@windbornesystems.com"
    assert_equal 2, ActionMailer::Base.deliveries.size

    visit path_from_mail(ActionMailer::Base.deliveries.last, "/verify-email/")
    assert_text "Email verified"
    assert_text "No runs yet"
    assert_selector "aside", text: "new.person@windbornesystems.com"
  end

  test "an address outside the company is refused inline" do
    visit signup_path
    fill_in "Email", with: "someone@example.com"
    fill_in "Password", with: PASSWORD
    fill_in "Confirm password", with: PASSWORD
    click_button "Create account"

    assert_selector ".field-error", text: "Sign-ups are limited to windbornesystems.com addresses."
    assert_field "Email", with: "someone@example.com"
  end

  test "a weak password is explained before anything is created" do
    visit signup_path
    fill_in "Email", with: "new.person@windbornesystems.com"
    fill_in "Password", with: "short"
    fill_in "Confirm password", with: "short"
    click_button "Create account"

    assert_selector ".field-error", text: "at least 12 characters"
    assert_nil User.find_by(email_address: "new.person@windbornesystems.com")
  end

  test "the password checklist ticks each rule as you type" do
    visit signup_path
    assert_selector "ul.rules li[data-met=false]", count: 5

    fill_in "Password", with: "short"
    assert_selector "ul.rules li[data-met=true]", count: 1, text: "A lowercase letter"

    fill_in "Password", with: "Correct-Horse-Battery-9"
    assert_selector "ul.rules li[data-met=true]", count: 5
    assert_no_selector "ul.rules li[data-met=false]"
  end

  test "the eye toggle reveals and hides the password" do
    visit signup_path
    fill_in "Password", with: "Correct-Horse-Battery-9"
    assert_equal "password", find_field("Password")["type"]

    click_button "Show password", match: :first
    assert_equal "text", find_field("Password")["type"]
    assert_selector "button[aria-label='Hide password'][aria-pressed=true]"

    click_button "Hide password"
    assert_equal "password", find_field("Password")["type"]
  end
end
