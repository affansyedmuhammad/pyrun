# The framework filters query parameters in the logged request path but never
# path segments (ActionDispatch::Http::FilterParameters#filtered_path). Our
# reset and verification tokens ride in the path, so they would otherwise land
# in the request log in clear text. Redact those segments before the path
# reaches any log line. See docs/SECURITY-REVIEW.md, finding 1.
module Pyrun
  module FilteredRequestPath
    # /passwords/<token>[/edit] and /verify-email/<token>. "new" is a real
    # sub-route, not a token, so it stays readable.
    PASSWORD_TOKEN = %r{\A(/passwords)/(?!new(?:/|\z))[^/]+}
    VERIFY_TOKEN   = %r{\A(/verify-email)/[^/]+}

    def filtered_path
      super
        .sub(PASSWORD_TOKEN) { "#{$1}/[FILTERED]" }
        .sub(VERIFY_TOKEN)   { "#{$1}/[FILTERED]" }
    end
  end
end

ActiveSupport.on_load(:action_dispatch_request) do
  prepend Pyrun::FilteredRequestPath
end
