# Everything that touches a sandbox lives under this namespace. The rest of the
# app only ever calls Sandbox.runner and reads Sandbox::Result.
module Sandbox
  def self.runner
    case Pyrun.config.sandbox_runner
    when "fake" then FakeRunner.new
    else DockerRunner.new
    end
  end
end
