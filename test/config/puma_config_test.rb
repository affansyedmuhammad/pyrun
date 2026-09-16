require "test_helper"
require "puma/configuration"
require "puma/plugin"

# config/puma.rb decides whether a Solid Queue supervisor runs inside the web
# process. That must follow the parsed boolean, never the mere presence of the
# variable: the web role has no Docker access, so a supervisor there claims
# sandbox jobs and fails every one of them instantly (this happened in
# production with SOLID_QUEUE_IN_PUMA=false, which Ruby treats as truthy).
class PumaConfigTest < ActiveSupport::TestCase
  PUMA_RB = Rails.root.join("config/puma.rb").to_s

  test "SOLID_QUEUE_IN_PUMA=false does not start Solid Queue inside Puma" do
    assert_not solid_queue_in_puma?("false")
  end

  test "an unset SOLID_QUEUE_IN_PUMA does not start Solid Queue inside Puma" do
    assert_not solid_queue_in_puma?(nil)
  end

  test "SOLID_QUEUE_IN_PUMA=true starts Solid Queue inside Puma" do
    assert solid_queue_in_puma?("true")
  end

  private
    # Evaluates config/puma.rb the way Puma does and reports whether it
    # registered the solid_queue plugin. Nothing is started.
    def solid_queue_in_puma?(value)
      previous = ENV["SOLID_QUEUE_IN_PUMA"]
      value.nil? ? ENV.delete("SOLID_QUEUE_IN_PUMA") : ENV["SOLID_QUEUE_IN_PUMA"] = value
      config = Puma::Configuration.new(config_files: [ PUMA_RB ])
      config.load
      solid_queue = Puma::Plugins.find("solid_queue")
      config.plugins.instance_variable_get(:@instances).any? { |plugin| plugin.is_a?(solid_queue) }
    ensure
      previous.nil? ? ENV.delete("SOLID_QUEUE_IN_PUMA") : ENV["SOLID_QUEUE_IN_PUMA"] = previous
    end
end
