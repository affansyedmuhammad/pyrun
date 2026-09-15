require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  test "an address making too many requests in a minute is throttled" do
    with_config(request_rate_limit: [ 5, 60 ]) do
      5.times do
        get login_path
        assert_response :success
      end
      get login_path
      assert_response :too_many_requests
      assert_includes response.body, "Too many requests"
    end
  end

  test "the health check is never throttled" do
    with_config(request_rate_limit: [ 2, 60 ]) do
      5.times { get "/up" }
      assert_response :success
    end
  end

  test "the throttle is per address" do
    with_config(request_rate_limit: [ 2, 60 ]) do
      3.times { get login_path, headers: { "REMOTE_ADDR" => "10.9.0.1" } }
      assert_response :too_many_requests
      get login_path, headers: { "REMOTE_ADDR" => "10.9.0.2" }
      assert_response :success
    end
  end
end
