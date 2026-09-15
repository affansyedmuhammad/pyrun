require "test_helper"

module Admin
  class RunsControllerTest < ActionDispatch::IntegrationTest
    test "members get a 404, not a hint that the page exists" do
      sign_in_as users(:verified)
      get admin_runs_path
      assert_response :not_found
    end

    test "the admin link is only in the header for admins" do
      sign_in_as users(:verified)
      get runs_path
      assert_select "a[href=?]", admin_runs_path, count: 0

      with_config(admin_emails: [ users(:admin).email_address ]) do
        sign_in_as users(:admin)
        get runs_path
        assert_select "a[href=?]", admin_runs_path, text: "All runs"
      end
    end

    test "admins see every run with its owner, newest first" do
      with_config(admin_emails: [ users(:admin).email_address ]) do
        sign_in_as users(:admin)
        get admin_runs_path
      end
      assert_response :success
      assert_select "h1", "All runs"
      rows = css_select("tbody tr")
      assert_equal Run.count, rows.size
      assert_match(/verified@windbornesystems\.com/, rows[0].text)
      assert_match(/admin@windbornesystems\.com/, rows.last.text)
    end

    test "each row opens the run with a marker so it comes back to All runs" do
      with_config(admin_emails: [ users(:admin).email_address ]) do
        sign_in_as users(:admin)
        get admin_runs_path
        assert_select "tbody tr a[href=?]", run_path(runs(:verified_failed), from: "all"), text: /raise RuntimeError/
        assert_select "tbody tr a", text: "Open", count: 0
      end
    end

    test "admins can filter by owner and status" do
      with_config(admin_emails: [ users(:admin).email_address ]) do
        sign_in_as users(:admin)
        get admin_runs_path(email: "admin@")
        assert_equal 1, css_select("tbody tr").size
        assert_select "tbody tr", /print\(2 \+ 2\)/

        get admin_runs_path(status: "failed")
        assert_equal 1, css_select("tbody tr").size
        assert_select "tbody tr", /verified@windbornesystems\.com/
      end
    end

    test "opening another person's run from the admin list is logged" do
      with_config(admin_emails: [ users(:admin).email_address ]) do
        sign_in_as users(:admin)
        assert_logged(/admin\.run_view admin=#{users(:admin).id} run=#{runs(:verified_failed).id}/) do
          get run_path(runs(:verified_failed))
        end
      end
    end

    private
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
