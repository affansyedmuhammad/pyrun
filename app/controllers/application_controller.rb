class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private
    # Shared handler for every rate_limit declaration.
    def rate_limited
      render "shared/rate_limited", layout: "auth", status: :too_many_requests
    end
end
