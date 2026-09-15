require "test_helper"

class AdminPolicyTest < ActiveSupport::TestCase
  test "admin when the address is listed, case-insensitively" do
    with_config(admin_emails: [ "boss@windbornesystems.com" ]) do
      assert AdminPolicy.admin?("boss@windbornesystems.com")
      assert AdminPolicy.admin?(" Boss@WindborneSystems.com ")
      assert_not AdminPolicy.admin?("peer@windbornesystems.com")
    end
  end

  test "nobody is admin when the list is empty" do
    assert_not AdminPolicy.admin?("boss@windbornesystems.com")
    assert_not AdminPolicy.admin?(nil)
  end
end
