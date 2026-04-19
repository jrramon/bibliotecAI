require "test_helper"

class InvitationsMailerTest < ActionMailer::TestCase
  test "invite" do
    mail = InvitationsMailer.invite
    assert_equal "Invite", mail.subject
    assert_equal ["to@example.org"], mail.to
    assert_equal ["from@example.com"], mail.from
    assert_match "Hi", mail.body.encoded
  end
end
