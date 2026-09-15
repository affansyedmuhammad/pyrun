module Pyrun
  # Refuses request bodies over a fixed size with 413 before Rails parses anything.
  # Sits first in the middleware stack. The limit is far above the code cap
  # (MAX_CODE_BYTES) so legitimate submissions are never refused, and far below
  # anything that could tie up a worker.
  class RequestSizeLimit
    MAX_BYTES = 1_000_000

    def initialize(app, max_bytes: MAX_BYTES)
      @app = app
      @max_bytes = max_bytes
    end

    def call(env)
      if env["CONTENT_LENGTH"].to_i > @max_bytes
        return [ 413, { "content-type" => "text/plain; charset=utf-8" }, [ "Request body too large.\n" ] ]
      end
      @app.call(env)
    end
  end
end
