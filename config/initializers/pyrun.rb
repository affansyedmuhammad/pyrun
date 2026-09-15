# The one place environment variables are read. Parsing happens at boot so a bad value
# fails the deploy instead of a request. `bin/rails pyrun:config` prints the result.
require Rails.root.join("lib/pyrun/config")

module Pyrun
  class << self
    attr_writer :config

    def config
      @config ||= Config.from_env(ENV)
    end
  end
end

Pyrun.config
