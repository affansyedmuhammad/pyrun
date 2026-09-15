require "test_helper"
require "rake"

class PyrunConfigTaskTest < ActiveSupport::TestCase
  setup do
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
  end

  test "pyrun:config prints every setting with secrets redacted" do
    with_config(smtp_password: "hunter2", sandbox_timeout_seconds: 42) do
      output = capture_io { Rake::Task["pyrun:config"].invoke }.first
      assert_match(/sandbox_timeout_seconds\s+42/, output)
      assert_match(/smtp_password\s+\[REDACTED\]/, output)
      assert_no_match(/hunter2/, output)
    end
  end
end
