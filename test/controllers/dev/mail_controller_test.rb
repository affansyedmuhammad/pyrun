require "test_helper"
require "tmpdir"

module Dev
  class MailControllerTest < ActionDispatch::IntegrationTest
    setup do
      @previous_location = DevMailbox.location
      DevMailbox.location = Pathname(Dir.mktmpdir("dev_mailbox"))
    end

    teardown do
      FileUtils.rm_rf(DevMailbox.location)
      DevMailbox.location = @previous_location
    end

    test "the inbox needs no login and shows an empty state" do
      get dev_mail_path
      assert_response :success
      assert_select "h1", "Mail"
      assert_select "p", /Nothing has been sent yet/
    end

    test "the inbox lists delivered mail newest first" do
      DevMailbox::DeliveryMethod.new({}).deliver!(UserMailer.email_verification(users(:unverified)))
      travel 1.minute do
        DevMailbox::DeliveryMethod.new({}).deliver!(UserMailer.password_reset(users(:verified)))
      end
      get dev_mail_path
      rows = css_select("tbody tr")
      assert_equal 2, rows.size
      assert_match(/Reset your password/, rows[0].text)
      assert_match(/verified@windbornesystems\.com/, rows[0].text)
      assert_match(/Verify your email address/, rows[1].text)
    end

    test "a message shows its text with every link clickable" do
      DevMailbox::DeliveryMethod.new({}).deliver!(UserMailer.email_verification(users(:unverified)))
      message = DevMailbox.messages.first
      get dev_mail_message_path(message.id)
      assert_response :success
      assert_select "h1", "Verify your email address"
      assert_select "dd", /unverified@windbornesystems\.com/
      assert_select "a[href^=?]", "http://localhost:3000/verify-email/", text: /verify-email/
      assert_select "a[href=?]", dev_mail_path
    end

    test "an unknown or unsafe id is not found" do
      get dev_mail_message_path("nope")
      assert_response :not_found
      get "/dev/mail/..%2F..%2Fconfig%2Fmaster.key"
      assert_response :not_found
    end

    test "clearing empties the inbox" do
      DevMailbox::DeliveryMethod.new({}).deliver!(UserMailer.email_verification(users(:unverified)))
      delete dev_mail_path
      assert_redirected_to dev_mail_path
      assert_empty DevMailbox.messages
    end

    test "the inbox is only ever routed outside production" do
      routes = File.read(Rails.root.join("config/routes.rb"))
      assert_match(/if Rails\.env\.local\?\n(.*\n)*?.*dev\/mail/, routes, "the dev mailbox routes must sit inside the Rails.env.local? guard")
    end
  end
end
