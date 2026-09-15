require "application_system_test_case"

class AdminUsersTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery staple"

  test "an admin reviews accounts, deactivates one, and brings it back" do
    with_config(admin_emails: [ users(:admin).email_address ]) do
      visit login_path
      fill_in "Email", with: users(:admin).email_address
      fill_in "Password", with: PASSWORD
      click_button "Sign in"
      assert_selector "h1", text: "Runs"

      click_link "Users"
      assert_selector "h1", text: "Users"
      assert_selector "tbody tr", count: User.count

      fill_in "Email", with: "verified@"
      click_button "Filter"
      assert_selector "tbody tr", count: 2 # verified@ and unverified@ both contain it

      within(:xpath, "//tr[td[normalize-space(.)='verified@windbornesystems.com']]") do
        assert_text "Active"
        click_button "Sign out everywhere" # the fixture session; deactivating below would end it anyway
      end
      assert_text "Signed verified@windbornesystems.com out everywhere"

      within(:xpath, "//tr[td[normalize-space(.)='verified@windbornesystems.com']]") do
        click_button "Deactivate"
      end
      assert_text "Deactivated verified@windbornesystems.com"
      within(:xpath, "//tr[td[normalize-space(.)='verified@windbornesystems.com']]") do
        assert_text "Disabled"
        click_button "Reactivate"
      end
      assert_text "Reactivated verified@windbornesystems.com"

      within(:xpath, "//tr[td[normalize-space(.)='verified@windbornesystems.com']]") do
        assert_no_text "Admin"
        click_button "Make admin"
      end
      assert_text "verified@windbornesystems.com is now an admin"
      within(:xpath, "//tr[td[contains(normalize-space(.), 'verified@windbornesystems.com') and not(contains(., 'unverified'))]]") do
        assert_selector ".tag", text: /admin/i # rendered uppercase by the stylesheet
        click_button "Remove admin"
      end
      assert_text "verified@windbornesystems.com is no longer an admin"

      within(:xpath, "//tr[td[normalize-space(.)='verified@windbornesystems.com']]") do
        click_button "Reset password"
      end
      assert_text "Sent a password reset link to verified@windbornesystems.com"
      mail = ActionMailer::Base.deliveries.last
      assert_equal [ "verified@windbornesystems.com" ], mail.to
      assert_equal "Reset your password", mail.subject
    end
  end
end
