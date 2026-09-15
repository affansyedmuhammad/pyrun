require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "email_verification carries a link that resolves to the user" do
    user = users(:unverified)
    mail = UserMailer.email_verification(user)
    assert_equal [ user.email_address ], mail.to
    assert_equal [ Pyrun.config.mail_from ], mail.from
    assert_equal "Verify your email address", mail.subject
    assert_includes mail.text_part.body.to_s, "24 hours"

    token = link_token(mail, "/verify-email/")
    assert_equal user, User.find_by_token_for(:email_verification, token)
  end

  test "password_reset carries a link that resolves to the user" do
    user = users(:verified)
    mail = UserMailer.password_reset(user)
    assert_equal [ user.email_address ], mail.to
    assert_equal "Reset your password", mail.subject
    assert_includes mail.text_part.body.to_s, "15 minutes"

    token = link_token(mail, "/passwords/", "/edit")
    assert_equal user, User.find_by_token_for(:password_reset, token)
  end

  test "existing_account tells the owner someone tried to sign up and offers a reset" do
    user = users(:verified)
    mail = UserMailer.existing_account(user)
    assert_equal [ user.email_address ], mail.to
    assert_equal "You already have an account", mail.subject
    assert_includes mail.text_part.body.to_s, "Someone tried to sign up"

    token = link_token(mail, "/passwords/", "/edit")
    assert_equal user, User.find_by_token_for(:password_reset, token)
  end

  test "every mail has both a text and an html part" do
    user = users(:verified)
    [ UserMailer.email_verification(user), UserMailer.password_reset(user), UserMailer.existing_account(user) ].each do |mail|
      assert mail.text_part, "#{mail.subject} has no text part"
      assert mail.html_part, "#{mail.subject} has no html part"
    end
  end

  test "links use the configured host, not whatever the request said" do
    with_config(app_host: "run.example.com") do
      mail = UserMailer.email_verification(users(:unverified))
      assert_includes mail.text_part.body.to_s, "http://run.example.com/verify-email/"
    end
  end

  private
    def link_token(mail, prefix, suffix = "")
      body = mail.text_part.body.to_s
      match = body.match(%r{https?://[^/\s]+#{Regexp.escape(prefix)}([^\s/]+)#{Regexp.escape(suffix)}})
      assert match, "no link with #{prefix} in:\n#{body}"
      match[1]
    end
end
