require "test_helper"

# Every route is private unless it is on this list, so a new route cannot be
# forgotten. Anonymous requests must be sent to the login page or get a 404.
class RouteCoverageTest < ActionDispatch::IntegrationTest
  PUBLIC = [
    [ "GET", "/login" ], [ "POST", "/login" ],
    [ "GET", "/signup" ], [ "POST", "/signup" ],
    [ "GET", "/passwords/new" ], [ "POST", "/passwords" ],
    [ "GET", "/passwords/:token/edit" ], [ "PATCH", "/passwords/:token" ], [ "PUT", "/passwords/:token" ],
    [ "GET", "/up" ]
  ].freeze

  test "every route not on the public list rejects anonymous requests" do
    checked = 0
    app_routes.each do |verb, spec|
      next if PUBLIC.include?([ verb, spec ])

      process(verb.downcase.to_sym, spec.gsub(/:\w+/, "1"))
      checked += 1
      assert_includes [ 302, 303, 404 ], response.status, "#{verb} #{spec} answered #{response.status} to an anonymous request"
      assert_equal login_url, response.location, "#{verb} #{spec} should send anonymous users to sign in" if response.redirect?
    end
    assert_operator checked, :>, 0
  end

  test "the public list only names routes that exist" do
    PUBLIC.each do |verb, spec|
      assert_includes app_routes, [ verb, spec ], "#{verb} #{spec} is on the public list but not in the routes"
    end
  end

  private
    def app_routes
      Rails.application.routes.routes.flat_map do |route|
        spec = route.path.spec.to_s.sub("(.:format)", "")
        next [] if route.verb.blank? || spec.start_with?("/rails/", "/assets")
        route.verb.split("|").map { |verb| [ verb, spec ] }
      end
    end
end
