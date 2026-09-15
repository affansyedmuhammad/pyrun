require "test_helper"

class RunsControllerTest < ActionDispatch::IntegrationTest
  test "the runs page asks anonymous visitors to sign in" do
    get runs_path
    assert_redirected_to login_path
  end

  test "a verified user with no runs sees an empty state" do
    sign_in_as users(:verified)
    get runs_path
    assert_response :success
    assert_select "h1", "Runs"
    assert_select "p", /No runs yet/
  end

  test "the root path is the runs page" do
    sign_in_as users(:verified)
    get root_path
    assert_response :success
    assert_select "h1", "Runs"
  end
end
