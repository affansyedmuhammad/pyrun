require "test_helper"
require "minitest/mock"

module Sandbox
  class RuntimeTest < ActiveSupport::TestCase
    test "all loads the registry in file order and the first entry is the default" do
      assert_equal [ "python3.12" ], Runtime.all.map(&:key)
      assert_equal "python3.12", Runtime.default.key
      assert_equal [ "python3.12" ], Runtime.keys
    end

    test "find returns a frozen definition with label, image, and command" do
      runtime = Runtime.find("python3.12")
      assert runtime.frozen?
      assert_equal "Python 3.12", runtime.label
      assert_equal %w[python3 -I -u -], runtime.command
      assert_equal Pyrun.config.sandbox_image, runtime.image
    end

    test "find raises for an unknown key" do
      assert_raises(Runtime::Unknown) { Runtime.find("cobol") }
      assert_raises(Runtime::Unknown) { Runtime.find(nil) }
    end

    test "an entry without its own image runs the configured sandbox image" do
      with_config(sandbox_image: "pyrun-sandbox:abc123") do
        assert_equal "pyrun-sandbox:abc123", Runtime.find("python3.12").image
      end
    end

    test "an entry can pin its own image" do
      Runtime.stub :registry, { "py" => { "label" => "Py", "image" => "pinned:1", "command" => [ "python3" ] } } do
        assert_equal "pinned:1", Runtime.find("py").image
      end
    end
  end
end
