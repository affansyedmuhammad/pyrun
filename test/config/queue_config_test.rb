require "test_helper"

# config/queue.yml sets sandbox capacity and latency: the sandbox worker's thread
# count is how many containers run at once (validated against the host at boot),
# and its polling interval is the floor on how long a submitted run waits for a
# free worker.
class QueueConfigTest < ActiveSupport::TestCase
  test "the sandbox worker runs SANDBOX_CONCURRENCY threads and polls at least every 100 ms" do
    sandbox = workers.find { |w| Array(w["queues"]).include?("sandbox") }
    assert_equal Pyrun.config.sandbox_concurrency, sandbox["threads"]
    assert_operator sandbox["polling_interval"], :<=, 0.1
  end

  test "mail and broadcasts never share a worker with sandbox runs" do
    other = workers.find { |w| Array(w["queues"]).include?("mailers") }
    assert_includes Array(other["queues"]), "default"
    assert_not_includes Array(other["queues"]), "sandbox"
  end

  private
    def workers
      YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true).fetch(Rails.env).fetch("workers")
    end
end
