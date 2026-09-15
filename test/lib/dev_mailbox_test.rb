require "test_helper"
require "tmpdir"

# The development inbox: every mail the app sends is written to a folder and
# read back for /dev/mail. Development tooling, but it is code, so it is tested.
class DevMailboxTest < ActiveSupport::TestCase
  setup do
    @previous_location = DevMailbox.location
    DevMailbox.location = Pathname(Dir.mktmpdir("dev_mailbox"))
  end

  teardown do
    FileUtils.rm_rf(DevMailbox.location)
    DevMailbox.location = @previous_location
  end

  test "delivering writes one file per mail and messages reads them back newest first" do
    deliver(subject: "First", to: "a@windbornesystems.com", text: "one", html: "<p>one</p>")
    travel 1.minute do
      deliver(subject: "Second", to: "b@windbornesystems.com", text: "two", html: "<p>two</p>")
    end

    assert_equal 2, Dir.children(DevMailbox.location).size
    messages = DevMailbox.messages
    assert_equal [ "Second", "First" ], messages.map(&:subject)

    message = messages.last
    assert_equal [ "a@windbornesystems.com" ], message.to
    assert_equal "one", message.text.strip
    assert_equal "<p>one</p>", message.html.strip
    assert message.delivered_at.present?
    assert_match(/\A[\w-]+\z/, message.id)
  end

  test "find returns a message by id and refuses anything that is not a plain id" do
    deliver(subject: "Only", to: "a@windbornesystems.com", text: "x", html: "<p>x</p>")
    id = DevMailbox.messages.first.id
    assert_equal "Only", DevMailbox.find(id).subject

    assert_raises(DevMailbox::NotFound) { DevMailbox.find("does-not-exist") }
    assert_raises(DevMailbox::NotFound) { DevMailbox.find("../../config/master.key") }
    assert_raises(DevMailbox::NotFound) { DevMailbox.find("") }
  end

  test "links lists every URL in the text part" do
    deliver(subject: "Verify", to: "a@windbornesystems.com", text: "Open http://localhost:3000/verify-email/abc.def now", html: "<p>x</p>")
    assert_equal [ "http://localhost:3000/verify-email/abc.def" ], DevMailbox.messages.first.links
  end

  test "clear removes everything" do
    deliver(subject: "Gone", to: "a@windbornesystems.com", text: "x", html: "<p>x</p>")
    DevMailbox.clear
    assert_empty DevMailbox.messages
  end

  test "messages is empty when the folder does not exist yet" do
    FileUtils.rm_rf(DevMailbox.location)
    assert_equal [], DevMailbox.messages
  end

  private
    def deliver(subject:, to:, text:, html:)
      mail = Mail.new do
        from    "pyrun@localhost"
        to      to
        subject subject
        text_part { body text }
        html_part { content_type "text/html; charset=UTF-8"; body html }
      end
      DevMailbox::DeliveryMethod.new({}).deliver!(mail)
    end
end
