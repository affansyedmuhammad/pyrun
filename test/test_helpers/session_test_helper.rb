module SessionTestHelper
  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[Authentication::SESSION_COOKIE] = Current.session.id
      cookies[Authentication::SESSION_COOKIE] = cookie_jar[Authentication::SESSION_COOKIE]
    end
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete(Authentication::SESSION_COOKIE)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
