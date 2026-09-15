require "test_helper"

module Admin
  class UsersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = users(:admin)
    end

    test "members get a 404" do
      sign_in_as users(:verified)
      get admin_users_path
      assert_response :not_found
      post deactivate_admin_user_path(users(:unverified))
      assert_response :not_found
    end

    test "the Users link is in the header for admins only" do
      sign_in_as users(:verified)
      get runs_path
      assert_select "a[href=?]", admin_users_path, count: 0

      as_admin do
        get runs_path
        assert_select "a[href=?]", admin_users_path, text: "Users"
      end
    end

    test "admins see every account with status, admin badge, run count, and sign-in time" do
      users(:verified).update!(last_signed_in_at: 2.hours.ago)
      as_admin do
        get admin_users_path
      end
      assert_response :success
      assert_select "h1", "Users"
      rows = css_select("tbody tr")
      assert_equal User.count, rows.size

      verified_row = rows.find { |r| r.text.include?("verified@windbornesystems.com") && !r.text.include?("unverified@") }
      assert_match(/Active/, verified_row.text)
      assert_match(/3/, verified_row.css("td")[2].text) # runs
      assert_match(/about 2 hours ago/, verified_row.text)
      assert_select "a[href=?]", admin_runs_path(email: "verified@windbornesystems.com")

      admin_row = rows.find { |r| r.text.include?("admin@windbornesystems.com") }
      assert_match(/Admin/, admin_row.text)
      assert_match(/Unverified/, rows.find { |r| r.text.include?("unverified@") }.text)
      assert_match(/Disabled/, rows.find { |r| r.text.include?("former@") }.text)
    end

    test "admins can filter by email and by status" do
      as_admin do
        get admin_users_path(email: "former@")
        assert_equal 1, css_select("tbody tr").size
        assert_select "tbody tr", /former@windbornesystems\.com/

        get admin_users_path(status: "unverified")
        assert_equal 1, css_select("tbody tr").size
        assert_select "tbody tr", /unverified@/

        get admin_users_path(status: "disabled")
        assert_equal 1, css_select("tbody tr").size
      end
    end

    test "deactivating a user disables the account, ends their sessions, and is logged" do
      user = users(:verified)
      assert_operator user.sessions.count, :>, 0
      as_admin do
        assert_logged(/admin\.user_deactivated admin=#{@admin.id} user=#{user.id}/) do
          post deactivate_admin_user_path(user)
        end
      end
      assert_redirected_to admin_users_path
      assert user.reload.disabled?
      assert_empty user.sessions
      follow_redirect!
      assert_select ".flash-notice", /verified@windbornesystems\.com/
    end

    test "a deactivated user's existing session stops working immediately" do
      user = users(:verified)
      sign_in_as user
      get runs_path
      assert_response :success

      as_admin { post deactivate_admin_user_path(user) }

      sign_in_as_existing_cookie_of user
      get runs_path
      assert_redirected_to login_path
    end

    test "reactivating clears the flag" do
      user = users(:disabled)
      as_admin do
        assert_logged(/admin\.user_reactivated admin=#{@admin.id} user=#{user.id}/) do
          post reactivate_admin_user_path(user)
        end
      end
      assert_redirected_to admin_users_path
      assert_not user.reload.disabled?
    end

    test "signing a user out everywhere deletes their sessions and nothing else" do
      user = users(:verified)
      as_admin do
        assert_logged(/admin\.user_sessions_revoked admin=#{@admin.id} user=#{user.id}/) do
          delete sessions_admin_user_path(user)
        end
      end
      assert_redirected_to admin_users_path
      assert_empty user.reload.sessions
      assert_not user.disabled?
    end

    test "an admin cannot deactivate their own account" do
      as_admin do
        post deactivate_admin_user_path(@admin)
      end
      assert_redirected_to admin_users_path
      assert_not @admin.reload.disabled?
      follow_redirect!
      assert_select ".flash-alert", /your own account/
    end

    test "the list paginates" do
      30.times { |i| User.create!(email_address: "extra#{i}@windbornesystems.com", password: "Correct-Horse-Battery-9", password_confirmation: "Correct-Horse-Battery-9") }
      as_admin do
        get admin_users_path
        assert_equal 25, css_select("tbody tr").size
        assert_select "a[href=?]", admin_users_path(page: 2)
      end
    end

    private
      def as_admin(&block)
        with_config(admin_emails: [ @admin.email_address ]) do
          sign_in_as @admin
          block.call
        end
      end

      # The user signed in earlier; deactivation must have destroyed that session.
      def sign_in_as_existing_cookie_of(user)
        cookies[Authentication::SESSION_COOKIE] = @cookie_for ||= begin
          session = user.sessions.first || user.sessions.create!
          ActionDispatch::TestRequest.create.cookie_jar.tap { |jar| jar.signed[Authentication::SESSION_COOKIE] = session.id }[Authentication::SESSION_COOKIE]
        end
      end

      def assert_logged(pattern)
        io = StringIO.new
        previous = Rails.logger
        Rails.logger = ActiveSupport::BroadcastLogger.new(previous, ActiveSupport::Logger.new(io))
        yield
        assert_match pattern, io.string
      ensure
        Rails.logger = previous
      end
  end
end
