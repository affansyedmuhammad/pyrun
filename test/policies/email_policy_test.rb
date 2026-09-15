require "test_helper"

class EmailPolicyTest < ActiveSupport::TestCase
  test "allows an exact match on a configured domain" do
    assert EmailPolicy.allowed?("someone@windbornesystems.com")
  end

  test "allows an address on the exact list even on another domain" do
    with_config(allowed_emails: [ "me@example.com" ]) do
      assert EmailPolicy.allowed?("me@example.com")
      assert_not EmailPolicy.allowed?("you@example.com")
    end
  end

  test "rejects other domains" do
    assert_not EmailPolicy.allowed?("someone@example.com")
  end

  test "rejects lookalike domains" do
    assert_not EmailPolicy.allowed?("a@windbornesystems.com.evil.example")
    assert_not EmailPolicy.allowed?("a@evilwindbornesystems.com")
    assert_not EmailPolicy.allowed?("a@windbornesystems.co")
    assert_not EmailPolicy.allowed?("a@xwindbornesystems.com")
  end

  test "rejects subdomains unless listed" do
    assert_not EmailPolicy.allowed?("a@mail.windbornesystems.com")
    with_config(allowed_email_domains: [ "windbornesystems.com", "mail.windbornesystems.com" ]) do
      assert EmailPolicy.allowed?("a@mail.windbornesystems.com")
    end
  end

  test "rejects addresses with more than one @" do
    assert_not EmailPolicy.allowed?("a@evil.example@windbornesystems.com")
  end

  test "is case-insensitive and ignores surrounding whitespace" do
    assert EmailPolicy.allowed?("  Someone@WindborneSystems.COM  ")
    with_config(allowed_emails: [ "me@example.com" ]) do
      assert EmailPolicy.allowed?("ME@Example.com")
    end
  end

  test "allows plus addressing and unicode local parts" do
    assert EmailPolicy.allowed?("someone+tag@windbornesystems.com")
    assert EmailPolicy.allowed?("jörg@windbornesystems.com")
  end

  test "rejects blank, nil, and malformed input" do
    assert_not EmailPolicy.allowed?(nil)
    assert_not EmailPolicy.allowed?("")
    assert_not EmailPolicy.allowed?("windbornesystems.com")
    assert_not EmailPolicy.allowed?("@windbornesystems.com")
  end

  test "allowed_domains exposes the configured list for copy" do
    assert_equal [ "windbornesystems.com" ], EmailPolicy.allowed_domains
    with_config(allowed_email_domains: [ "a.example", "b.example" ]) do
      assert_equal [ "a.example", "b.example" ], EmailPolicy.allowed_domains
    end
  end
end
