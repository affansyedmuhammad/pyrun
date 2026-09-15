require "test_helper"

class RequestSizeLimitTest < ActionDispatch::IntegrationTest
  test "a request body over the limit is refused before it reaches the app" do
    sign_in_as users(:verified)
    post runs_path, params: { run: { code: "x" * (Pyrun::RequestSizeLimit::MAX_BYTES + 1) } }
    assert_response :content_too_large
    assert_no_difference "Run.count" do
      post runs_path, params: { run: { code: "x" * (Pyrun::RequestSizeLimit::MAX_BYTES + 1) } }
    end
  end

  test "the limit sits well above the code cap so real submissions are never refused" do
    assert_operator Pyrun::RequestSizeLimit::MAX_BYTES, :>, Pyrun.config.max_code_bytes * 4
  end
end
