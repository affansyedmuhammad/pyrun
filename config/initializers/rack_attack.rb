# A per-address brake in front of the whole app. The per-action limits on
# sign-in, signup, reset, and submissions live in the controllers; this one
# stops a single address from hammering anything at all.
Rack::Attack.cache.store = Rails.cache

Rack::Attack.safelist("health check") { |request| request.path == "/up" }

Rack::Attack.throttle("requests per address",
                      limit: ->(_request) { Pyrun.config.request_rate_limit_count },
                      period: ->(_request) { Pyrun.config.request_rate_limit_period.to_i }) do |request|
  request.ip
end

Rack::Attack.throttled_responder = lambda do |request|
  retry_after = request.env["rack.attack.match_data"]&.dig(:period).to_i
  [ 429, { "content-type" => "text/plain; charset=utf-8", "retry-after" => retry_after.to_s }, [ "Too many requests. Try again in a minute.\n" ] ]
end
