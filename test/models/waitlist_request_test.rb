require "test_helper"

class WaitlistRequestTest < ActiveSupport::TestCase
  test "valid with just an email" do
    assert WaitlistRequest.new(email: "alice@example.com").valid?
  end

  test "rejects an invalid email format" do
    refute WaitlistRequest.new(email: "not-an-email").valid?
  end

  test "downcases and strips email on save" do
    r = WaitlistRequest.create!(email: "  Alice@Example.COM  ")
    assert_equal "alice@example.com", r.email
  end

  test "email is unique case-insensitively" do
    WaitlistRequest.create!(email: "alice@example.com")
    refute WaitlistRequest.new(email: "ALICE@example.com").valid?
  end

  test "note has a 500 char cap" do
    r = WaitlistRequest.new(email: "a@b.com", note: "x" * 501)
    refute r.valid?
  end
end
